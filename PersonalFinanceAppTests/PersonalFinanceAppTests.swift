//
//  LedgerStoreTests.swift
//  Nokael Money
//
//  The store against an in-memory database: persistence, idempotency, audit,
//  edits, bill payments and reconciliation.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct LedgerStoreTests {
    static let dubai: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return c
    }()
    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        dubai.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    // Held for the test's lifetime: a context outlived by its container traps on fetch
    let container: ModelContainer
    let store: LedgerStore
    let today = date(2026, 10, 25)

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: Self.dubai, now: { now })
        try store.addStarterCategories()
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.name == name }!
    }

    @Test("ONB-05: setup adds no transactions or balances by itself")
    func noFabricatedRecords() {
        #expect(store.snapshot.entryRecords.isEmpty)
        #expect(store.snapshot.accounts.isEmpty)
        #expect(store.snapshot.safeToSpend().amount == nil)
    }

    @Test("QA-01: an opening balance shows straight away")
    func openingBalance() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(12000), openingDate: today)
        #expect(store.snapshot.balance(account.id) == Self.aed(12000))
        #expect(store.snapshot.netWorth.total == Self.aed(12000))
    }

    @Test("QA-08: saving the same entry twice commits it once")
    func idempotentSave() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(500), openingDate: today)
        let key = UUID()
        let spend = try EntryFactory.expense(Self.aed(85), from: account.info, category: category("Groceries").info,
                                             date: today, memo: "Carrefour", key: key)
        let first = try store.post(spend)
        // A retry builds a new entry with the same key, as the editor does
        let retry = try EntryFactory.expense(Self.aed(85), from: account.info, category: category("Groceries").info,
                                             date: today, memo: "Carrefour", key: key)
        let second = try store.post(retry)
        #expect(first == second)
        #expect(store.snapshot.entries().count == 1)
        #expect(store.snapshot.balance(account.id) == Self.aed(415))
    }

    @Test("QA-09 / TX-08: editing keeps history and recalculates")
    func editKeepsHistory() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: today)
        let original = try store.post(try EntryFactory.expense(Self.aed(50), from: account.info, category: category("Groceries").info,
                                                                date: today, memo: "Spinneys"))
        let replacement = try EntryFactory.expense(Self.aed(60), from: account.info, category: category("Transport").info,
                                                   date: today, memo: "Taxi")
        try store.replace(original, with: replacement)

        let s = store.snapshot
        #expect(s.balance(account.id) == Self.aed(940))
        #expect(s.budget.spent(category("Groceries").id, month: s.monthKey).isZero)
        #expect(s.budget.spent(category("Transport").id, month: s.monthKey) == Self.aed(60))
        #expect(s.entries(includeVoided: true).count == 2)              // original kept, voided
        #expect(store.auditTrail.contains { $0.action == "entry.edited" })
    }

    @Test func deletingIsAuditedAndReversible() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(100), openingDate: today)
        let id = try store.post(try EntryFactory.expense(Self.aed(40), from: account.info, category: category("Groceries").info, date: today))
        try store.void(id, reason: "Duplicate")
        #expect(store.snapshot.balance(account.id) == Self.aed(100))
        #expect(store.auditTrail.first { $0.action == "entry.voided" }?.reason == "Duplicate")
    }

    @Test("QA-05 / BILL-03: paying a bill links it and isn't counted twice")
    func payingABill() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(12000), openingDate: today)
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2800),
                               schedule: Schedule(start: Self.date(2026, 10, 28), frequency: .monthly(every: 1)),
                               accountId: account.id, categoryId: category("Rent or mortgage").id)
        try store.savePlannedItem(rent)
        let before = store.snapshot.safeToSpend(through: Self.date(2026, 10, 31)).amount
        #expect(before == Self.aed(12000 - 2800))

        let occ = try #require(store.snapshot.occurrences.first)
        let key = UUID()
        try store.pay(occurrenceId: occ.id, amount: Self.aed(2800), accountId: account.id, categoryId: nil, date: today, key: key)
        // A double tap on "Record payment"
        try store.pay(occurrenceId: occ.id, amount: Self.aed(2800), accountId: account.id, categoryId: nil, date: today, key: key)

        let s = store.snapshot
        #expect(s.balance(account.id) == Self.aed(9200))
        #expect(s.safeToSpend(through: Self.date(2026, 10, 31)).amount == before)
        #expect(s.state(of: s.occurrences.first { $0.id == occ.id }!) == .paid)
    }

    @Test("Reminders follow each bill's choice and stop once it's paid")
    func billReminders() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(12000), openingDate: today)
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2800),
                               schedule: Schedule(start: Self.date(2026, 10, 28), frequency: .monthly(every: 1)),
                               accountId: account.id, categoryId: category("Rent or mortgage").id)
        try store.savePlannedItem(rent, reminderDays: 1)
        let first = try #require(store.snapshot.billReminders(hour: 9, now: today).first)
        #expect(first.fireDate == Self.dubai.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9)))

        // Saving again without a choice keeps it; paying removes that due date's reminder
        try store.savePlannedItem(rent)
        #expect(store.snapshot.reminderDays(for: rent.id) == 1)
        try store.pay(occurrenceId: first.occurrenceId, amount: Self.aed(2800), accountId: account.id, categoryId: nil,
                      date: today, key: UUID())
        #expect(!store.snapshot.billReminders(hour: 9, now: today).contains { $0.occurrenceId == first.occurrenceId })

        try store.savePlannedItem(rent, reminderDays: -1)
        #expect(store.snapshot.billReminders(hour: 9, now: today).isEmpty)
    }

    @Test("Importing a statement adds spending, transfers and bill payments once, however often it's run")
    func importingAStatement() throws {
        let current = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(10000), openingDate: today)
        let card = try store.createAccount(name: "Card", kind: .creditCard, opening: Self.aed(-1000), openingDate: today)
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2800),
                               schedule: Schedule(start: Self.date(2026, 10, 28), frequency: .monthly(every: 1)),
                               accountId: current.id, categoryId: category("Rent or mortgage").id)
        try store.savePlannedItem(rent)
        let occ = try #require(store.snapshot.occurrences.first)
        let rows = [
            LedgerStore.ImportedRow(date: today, memo: "Carrefour", amount: Self.aed(-150),
                                    target: .category(category("Groceries").id), key: UUID()),
            LedgerStore.ImportedRow(date: today, memo: "Card payment", amount: Self.aed(-500),
                                    target: .transfer(card.id), key: UUID()),
            LedgerStore.ImportedRow(date: today, memo: "Rent", amount: Self.aed(-2800), target: .bill(occ.id), key: UUID()),
        ]
        try store.importRows(rows, into: current.id)
        try store.importRows(rows, into: current.id)

        let s = store.snapshot
        #expect(s.balance(current.id) == Self.aed(10000 - 150 - 500 - 2800))
        #expect(s.balance(card.id) == Self.aed(-500))
        #expect(s.state(of: s.occurrences.first { $0.id == occ.id }!) == .paid)
        #expect(s.entries().count == 3)
    }

    @Test("BILL-05: editing a bill only changes future unpaid ones")
    func editingABill() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(9000), openingDate: today)
        var rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2800),
                               schedule: Schedule(start: Self.date(2026, 10, 28), frequency: .monthly(every: 1)),
                               accountId: account.id, categoryId: category("Rent or mortgage").id)
        try store.savePlannedItem(rent)
        let first = try #require(store.snapshot.occurrences.first)
        try store.pay(occurrenceId: first.id, amount: Self.aed(2800), accountId: account.id, categoryId: nil, date: today, key: UUID())

        rent.amount = Self.aed(3000)
        try store.savePlannedItem(rent)
        let occs = store.snapshot.occurrences
        #expect(occs.first { $0.id == first.id }?.expected == Self.aed(2800))
        #expect(occs.filter { $0.id != first.id }.allSatisfy { $0.expected == Self.aed(3000) })
    }

    @Test("Matching an existing payment instead of recording it again")
    func matchingAPayment() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(5000), openingDate: today)
        let bill = PlannedItem(name: "DEWA", direction: .outflow, amount: Self.aed(400), isEstimate: true,
                               schedule: Schedule(start: Self.date(2026, 10, 27), frequency: .monthly(every: 1)),
                               accountId: account.id, categoryId: category("Utilities").id)
        try store.savePlannedItem(bill)
        let paid = try store.post(try EntryFactory.expense(Self.aed(437), from: account.info, category: category("Utilities").info,
                                                           date: today, memo: "DEWA"))
        let occ = try #require(store.snapshot.occurrences.first)
        try store.match(occurrenceId: occ.id, entryId: paid)
        let matched = try #require(store.snapshot.occurrences.first { $0.id == occ.id })
        #expect(matched.expected == Self.aed(437))   // estimate settled at the real amount
        #expect(matched.remaining.isZero)
        #expect(store.snapshot.balance(account.id) == Self.aed(4563)) // spent once
    }

    @Test("REC-02/03: reconciling records a reasoned adjustment")
    func reconcile() throws {
        let account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: Self.date(2026, 10, 1))
        #expect(throws: StoreError.self) {
            try store.reconcile(accountId: account.id, statementDate: today, statementBalance: Self.aed(990), reason: nil)
        }
        try store.reconcile(accountId: account.id, statementDate: today, statementBalance: Self.aed(990), reason: "Bank fee")
        #expect(store.snapshot.balance(account.id) == Self.aed(990))
        #expect(store.snapshot.account(account.id)?.lastReconciledAt != nil)
        #expect(store.auditTrail.contains { $0.action == "account.reconciled" && $0.reason == "Bank fee" })
    }

    @Test("CAT-04: allocation changes are kept as history and moves conserve totals")
    func allocations() throws {
        _ = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(5000), openingDate: today)
        let month = store.snapshot.monthKey
        let groceries = category("Groceries").id
        let transport = category("Transport").id
        try store.setAllocation(Self.aed(600), categoryId: groceries, month: month)
        try store.setAllocation(Self.aed(500), categoryId: groceries, month: month)
        #expect(store.fetch(AllocationRecord.self).count == 2)
        #expect(store.snapshot.budget.allocated(groceries, month: month) == Self.aed(500))

        let before = store.snapshot.budget.availableToAllocate(month: month)
        try store.moveAllocation(Self.aed(200), from: groceries, to: transport, month: month)
        #expect(store.snapshot.budget.availableToAllocate(month: month) == before)
        #expect(throws: StoreError.self) {
            try store.moveAllocation(Self.aed(900), from: groceries, to: transport, month: month)
        }
    }

    @Test("Transfers between owned accounts leave net worth unchanged")
    func transfers() throws {
        let a = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(3000), openingDate: today)
        let b = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(0), openingDate: today)
        let before = store.snapshot.netWorth.total
        try store.post(try EntryFactory.transfer(Self.aed(1000), from: a.info, to: b.info, date: today))
        #expect(store.snapshot.netWorth.total == before)
    }

    // MARK: Debts

    private func carLoan(owing: Decimal = 30000) throws -> (bank: LedgerAccountRecord, loan: LedgerAccountRecord) {
        let bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(12000), openingDate: today)
        let loan = try store.createAccount(name: "Car loan", kind: .loan, opening: Self.aed(-owing), openingDate: today)
        return (bank, loan)
    }

    @Test("QA-07: a loan payment lowers the debt by the principal and counts interest as spending")
    func payingALoan() throws {
        let (bank, loan) = try carLoan()
        let key = UUID()
        try store.payDebt(loan.id, from: bank.id, amount: Self.aed(1000), interest: Self.aed(150), fees: Self.aed(0),
                          date: today, key: key)
        // A double tap records it once
        try store.payDebt(loan.id, from: bank.id, amount: Self.aed(1000), interest: Self.aed(150), fees: Self.aed(0),
                          date: today, key: key)
        let s = store.snapshot
        #expect(s.balance(bank.id) == Self.aed(11000))
        #expect(s.owed(loan.id) == Self.aed(29150))
        // The budget counts the whole instalment: the principal left the budget too
        #expect(s.budget.spent(category("Loan payments").id, month: s.monthKey) == Self.aed(1000))
        #expect(s.netWorth.total == Self.aed(12000 - 30000 - 150))
    }

    @Test func overpayingADebtIsRefused() throws {
        let (bank, loan) = try carLoan(owing: 500)
        #expect(throws: StoreError.self) {
            try store.payDebt(loan.id, from: bank.id, amount: Self.aed(800), interest: Self.aed(0), fees: Self.aed(0),
                              date: today, key: UUID())
        }
        #expect(throws: StoreError.self) {
            try store.payDebt(loan.id, from: bank.id, amount: Self.aed(100), interest: Self.aed(80), fees: Self.aed(30),
                              date: today, key: UUID())
        }
        #expect(store.snapshot.owed(loan.id) == Self.aed(500))
    }

    @Test("A debt's monthly payment becomes a bill that's reserved in safe-to-spend")
    func termsCreateABill() throws {
        let (bank, loan) = try carLoan()
        let before = store.snapshot.safeToSpend(through: Self.date(2026, 11, 30)).amount
        try store.saveDebtTerms(DebtTerms(annualRateBps: 600, monthlyPayment: Self.aed(1000), dueDay: 5),
                                for: loan.id, paidFrom: bank.id)
        let s = store.snapshot
        let item = try #require(s.paymentItem(for: loan.id))
        #expect(item.amount == Self.aed(1000))
        #expect(item.accountId == bank.id)
        let first = try #require(s.occurrences.first { $0.itemId == item.id })
        #expect(Self.dubai.dateComponents([.month, .day], from: first.dueDate) == DateComponents(month: 11, day: 5))
        #expect(s.safeToSpend(through: Self.date(2026, 11, 30)).amount == before.map { $0 - Self.aed(1000) })
        // 30,000 at 6% with 1,000 a month: 33 payments
        guard case let .paidOff(months, _, _, _) = try #require(s.payoff(for: s.account(loan.id)!)) else {
            Issue.record("expected a payoff date"); return
        }
        #expect(months == 33)

        // Changing the payment updates the same bill; removing the terms stops it
        try store.saveDebtTerms(DebtTerms(annualRateBps: 600, monthlyPayment: Self.aed(1200), dueDay: 5),
                                for: loan.id, paidFrom: bank.id)
        #expect(store.snapshot.items.filter { $0.debtId == loan.id }.map(\.amount) == [Self.aed(1200)])
        try store.saveDebtTerms(nil, for: loan.id, paidFrom: nil)
        #expect(store.snapshot.paymentItem(for: loan.id) == nil)
        #expect(store.snapshot.account(loan.id)?.debtTerms == nil)
    }

    @Test("Paying a debt bill splits interest from principal and marks it paid")
    func payingADebtBill() throws {
        let (bank, loan) = try carLoan()
        try store.saveDebtTerms(DebtTerms(annualRateBps: 600, monthlyPayment: Self.aed(1000), dueDay: 5),
                                for: loan.id, paidFrom: bank.id)
        let occ = try #require(store.snapshot.occurrences.first)
        try store.pay(occurrenceId: occ.id, amount: Self.aed(1000), accountId: bank.id, categoryId: nil, date: today, key: UUID())
        let s = store.snapshot
        #expect(s.owed(loan.id) == Self.aed(29150))
        #expect(s.balance(bank.id) == Self.aed(11000))
        #expect(s.state(of: s.occurrences.first { $0.id == occ.id }!) == .paid)
    }

    // MARK: Savings goals

    @Test("A goal sets money aside, so safe-to-spend drops by what's saved")
    func goalsReserveMoney() throws {
        let bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(10000), openingDate: today)
        let before = try #require(store.snapshot.safeToSpend().amount)
        let goal = Reserve(name: "Japan", amount: Self.aed(0), accountId: bank.id, target: Self.aed(6000),
                           targetDate: Self.date(2027, 3, 31))
        try store.saveReserve(goal)
        let key = UUID()
        try store.addToGoal(goal.id, amount: Self.aed(1000), from: nil, date: today, key: key)
        try store.addToGoal(goal.id, amount: Self.aed(1000), from: nil, date: today, key: key) // double tap
        let s = store.snapshot
        let saved = try #require(s.goals.first)
        #expect(saved.amount == Self.aed(1000))
        #expect(s.safeToSpend().amount == before - Self.aed(1000))
        #expect(s.progress(of: saved)?.status == .needsPerMonth(Self.aed(833.34), months: 6)) // 5,000 over Oct–Mar
        #expect(s.balance(bank.id) == Self.aed(10000)) // nothing moved

        try store.takeFromGoal(goal.id, amount: Self.aed(400), key: UUID())
        #expect(store.snapshot.goals.first?.amount == Self.aed(600))
        #expect(throws: StoreError.self) { try store.takeFromGoal(goal.id, amount: Self.aed(700), key: UUID()) }
    }

    @Test("Adding from another account moves the money and can't over-claim it")
    func goalsMoveMoney() throws {
        let bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(5000), openingDate: today)
        let savings = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(0), openingDate: today)
        let goal = Reserve(name: "Car", amount: Self.aed(0), accountId: savings.id, target: Self.aed(20000))
        try store.saveReserve(goal)
        try store.addToGoal(goal.id, amount: Self.aed(1500), from: bank.id, date: today, key: UUID())
        var s = store.snapshot
        #expect(s.balance(bank.id) == Self.aed(3500))
        #expect(s.balance(savings.id) == Self.aed(1500))
        #expect(s.goals.first?.amount == Self.aed(1500))
        // Savings holds 1,500, all claimed: adding without moving money is refused
        #expect(throws: StoreError.self) {
            try store.addToGoal(goal.id, amount: Self.aed(100), from: nil, date: today, key: UUID())
        }
        s = store.snapshot
        #expect(s.goals.first?.amount == Self.aed(1500))
        #expect(s.freeToSetAside(in: savings.id).isZero)
    }

    // MARK: Backup and restore

    /// A household touching every kind of record
    private func household() throws -> (bank: LedgerAccountRecord, loan: LedgerAccountRecord) {
        let bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(12000), openingDate: today)
        let loan = try store.createAccount(name: "Car loan", kind: .loan, opening: Self.aed(-30000), openingDate: today)
        try store.post(try EntryFactory.expense(Self.aed(85), from: bank.info, category: category("Groceries").info,
                                                date: today, memo: "Carrefour"))
        try store.setAllocation(Self.aed(1500), categoryId: category("Groceries").id, month: store.snapshot.monthKey)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 600, monthlyPayment: Self.aed(1000), dueDay: 5),
                                for: loan.id, paidFrom: bank.id)
        let occ = try #require(store.snapshot.occurrences.first)
        try store.pay(occurrenceId: occ.id, amount: Self.aed(1000), accountId: bank.id, categoryId: nil, date: today, key: UUID())
        try store.saveReserve(Reserve(name: "Japan", amount: Self.aed(2000), accountId: bank.id, target: Self.aed(6000),
                                      targetDate: Self.date(2027, 3, 31)))
        try store.updateSettings { $0.bufferMinor = 50000; $0.onboardingDone = true }
        return (bank, loan)
    }

    private func freshStore() throws -> (ModelContainer, LedgerStore) {
        let container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        return (container, LedgerStore(context: container.mainContext, calendar: Self.dubai, now: { now }))
    }

    @Test("A backup restored on a new device gives the same balances, budget, bills, debts and goals")
    func backupRoundTrip() throws {
        let (bank, loan) = try household()
        let data = try store.backupData()
        let (container, other) = try freshStore()
        _ = container
        try other.restore(try LedgerStore.readBackup(data))

        let a = store.snapshot, b = other.snapshot
        #expect(b.balance(bank.id) == a.balance(bank.id))
        #expect(b.owed(loan.id) == a.owed(loan.id))
        #expect(b.netWorth.total == a.netWorth.total)
        #expect(b.safeToSpend().amount == a.safeToSpend().amount)
        #expect(b.budget.availableToAllocate(month: b.monthKey) == a.budget.availableToAllocate(month: a.monthKey))
        #expect(b.entries(includeVoided: true).count == a.entries(includeVoided: true).count)
        #expect(b.account(loan.id)?.debtTerms == a.account(loan.id)?.debtTerms)
        #expect(b.paymentItem(for: loan.id)?.id == a.paymentItem(for: loan.id)?.id)
        #expect(b.occurrences.map(\.id) == a.occurrences.map(\.id))
        #expect(b.occurrences.map(\.paid) == a.occurrences.map(\.paid))
        #expect(b.goals == a.goals)
        #expect(b.settings.bufferMinor == 50000 && b.settings.onboardingDone)
        #expect(other.auditTrail.contains { $0.action == "data.restored" })
    }

    @Test("Restoring over existing data replaces it rather than doubling it")
    func restoreOverExisting() throws {
        let (bank, _) = try household()
        let backup = try LedgerStore.readBackup(try store.backupData())
        try store.post(try EntryFactory.expense(Self.aed(500), from: bank.info, category: category("Shopping").info, date: today))
        try store.restore(backup)
        let s = store.snapshot
        #expect(s.balance(bank.id) == Self.aed(12000 - 85 - 1000))
        #expect(s.accounts.count == 2)
        #expect(s.entryRecords.count == backup.entries.count) // opening balances included
        // Saving with an old idempotency key after the restore still counts once
        #expect(throws: Never.self) { try store.post(try EntryFactory.expense(Self.aed(1), from: bank.info, category: category("Groceries").info, date: today)) }
    }

    @Test("Damaged, foreign or too-new files are refused and nothing changes")
    func badBackupsAreRefused() throws {
        let (bank, _) = try household()
        let good = try store.backupData()
        var json = try #require(try JSONSerialization.jsonObject(with: good) as? [String: Any])

        var unbalanced = json
        var entries = try #require(unbalanced["entries"] as? [[String: Any]])
        var lines = try #require(entries[0]["lines"] as? [[String: Any]])
        lines[0]["minorUnits"] = (lines[0]["minorUnits"] as! Int) + 1
        entries[0]["lines"] = lines
        unbalanced["entries"] = entries
        #expect(throws: BackupError.self) { try LedgerStore.readBackup(try JSONSerialization.data(withJSONObject: unbalanced)) }

        json["version"] = Backup.currentVersion + 1
        #expect(throws: BackupError.newerVersion) { try LedgerStore.readBackup(try JSONSerialization.data(withJSONObject: json)) }
        #expect(throws: BackupError.notABackup) { try LedgerStore.readBackup(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: BackupError.notABackup) { try LedgerStore.readBackup(Data("not json".utf8)) }

        #expect(store.snapshot.balance(bank.id) == Self.aed(12000 - 85 - 1000))
    }

    @Test("Data deletion removes everything on the device")
    func erase() throws {
        _ = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(3000), openingDate: today)
        try store.eraseAllData()
        #expect(store.snapshot.accounts.isEmpty)
        #expect(store.snapshot.entryRecords.isEmpty)
        #expect(!store.settings.onboardingDone)
    }
}

// MARK: - Nokael Plus

import StoreKitTest

/// Off on this Mac: SKTestSession can't save its configuration in these
/// simulators (SKInternalErrorDomain 3). Purchases are checked in the App
/// Store sandbox through TestFlight instead.
@MainActor
@Suite(.disabled("SKTestSession fails in this Mac's simulators"))
struct PlusStoreTests {
    @Test("Buying yearly unlocks Plus, and it locks again when the subscription ends")
    func buyingAndExpiring() async throws {
        let session = try SKTestSession(configurationFileNamed: "NokaelPlus")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let plus = PlusStore()
        await plus.loadProducts()
        await plus.refresh()
        #expect(plus.products.map(\.id) == [PlusStore.yearly, PlusStore.monthly, PlusStore.lifetime])
        #expect(!plus.isPlus)

        let yearly = try #require(plus.products.first { $0.id == PlusStore.yearly })
        #expect(await yearly.subscription?.isEligibleForIntroOffer == true)
        #expect(try await plus.purchase(yearly))
        #expect(plus.isPlus)
        #expect(plus.currentPlan == "Yearly")

        try session.expireSubscription(productIdentifier: PlusStore.yearly)
        await plus.refresh()
        #expect(!plus.isPlus)
    }

    @Test("Lifetime is kept and comes back with Restore")
    func lifetime() async throws {
        let session = try SKTestSession(configurationFileNamed: "NokaelPlus")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let plus = PlusStore()
        await plus.loadProducts()
        let lifetime = try #require(plus.products.first { $0.id == PlusStore.lifetime })
        #expect(try await plus.purchase(lifetime))
        let another = PlusStore()
        await another.refresh()
        #expect(another.isPlus)
        #expect(another.currentPlan == "Lifetime")
    }
}

