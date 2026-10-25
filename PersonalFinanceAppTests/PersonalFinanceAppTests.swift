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

    @Test("Data deletion removes everything on the device")
    func erase() throws {
        _ = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(3000), openingDate: today)
        try store.eraseAllData()
        #expect(store.snapshot.accounts.isEmpty)
        #expect(store.snapshot.entryRecords.isEmpty)
        #expect(!store.settings.onboardingDone)
    }
}
