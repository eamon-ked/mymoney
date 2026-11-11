//  AcceptancePlanTests.swift — the cases of "MyMoney complete acceptance test plan" (8 November 2026)
//  that can be checked against the app's own store, one test per case ID, each from the plan's
//  baseline: seven accounts opened on 1 November, test day T = 8 November 2026 in Asia/Dubai.
//  Cases that need a real iPhone, real time passing or Apple services are not here.

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct Baseline {
    nonisolated static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    static let T = LedgerStoreTests.date(2026, 11, 8)
    static func day(_ offset: Int) -> Date { LedgerStoreTests.dubai.date(byAdding: .day, value: offset, to: T)! }

    let container: ModelContainer
    let store: LedgerStore
    let main, savings, cash, investments, card, loan, lent: LedgerAccountRecord

    init(openings: Date? = nil, now: Date? = nil) throws {
        let openings = openings ?? LedgerStoreTests.date(2026, 11, 1)
        let now = now ?? Baseline.T
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        main = try store.addAccount(name: "Main", kind: .bank, balance: Self.aed(10000), openingDate: openings)
        savings = try store.addAccount(name: "Savings", kind: .savings, balance: Self.aed(5000), openingDate: openings)
        cash = try store.addAccount(name: "Cash", kind: .cash, balance: Self.aed(500), openingDate: openings)
        investments = try store.addAccount(name: "Investments", kind: .investment, balance: Self.aed(2000), openingDate: openings)
        card = try store.addAccount(name: "Card", kind: .creditCard, balance: Self.aed(1000), openingDate: openings)
        loan = try store.addAccount(name: "Loan", kind: .loan, balance: Self.aed(3000), openingDate: openings)
        lent = try store.addAccount(name: "Lent", kind: .lent, balance: Self.aed(250), openingDate: openings)
        for account in [savings, investments, lent] { try store.updateAccount(account) { $0.spendable = false } }
        try store.linkAccount(digits: "560001", to: main.id)
        try store.linkAccount(digits: "240001", to: savings.id)
        try store.linkCard("2222", to: main.id)
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = main.id; $0.bankSenders = ["ADCB", "ADCBAlert"] }
    }

    var s: FinanceSnapshot { store.snapshot }
    func bal(_ a: LedgerAccountRecord) -> Money { s.balance(a.id) }
    func owed(_ a: LedgerAccountRecord) -> Money { s.balance(a.id).negated }
    var netWorth: Money { s.netWorth.total }
    var assets: Money { s.netWorth.assets }
    var liabilities: Money { s.netWorth.liabilities }
    var report: MonthReport {
        Reports.month(s.monthKey, ledger: s.ledger, expenseCategories: s.spendingCategoryInfos, incomeCategories: s.earningCategoryInfos,
                      budget: s.budget, calendar: s.calendar, loanCategories: s.loanCategories)
    }
    var spending: Money { report.totals.spending }
    var income: Money { report.totals.income }
    var safe: Money? { s.safeToSpend(through: Self.day(7)).amount }
    /// Spendable money, as the Safe to Spend breakdown lists it
    var spendable: Money { s.safeToSpend(through: Self.day(7)).spendableTotal }
    func category(_ name: String) -> LedgerAccountRecord {
        s.expenseCategories.first { $0.name == name } ?? s.incomeCategories.first { $0.name == name }!
    }
    var posted: [EntryRecord] { s.entryRecords.filter { $0.status == .posted && $0.kind != .openingBalance } }

    @discardableResult
    func expense(_ amount: Decimal, from a: LedgerAccountRecord, _ cat: String = "Groceries", memo: String = "Carrefour",
                 date: Date = Baseline.T) throws -> UUID {
        try store.save(EntryForm(kind: .expense, amount: Self.aed(amount), accountId: a.id, categoryId: category(cat).id, memo: memo, date: date))
    }
    @discardableResult
    func income(_ amount: Decimal, into a: LedgerAccountRecord, date: Date = Baseline.T) throws -> UUID {
        try store.save(EntryForm(kind: .income, amount: Self.aed(amount), accountId: a.id, categoryId: category("Salary").id, memo: "Test salary", date: date))
    }
    @discardableResult
    func transfer(_ amount: Decimal, from a: LedgerAccountRecord, to b: LedgerAccountRecord, date: Date = Baseline.T) throws -> UUID {
        try store.save(EntryForm(kind: .transfer, amount: Self.aed(amount), accountId: a.id, toAccountId: b.id, date: date))
    }
    @discardableResult
    func payDebt(_ debt: LedgerAccountRecord, _ amount: Decimal, interest: Decimal = 0, fees: Decimal = 0) throws -> UUID {
        try store.payDebt(debt.id, from: main.id, amount: Self.aed(amount), interest: Self.aed(interest), fees: Self.aed(fees), date: Self.T, key: UUID())
    }
}

private func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

// MARK: - Setup, journeys, accounts and net worth

@MainActor
struct AcceptanceAccountsTests {
    @Test("SET01 / M01 baseline totals") func set01m01() throws {
        let b = try Baseline()
        #expect(b.assets == aed(17750))
        #expect(b.liabilities == aed(4000))
        #expect(b.netWorth == aed(13750))
        #expect(b.bal(b.main) == aed(10000) && b.bal(b.savings) == aed(5000) && b.bal(b.cash) == aed(500))
        #expect(b.bal(b.investments) == aed(2000) && b.bal(b.lent) == aed(250))
        #expect(b.owed(b.card) == aed(1000) && b.owed(b.loan) == aed(3000))
        #expect(b.spendable == aed(10500))
        #expect(b.spending.isZero && b.income.isZero)
        #expect(b.posted.isEmpty)
    }

    @Test("E2E02 a complete set of movements") func e2e02() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        try b.transfer(200, from: b.main, to: b.savings)
        try b.expense(80, from: b.card)
        try b.payDebt(b.card, 100)
        try b.payDebt(b.loan, 100, interest: 10, fees: 10)
        try b.income(500, into: b.main)
        #expect(b.bal(b.main) == aed(10055))
        #expect(b.bal(b.savings) == aed(5200))
        #expect(b.owed(b.card) == aed(980))
        #expect(b.owed(b.loan) == aed(2920))
        #expect(b.assets == aed(18005) && b.liabilities == aed(3900) && b.netWorth == aed(14105))
        #expect(b.spending == aed(225))
        #expect(b.income == aed(500))
        #expect(b.posted.count == 6)
        // A backup and restore adds nothing
        let data = try b.store.backupData()
        _ = try b.store.restore(try LedgerStore.readBackup(data))
        #expect(b.posted.count == 6 && b.netWorth == aed(14105))
    }

    @Test("M02 bank purchase") func m02() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        #expect(b.bal(b.main) == aed(9955) && b.netWorth == aed(13705))
        #expect(b.spending == aed(45) && b.income.isZero)
        #expect(b.s.budget.spent(b.category("Groceries").id, month: b.s.monthKey) == aed(45))
        #expect(b.posted.count == 1)
    }

    @Test("M03 credit card purchase") func m03() throws {
        let b = try Baseline()
        try b.expense(45, from: b.card)
        #expect(b.owed(b.card) == aed(1045) && b.bal(b.main) == aed(10000))
        #expect(b.liabilities == aed(4045) && b.assets == aed(17750) && b.netWorth == aed(13705))
        #expect(b.spending == aed(45))
    }

    @Test("M04 paying the card") func m04() throws {
        let b = try Baseline()
        try b.payDebt(b.card, 100)
        #expect(b.bal(b.main) == aed(9900) && b.owed(b.card) == aed(900))
        #expect(b.netWorth == aed(13750))
        #expect(b.spending.isZero && b.income.isZero)
        #expect(b.posted.count == 1)
    }

    @Test("M05 internal transfer") func m05() throws {
        let b = try Baseline()
        try b.transfer(200, from: b.main, to: b.savings)
        #expect(b.bal(b.main) == aed(9800) && b.bal(b.savings) == aed(5200) && b.netWorth == aed(13750))
        #expect(b.posted.count == 1)
        #expect(b.spending.isZero && b.income.isZero)
        #expect(b.spendable == aed(10300))
    }

    @Test("M06 real income") func m06() throws {
        let b = try Baseline()
        try b.income(500, into: b.main)
        #expect(b.bal(b.main) == aed(10500) && b.assets == aed(18250) && b.netWorth == aed(14250))
        #expect(b.income == aed(500) && b.spending.isZero)
        #expect(b.posted.count == 1)
    }

    @Test("M07 correcting the opening balance") func m07() throws {
        let b = try Baseline()
        try b.store.correctOpeningBalance(b.main.id, to: aed(10050))
        #expect(b.bal(b.main) == aed(10050) && b.netWorth == aed(13800))
        #expect(b.income.isZero && b.spending.isZero)
        try b.store.correctOpeningBalance(b.main.id, to: aed(10050))
        #expect(b.bal(b.main) == aed(10050))
        #expect(b.posted.isEmpty)
        #expect(b.store.fetch(AuditRecord.self).contains { $0.subjectId == b.main.id })
    }

    @Test("M08 investment valuation") func m08() throws {
        let b = try Baseline()
        try b.store.reconcile(accountId: b.investments.id, statementDate: Baseline.T, statementBalance: aed(2100), reason: "Valuation")
        #expect(b.bal(b.investments) == aed(2100) && b.netWorth == aed(13850) && b.bal(b.main) == aed(10000))
        #expect(b.income.isZero && b.spending.isZero)
        #expect(b.posted.count == 1 && b.posted[0].kind == .reconciliation)
    }

    @Test("M09 net worth inclusion switch") func m09() throws {
        let b = try Baseline()
        try b.store.updateAccount(b.investments) { $0.includeInNetWorth = false }
        #expect(b.bal(b.investments) == aed(2000))
        #expect(b.assets == aed(15750) && b.netWorth == aed(11750))
        try b.store.updateAccount(b.investments) { $0.includeInNetWorth = true }
        #expect(b.netWorth == aed(13750) && b.posted.isEmpty)
    }

    @Test("M10 spendability is not net worth") func m10() throws {
        let b = try Baseline()
        #expect(b.spendable == aed(10500) && b.safe == aed(10500))
        try b.store.updateAccount(b.savings) { $0.spendable = true }
        #expect(b.spendable == aed(15500) && b.netWorth == aed(13750))
        try b.store.updateAccount(b.savings) { $0.spendable = false }
        #expect(b.spendable == aed(10500) && b.posted.isEmpty)
    }

    @Test("M11 matching statement confirmation") func m11() throws {
        let b = try Baseline()
        try b.store.reconcile(accountId: b.main.id, statementDate: Baseline.T, statementBalance: aed(10000), reason: nil)
        #expect(b.bal(b.main) == aed(10000) && b.netWorth == aed(13750) && b.posted.isEmpty)
        #expect(b.store.account(b.main.id)?.lastReconciledAt != nil)
        #expect(b.store.account(b.savings.id)?.lastReconciledAt == nil)
    }

    @Test("M12 statement mismatch") func m12() throws {
        let b = try Baseline()
        try b.store.reconcile(accountId: b.main.id, statementDate: Baseline.T, statementBalance: aed(9980), reason: "Bank says so")
        #expect(b.bal(b.main) == aed(9980) && b.netWorth == aed(13730))
        try b.store.reconcile(accountId: b.main.id, statementDate: Baseline.T, statementBalance: aed(9980), reason: "Again")
        #expect(b.posted.count == 1 && b.posted[0].kind == .reconciliation)
        #expect(b.spending.isZero && b.income.isZero)
    }

    @Test("M13 future entries don't count today") func m13() throws {
        let b = try Baseline()
        try b.income(500, into: b.main, date: Baseline.day(7))
        try b.expense(100, from: b.main, date: Baseline.day(8))
        #expect(b.bal(b.main) == aed(10000))
        #expect(b.netWorth == aed(13750))
        #expect(b.s.netWorth(on: Baseline.day(8)).total == aed(14150))
    }

    @Test("M14 daily net worth history") func m14() throws {
        let b = try Baseline(openings: Baseline.day(-3))
        try b.expense(45, from: b.main, date: Baseline.day(-2))
        try b.transfer(200, from: b.main, to: b.savings, date: Baseline.day(-1))
        try b.income(500, into: b.main)
        let history = b.s.netWorthHistory(days: 5).map(\.total)
        #expect(history.suffix(4) == [aed(13750), aed(13705), aed(13705), aed(14205)])
        #expect(b.s.firstRecordedDay == LedgerStoreTests.dubai.startOfDay(for: Baseline.day(-3)))
    }

    @Test("M15 a new day applies tomorrow's receipt without an edit") func m15() throws {
        var now = Baseline.T
        let b = try Baseline()
        b.store.now = { now }
        try b.income(500, into: b.main, date: Baseline.day(1))
        #expect(b.bal(b.main) == aed(10000) && b.netWorth == aed(13750))
        now = Baseline.day(1)
        #expect(b.bal(b.main) == aed(10500) && b.netWorth == aed(14250))
    }

    @Test("M16 loan payment split") func m16() throws {
        let b = try Baseline()
        let id = try b.payDebt(b.loan, 100, interest: 10, fees: 10)
        #expect(b.bal(b.main) == aed(9900) && b.owed(b.loan) == aed(2920) && b.owed(b.card) == aed(1000))
        #expect(b.assets == aed(17650) && b.liabilities == aed(3920) && b.netWorth == aed(13730))
        let record = try #require(b.store.entryRecord(id))
        let parts = try #require(b.store.debtPaymentParts(record))
        #expect(parts.principal == aed(80) && parts.interest == aed(10) && parts.fees == aed(10))
        #expect(b.spending == aed(100))
    }

    @Test("M17 interest-only loan payment") func m17() throws {
        let b = try Baseline()
        let id = try b.payDebt(b.loan, 100, interest: 100)
        #expect(b.bal(b.main) == aed(9900) && b.owed(b.loan) == aed(3000) && b.netWorth == aed(13650))
        let record = try #require(b.store.entryRecord(id))
        #expect(record.kind == .debtPayment && b.store.debtPaymentParts(record) != nil)
        let edited = try b.store.editDebtPayment(id, from: b.main.id, amount: aed(90), interest: aed(90), fees: aed(0), date: Baseline.T)
        #expect(b.bal(b.main) == aed(9910) && b.owed(b.loan) == aed(3000) && b.netWorth == aed(13660))
        #expect(b.posted.count == 1 && b.posted[0].id == edited)
        #expect(b.store.entryRecord(id)?.status == .void)
    }

    @Test("M18 fees larger than interest survive reopening") func m18() throws {
        let b = try Baseline()
        let id = try b.payDebt(b.loan, 100, interest: 10, fees: 20)
        let record = try #require(b.store.entryRecord(id))
        let parts = try #require(b.store.debtPaymentParts(record))
        #expect(parts.interest == aed(10) && parts.fees == aed(20) && parts.principal == aed(70))
        let again = try b.store.editDebtPayment(id, from: b.main.id, amount: aed(100), interest: parts.interest, fees: parts.fees, date: Baseline.T)
        let againRecord = try #require(b.store.entryRecord(again))
        let reread = try #require(b.store.debtPaymentParts(againRecord))
        #expect(reread.interest == aed(10) && reread.fees == aed(20))
        #expect(b.bal(b.main) == aed(9900) && b.owed(b.loan) == aed(2930) && b.netWorth == aed(13720))
        #expect(b.posted.count == 1 && b.spending == aed(100))
    }

    @Test("M20 lending and repayment") func m20() throws {
        let b = try Baseline()
        try b.store.lend(aed(100), to: b.lent.id, from: b.main.id, date: Baseline.T)
        #expect(b.bal(b.main) == aed(9900) && b.bal(b.lent) == aed(350) && b.netWorth == aed(13750))
        #expect(b.spendable == aed(10400) && b.spending.isZero && b.income.isZero)
        try b.store.receiveRepayment(aed(100), from: b.lent.id, into: b.main.id, date: Baseline.T)
        #expect(b.bal(b.main) == aed(10000) && b.bal(b.lent) == aed(250) && b.netWorth == aed(13750))
        #expect(b.spending.isZero && b.income.isZero && b.posted.count == 2)
    }

    @Test("M21 borrowing and paying back a person") func m21() throws {
        let b = try Baseline()
        let alex = try b.store.lentAccount(named: "Alex")
        try b.store.borrow(aed(100), from: alex.id, into: b.main.id, date: Baseline.T)
        #expect(b.bal(b.main) == aed(10100) && b.bal(alex) == aed(-100) && b.netWorth == aed(13750))
        #expect(b.income.isZero)
        try b.store.payBack(aed(100), to: alex.id, from: b.main.id, date: Baseline.T)
        #expect(b.bal(b.main) == aed(10000) && b.bal(alex).isZero && b.netWorth == aed(13750))
        #expect(b.spending.isZero && b.income.isZero)
    }

    @Test("M22 mixed activity reconciles to reports") func m22() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        try b.expense(20, from: b.card, "Transport", memo: "Taxi")
        try b.transfer(200, from: b.main, to: b.savings)
        try b.payDebt(b.loan, 100, interest: 10, fees: 10)
        try b.payDebt(b.card, 50)
        try b.income(500, into: b.main)
        #expect(b.bal(b.main) == aed(10105) && b.bal(b.savings) == aed(5200))
        #expect(b.owed(b.card) == aed(970) && b.owed(b.loan) == aed(2920))
        #expect(b.assets == aed(18055) && b.liabilities == aed(3890) && b.netWorth == aed(14165))
        #expect(b.spending == aed(165) && b.income == aed(500))
        #expect(b.posted.count == 6)
    }
}

// MARK: - Entries, accounts and forecasting

@MainActor
struct AcceptanceEntryTests {
    @Test("ENT01 edit and delete an expense") func ent01() throws {
        let b = try Baseline()
        let id = try b.expense(45, from: b.main)
        let edited = try b.store.save(EntryForm(kind: .expense, amount: aed(60), accountId: b.main.id,
                                                categoryId: b.category("Groceries").id, memo: "Carrefour", date: Baseline.T), replacing: id)
        #expect(b.bal(b.main) == aed(9940) && b.netWorth == aed(13690) && b.spending == aed(60))
        #expect(b.posted.count == 1)
        try b.store.void(edited)
        #expect(b.bal(b.main) == aed(10000) && b.netWorth == aed(13750) && b.spending.isZero)
        #expect(b.s.entryRecords.filter { $0.status == .void }.count == 2)
    }

    @Test("ENT02 invalid values are rejected") func ent02() throws {
        let b = try Baseline()
        let cat = b.category("Groceries").id
        for amount in [nil, aed(0), aed(-5)] as [Money?] {
            #expect(throws: (any Error).self) { try b.store.save(EntryForm(kind: .expense, amount: amount, accountId: b.main.id, categoryId: cat)) }
        }
        #expect(Money.exact(Decimal(string: "45.123")!, currency: "AED") == nil)
        #expect(throws: (any Error).self) { try b.transfer(10, from: b.main, to: b.main) }
        #expect(throws: (any Error).self) { try b.store.save(EntryForm(kind: .expense, amount: aed(45), accountId: nil, categoryId: cat)) }
        #expect(throws: (any Error).self) { try b.store.save(EntryForm(kind: .expense, amount: aed(45), accountId: b.main.id, categoryId: nil)) }
        #expect(b.posted.isEmpty && b.netWorth == aed(13750) && b.s.items.isEmpty)
    }

    @Test("ENT04 a repeating expense saves once") func ent04() throws {
        let b = try Baseline()
        var form = EntryForm(kind: .expense, amount: aed(100), accountId: b.main.id, categoryId: b.category("Shopping").id, memo: "Gym", date: Baseline.T)
        form.repeats = true
        try b.store.save(form)
        try b.store.save(form)
        try b.store.save(form)
        #expect(b.bal(b.main) == aed(9900) && b.spending == aed(100))
        #expect(b.posted.count == 1 && b.s.items.count == 1)
    }

    @Test("ACC01 archiving keeps history and money visible") func acc01() throws {
        let b = try Baseline()
        let spare = try b.store.addAccount(name: "Spare", kind: .bank, balance: aed(0), openingDate: Baseline.T)
        try b.store.updateAccount(spare) { $0.archived = true }
        #expect(!b.s.accounts.filter { !$0.archived }.contains { $0.id == spare.id })
        try b.store.updateAccount(spare) { $0.archived = false }
        #expect(b.s.entries(touching: spare.id).count == 1)
        // Archiving an account still holding money must not make it vanish from net worth silently
        // Archiving money still held is allowed with a warning naming the amount (RedesignAccounts.archiveWarning);
        // restoring brings it back without posting its opening again
        try b.store.updateAccount(b.main) { $0.archived = true }
        #expect(b.netWorth == aed(3750))
        try b.store.updateAccount(b.main) { $0.archived = false }
        #expect(b.netWorth == aed(13750) && b.s.entries(touching: b.main.id).count == 1)
    }

    @Test("FOR01 forecast on the dates money moves") func for01() throws {
        let b = try Baseline()
        try b.store.savePlannedItem(PlannedItem(name: "Rent", direction: .outflow, amount: aed(900),
                                                schedule: Schedule(start: Baseline.day(3), frequency: .monthly(every: 1), end: Baseline.day(6)), accountId: b.main.id,
                                                categoryId: b.category("Rent or mortgage").id))
        try b.store.savePlannedItem(PlannedItem(name: "Pay", direction: .inflow, amount: aed(500),
                                                schedule: Schedule(start: Baseline.day(5), frequency: .monthly(every: 1), end: Baseline.day(6)), accountId: b.main.id,
                                                categoryId: b.category("Salary").id))
        try b.store.savePlannedItem(PlannedItem(name: "Interest", direction: .inflow, amount: aed(700),
                                                schedule: Schedule(start: Baseline.day(2), frequency: .monthly(every: 1), end: Baseline.day(6)), accountId: b.savings.id,
                                                categoryId: b.category("Other income").id))
        let f = b.s.cashForecast(days: 7)
        #expect(f.start == aed(10500))
        #expect(f.days.first { LedgerStoreTests.dubai.isDate($0.date, inSameDayAs: Baseline.day(3)) }?.balance == aed(9600))
        #expect(f.days.first { LedgerStoreTests.dubai.isDate($0.date, inSameDayAs: Baseline.day(5)) }?.balance == aed(10100))
        #expect(f.lowest == aed(9600))
        #expect(b.netWorth == aed(13750) && b.posted.isEmpty)
    }
}

// MARK: - Bank messages, Apple Pay and statements

@MainActor
struct AcceptanceCaptureTests {
    func sms(_ b: Baseline, _ text: String, sender: String? = "ADCBAlert", plus: Bool = true) async -> CaptureService.Run {
        await CaptureService.runBankMessage(text, sender: sender, store: b.store, isPlus: plus, useAI: false)
    }
    func wallet(_ b: Baseline, _ amount: Decimal, _ merchant: String, card: String, plus: Bool = true) async -> CaptureService.Run {
        let capture = Capture(source: .applePay, direction: .spent, amount: aed(amount), merchant: merchant, cardHint: card,
                              date: b.store.now(), text: "\(card)|\(merchant)|\(amount)")
        return await CaptureService.runCardPurchase(capture, store: b.store, isPlus: plus)
    }
    func entryId(_ run: CaptureService.Run) -> UUID? {
        switch run.outcome {
        case .saved(let id), .merged(let id), .reversed(let id): return id
        default: return nil
        }
    }
    static let carrefour = "Purchase of AED 45.00 at CARREFOUR with card ending 2222."

    @Test("CAP01 bank purchase preview, save and review") func cap01() async throws {
        let b = try Baseline()
        let preview = await CaptureService.runBankMessage(Self.carrefour, sender: "ADCBAlert", store: b.store, isPlus: true, dryRun: true, useAI: false)
        #expect(preview.capture != nil && b.posted.isEmpty)
        let run = await sms(b, Self.carrefour)
        let id = try #require(entryId(run))
        #expect(b.posted.count == 1 && b.store.entryRecord(id)?.needsReview == true)
        #expect(b.bal(b.main) == aed(9955) && b.netWorth == aed(13705) && b.spending == aed(45))
        #expect(b.bal(b.savings) == aed(5000) && b.owed(b.card) == aed(1000))
        try b.store.markReviewed(id)
        #expect(b.store.entryRecord(id)?.needsReview == false)
    }

    @Test("CAP02 Wallet purchase on the linked credit card") func cap02() async throws {
        let b = try Baseline()
        try b.store.linkCard("Test Visa", to: b.card.id)
        let run = await wallet(b, 45, "CARREFOUR", card: "Test Visa")
        #expect(entryId(run) != nil)
        #expect(b.owed(b.card) == aed(1045) && b.bal(b.main) == aed(10000) && b.netWorth == aed(13705) && b.spending == aed(45))
    }

    @Test("CAP03 unknown card is provisional and can be linked") func cap03() async throws {
        let b = try Baseline()
        let first = try #require(entryId(await wallet(b, 45, "CARREFOUR", card: "Test New Card")))
        let record = try #require(b.store.entryRecord(first))
        #expect(record.needsReview)
        #expect(record.reviewReason != nil)
        // Corrected to the card and remembered
        _ = try b.store.save(EntryForm(kind: .expense, amount: aed(45), accountId: b.card.id, categoryId: record.lines.first { b.store.account($0.accountId)?.kind == .expense }?.accountId,
                                       memo: record.memo, date: record.date), replacing: first)
        try b.store.linkCard("Test New Card", to: b.card.id)
        #expect(b.owed(b.card) == aed(1045) && b.bal(b.main) == aed(10000) && b.netWorth == aed(13705))
        _ = try #require(entryId(await wallet(b, 30, "STARBUCKS", card: "Test New Card")))
        #expect(b.owed(b.card) == aed(1075) && b.netWorth == aed(13675) && b.spending == aed(75))
        #expect(b.posted.count == 2)
    }

    @Test("CAP04 Wallet, SMS and statement are one purchase", arguments: [false, true])
    func cap04(smsFirst: Bool) async throws {
        let b = try Baseline()
        try b.store.linkCard("Test Debit", to: b.main.id)
        if smsFirst { _ = await sms(b, Self.carrefour); _ = await wallet(b, 45, "CARREFOUR", card: "Test Debit") }
        else { _ = await wallet(b, 45, "CARREFOUR", card: "Test Debit"); _ = await sms(b, Self.carrefour) }
        #expect(b.posted.count == 1)
        let review = StatementReview(accountId: b.main.id, store: b.store)
        review.load("Date,Description,Amount\n2026-11-08,CARREFOUR,-45.00\n", named: "01_same_purchase.csv")
        #expect(review.error == nil && review.rows.count == 1 && review.matched.count == 1 && review.inbox.isEmpty)
        review.add()
        #expect(b.posted.count == 1 && b.bal(b.main) == aed(9955) && b.netWorth == aed(13705) && b.spending == aed(45))
    }

    @Test("CAP05 equal prices at different shops stay apart") func cap05() async throws {
        let b = try Baseline()
        try b.store.linkCard("Test Debit", to: b.main.id)
        _ = await wallet(b, 45, "CARREFOUR", card: "Test Debit")
        _ = await sms(b, "Purchase of AED 45.00 at STARBUCKS with card ending 2222. Ref 777700002.")
        #expect(b.posted.count == 2 && b.bal(b.main) == aed(9910) && b.spending == aed(90) && b.netWorth == aed(13660))
    }

    @Test("CAP05b two real same-shop purchases are never silently one") func cap05b() async throws {
        let b = try Baseline()
        try b.store.linkCard("Test Debit", to: b.main.id)
        _ = await wallet(b, 45, "CARREFOUR", card: "Test Debit")
        let second = await sms(b, Self.carrefour)
        // Either a second entry, or the merge is left as a visible question for the person
        if case .merged(let id) = second.outcome {
            #expect(b.store.entryRecord(id)?.needsReview == true)
            #expect(b.store.entryRecord(id)?.reviewReason == LedgerStore.joinedAlertsReason)
        } else {
            #expect(b.posted.count == 2)
        }
    }

    @Test("CAP06 retries are one purchase; tomorrow's is new") func cap06() async throws {
        var now = Baseline.T
        let b = try Baseline()
        b.store.now = { now }
        let text = "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700003."
        for _ in 0..<3 { _ = await sms(b, text) }
        #expect(b.posted.count == 1 && b.bal(b.main) == aed(9955))
        now = Baseline.day(1)
        _ = await sms(b, "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700004.")
        #expect(b.posted.count == 2 && b.s.balance(b.main.id) == aed(9910))
        // The same words with no reference on two different days are two purchases
        _ = await sms(b, "Purchase of AED 12.00 at BAKERY with card ending 2222.")
        now = Baseline.day(2)
        _ = await sms(b, "Purchase of AED 12.00 at BAKERY with card ending 2222.")
        #expect(b.posted.count == 4)
    }

    @Test("CAP07 a credit is money received into Main") func cap07() async throws {
        let b = try Baseline()
        let run = await sms(b, "A Cr. transaction of AED 150.00 on your account no. XXX560001 was successful.Available balance is AED334.52.")
        let id = try #require(entryId(run))
        let record = try #require(b.store.entryRecord(id))
        #expect(record.kind == .income && record.needsReview)
        #expect(b.bal(b.main) == aed(10150) && b.netWorth == aed(13900) && b.spending.isZero)
        #expect(!record.lines.contains { $0.accountId == b.category("Salary").id })
    }

    @Test("CAP08 a transfer with no account asks, then becomes an own transfer") func cap08() async throws {
        let b = try Baseline()
        let run = await sms(b, "Domestic Transfer instruction with Amount AED 200.00 with reference number 25-23266786 is transferred.")
        let id = try #require(entryId(run))
        let record = try #require(b.store.entryRecord(id))
        #expect(record.needsReview && record.reviewReason != nil)
        #expect(record.memo.contains("25-23266786") || record.reference == "25-23266786")
        let moved = try b.store.recordAsTransfer(id, other: b.savings.id)
        #expect(b.store.entryRecord(moved)?.kind == .transfer)
        #expect(b.bal(b.main) == aed(9800) && b.bal(b.savings) == aed(5200) && b.netWorth == aed(13750) && b.spending.isZero)
        #expect(b.posted.count == 1)
    }

    @Test("CAP09 a transfer to someone else is money sent, not spending") func cap09() async throws {
        let b = try Baseline()
        let run = await sms(b, "Domestic Transfer instruction with Amount AED 149.00 with reference number 25-23280793 is transferred.")
        let id = try #require(entryId(run))
        let record = try #require(b.store.entryRecord(id))
        #expect(record.needsReview)
        #expect(record.lines.contains { $0.accountId == b.store.peopleCategory.id })
        try b.store.markReviewed(id)
        #expect(b.bal(b.main) == aed(9851) && b.netWorth == aed(13601) && b.spending.isZero && b.bal(b.savings) == aed(5000))
        #expect(b.posted.count == 1)
    }

    @Test("CAP10 printed date and available balance") func cap10() async throws {
        let b = try Baseline()
        let run = await sms(b, "AED100.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  6 2026 10:38AM. Avl. bal. AED 7.01.")
        let id = try #require(entryId(run))
        let record = try #require(b.store.entryRecord(id))
        #expect(LedgerStoreTests.dubai.isDate(record.date, inSameDayAs: LedgerStoreTests.date(2026, 11, 6)))
        #expect(LedgerStoreTests.dubai.component(.hour, from: record.date) == 10)
        #expect(b.bal(b.main) == aed(9900))
        _ = try b.store.recordAsTransfer(id, other: b.savings.id)
        #expect(b.bal(b.main) == aed(9900) && b.bal(b.savings) == aed(5100) && b.netWorth == aed(13750) && b.spending.isZero)
    }

    @Test("CAP11 two alerts make one own transfer") func cap11() async throws {
        let b = try Baseline()
        _ = await sms(b, "AED 100.00 transferred from account XXX240001 to your account XXX560001. Ref 987654321.")
        _ = await sms(b, "AED 100.00 transferred from your account XXX240001 to account XXX560001. Ref 987654321.")
        _ = await sms(b, "AED 100.00 transferred from account XXX240001 to your account XXX560001. Ref 987654321.")
        _ = await sms(b, "AED 100.00 transferred from your account XXX240001 to account XXX560001. Ref 987654321.")
        #expect(b.bal(b.main) == aed(10100) && b.bal(b.savings) == aed(4900))
        #expect(b.posted.count == 1 && b.posted[0].kind == .transfer)
        #expect(b.netWorth == aed(13750) && b.spending.isZero && b.income.isZero)
    }

    @Test("CAP12 offers, declines, codes, balances and strangers are ignored") func cap12() async throws {
        let b = try Baseline()
        for text in ["Earn AED 50 cashback at Carrefour this weekend.",
                     "Your purchase of AED 45.00 at CARREFOUR was declined.",
                     "Your OTP is 123456 for a purchase of AED 45.00. Do not share it.",
                     "Your available balance is AED 334.52."] {
            let run = await sms(b, text)
            #expect(entryId(run) == nil, "\(text)")
        }
        let stranger = await sms(b, Self.carrefour, sender: "UNTRUSTED")
        #expect(entryId(stranger) == nil && stranger.trace.steps.first?.mark == .failed)
        #expect(b.posted.isEmpty && b.netWorth == aed(13750))
    }

    @Test("CAP15 a known format is read without Apple Intelligence") func cap15() async throws {
        let b = try Baseline()
        _ = await sms(b, "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700015.")
        _ = await sms(b, "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700015.")
        #expect(b.posted.count == 1 && b.bal(b.main) == aed(9955) && b.netWorth == aed(13705))
    }

    @Test("CAP16 without Plus nothing is saved, then a replay saves once") func cap16() async throws {
        let b = try Baseline()
        let text = "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700016."
        let gated = await sms(b, text, plus: false)
        #expect(gated.outcome == .needsPlus && b.posted.isEmpty)
        let gatedWallet = await wallet(b, 45, "CARREFOUR", card: "2222", plus: false)
        #expect(gatedWallet.outcome == .needsPlus && b.posted.isEmpty && b.netWorth == aed(13750))
        try b.expense(10, from: b.cash, memo: "Manual")
        _ = await sms(b, text)
        _ = await sms(b, text)
        #expect(b.posted.count == 2 && b.bal(b.main) == aed(9955))
    }

    @Test("CAP17 refunds", arguments: [false, true]) func cap17(reviewedFirst: Bool) async throws {
        let b = try Baseline()
        let charge = try #require(entryId(await sms(b, "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700017.")))
        if reviewedFirst { try b.store.markReviewed(charge) }
        let reversal = "Your purchase of AED 45.00 at CARREFOUR with card ending 2222 has been reversed. Ref 777700017."
        _ = await sms(b, reversal)
        _ = await sms(b, reversal)
        #expect(b.bal(b.main) == aed(10000) && b.netWorth == aed(13750))
        if reviewedFirst {
            // Confirmed history stays: the refund is its own entry
            #expect(b.store.entryRecord(charge)?.status == .posted)
        }
    }

    @Test("CAP17c a partial refund keeps the purchase") func cap17partial() async throws {
        let b = try Baseline()
        let charge = try #require(entryId(await sms(b, "Purchase of AED 45.00 at CARREFOUR with card ending 2222. Ref 777700018.")))
        _ = await sms(b, "Refund of AED 20.00 from CARREFOUR to card ending 2222. Ref 777700019.")
        #expect(b.store.entryRecord(charge)?.status == .posted)
        #expect(b.bal(b.main) == aed(9975) && b.netWorth == aed(13725))
    }

    @Test("CAT01 a confirmed category is reused") func cat01() async throws {
        let b = try Baseline()
        let first = try #require(entryId(await sms(b, "Purchase of AED 20.00 at TEST BAKERY with card ending 2222. Ref 1001.")))
        let record = try #require(b.store.entryRecord(first))
        let fixed = try b.store.save(EntryForm(kind: .expense, amount: aed(20), accountId: b.main.id, categoryId: b.category("Dining out").id,
                                               memo: record.memo, date: record.date), replacing: first)
        try b.store.markReviewed(fixed)
        let second = try #require(entryId(await sms(b, "Purchase of AED 25.00 at TEST BAKERY with card ending 2222. Ref 1002.")))
        let next = try #require(b.store.entryRecord(second))
        #expect(next.lines.contains { $0.accountId == b.category("Dining out").id })
        #expect(b.posted.count == 2 && b.bal(b.main) == aed(9955) && b.netWorth == aed(13705))
    }
}

// MARK: - Statement imports

@MainActor
struct AcceptanceImportTests {
    func load(_ b: Baseline, _ csv: String, into account: LedgerAccountRecord? = nil) -> StatementReview {
        let review = StatementReview(accountId: (account ?? b.main).id, store: b.store)
        review.load(csv, named: "test.csv")
        return review
    }
    static let basic = "Date,Description,Amount\n2026-11-08,CARREFOUR,-45.00\n2026-11-08,Salary,500.00\n"

    @Test("IMP01 / IMP02 a statement adds once, and again adds nothing") func imp01imp02() throws {
        let b = try Baseline()
        let review = load(b, Self.basic)
        #expect(review.rows.count == 2)
        #expect(review.rows.map(\.amount) == [aed(-45), aed(500)])
        for row in review.rows {
            review.targets[row.id] = .category(b.category(row.amount.isNegative ? "Groceries" : "Salary").id)
        }
        review.add()
        #expect(review.error == nil && review.added == 2)
        #expect(b.bal(b.main) == aed(10455) && b.netWorth == aed(14205) && b.spending == aed(45) && b.income == aed(500))
        #expect(b.posted.count == 2)
        let again = load(b, Self.basic)
        #expect(again.matched.count == 2 && again.inbox.isEmpty)
        again.add()
        #expect(b.posted.count == 2 && b.bal(b.main) == aed(10455))
    }

    @Test("IMP03 damaged files fail visibly", arguments: [
        "Date,Description,Amount\n2026-11-08,CARREFOUR,-10\n2026-11-08,\"BROKEN,-100\n",
        "Date,Description,Debit,Credit\n2026-11-08,CARREFOUR,BAD,\n",
        "Date,Description,Amount\n2026-11-08,CARREFOUR,12.34.56\n",
        "Date,Description,Amount\nnot-a-date,CARREFOUR,-45\n",
    ])
    func imp03(csv: String) throws {
        let b = try Baseline()
        let review = load(b, csv)
        #expect(review.error != nil && review.rows.isEmpty)
        review.add()
        #expect(b.posted.isEmpty && b.bal(b.main) == aed(10000) && b.netWorth == aed(13750))
    }

    @Test("IMP04 a USD statement can't be added as AED") func imp04() throws {
        let b = try Baseline()
        let review = load(b, "Date,Description,Amount (USD)\n2026-11-08,CARREFOUR,-100.00\n")
        #expect(review.fileCurrency == "USD")
        for row in review.rows { review.targets[row.id] = .category(b.category("Groceries").id) }
        review.add()
        #expect(review.error != nil)
        #expect(b.posted.isEmpty && b.bal(b.main) == aed(10000) && b.netWorth == aed(13750))
    }

    @Test("IMP05 a different shop with the same amount stays to add") func imp05() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main, memo: "CARREFOUR", date: Baseline.day(-2))
        let review = load(b, "Date,Description,Amount\n2026-11-08,UNRELATED TAXI,-45.00\n")
        #expect(review.matched.isEmpty && review.inbox.count == 1)
        for row in review.inbox { review.targets[row.id] = .category(b.category("Transport").id); review.skipped.remove(row.id) }
        review.add()
        #expect(b.bal(b.main) == aed(9910) && b.netWorth == aed(13660) && b.spending == aed(90))
    }

    @Test("IMP05b an unnamed record is not proof the row is recorded") func imp05b() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main, memo: "")
        let review = load(b, "Date,Description,Amount\n2026-11-08,TAXI,-45.00\n")
        #expect(review.matched.isEmpty)
    }

    @Test("Import: separate debit and credit columns and bank metadata above the header") func impFormats() throws {
        let b = try Baseline()
        let review = load(b, "Account,XXX560001\nStatement,November\n\nDate,Description,Debit,Credit\n2026-11-08,CARREFOUR,45.00,\n2026-11-08,Salary,,500.00\n")
        #expect(review.error == nil && review.rows.map(\.amount) == [aed(-45), aed(500)])
    }
}

// MARK: - Safe to Spend, budgets, bills, goals and payday

@MainActor
struct AcceptancePlanningTests {
    @discardableResult
    func bill(_ b: Baseline, _ name: String, _ amount: Decimal, due: Int, from account: LedgerAccountRecord? = nil,
              category: String = "Rent or mortgage", monthly: Bool = false) throws -> PlannedItem {
        let item = PlannedItem(name: name, direction: .outflow, amount: aed(amount),
                               schedule: Schedule(start: Baseline.day(due), frequency: .monthly(every: 1),
                                                  end: monthly ? nil : Baseline.day(due)),
                               accountId: (account ?? b.main).id, categoryId: b.category(category).id)
        try b.store.savePlannedItem(item)
        return item
    }
    func occurrence(_ b: Baseline, _ item: PlannedItem) -> Occurrence? {
        b.s.occurrences.filter { $0.itemId == item.id }.min { $0.dueDate < $1.dueDate }
    }

    @Test("STS01 baseline Safe to Spend") func sts01() throws {
        let b = try Baseline()
        #expect(b.safe == aed(10500) && b.netWorth == aed(13750))
    }

    @Test("STS02 a bill is held, then paid once") func sts02() throws {
        let b = try Baseline()
        let rent = try bill(b, "Rent", 900, due: 3)
        #expect(b.safe == aed(9600) && b.bal(b.main) == aed(10000) && b.spending.isZero)
        let occ = try #require(occurrence(b, rent))
        try b.store.pay(occurrenceId: occ.id, amount: aed(900), accountId: b.main.id, categoryId: rent.categoryId, date: Baseline.T, key: UUID())
        #expect(b.bal(b.main) == aed(9100) && b.netWorth == aed(12850) && b.spending == aed(900))
        #expect(b.safe == aed(9600))
    }

    @Test("STS03 a protected budget and its bill are held once") func sts03() throws {
        let b = try Baseline()
        let groceries = b.category("Groceries")
        try b.store.setAllocation(aed(1200), categoryId: groceries.id, month: b.s.monthKey)
        try b.store.updateAccount(groceries) { $0.reserveInSafeToSpend = true }
        try bill(b, "Box", 300, due: 3, category: "Groceries")
        #expect(b.safe == aed(9300))
        try b.expense(100, from: b.main)
        #expect(b.bal(b.main) == aed(9900) && b.safe == aed(9300))
    }

    @Test("STS04 a protected budget stays held when its bill is later") func sts04() throws {
        let b = try Baseline()
        let groceries = b.category("Groceries")
        try b.store.setAllocation(aed(1200), categoryId: groceries.id, month: b.s.monthKey)
        try b.store.updateAccount(groceries) { $0.reserveInSafeToSpend = true }
        try bill(b, "Box", 300, due: 10, category: "Groceries")
        #expect(b.safe == aed(9300))
    }

    @Test("STS05 buffer and an honest shortfall") func sts05() throws {
        let b = try Baseline()
        try b.store.updateSettings { $0.bufferMinor = 50000 }
        #expect(b.safe == aed(10000) && b.netWorth == aed(13750))
        let big = try bill(b, "Big", 11000, due: 3)
        #expect(b.safe == aed(-1000))
        try b.store.deletePlannedItem(big.id)
        try b.store.updateSettings { $0.bufferMinor = 0 }
        #expect(b.safe == aed(10500) && b.posted.isEmpty)
    }

    @Test("STS06 payday boundaries") func sts06() throws {
        let b = try Baseline()
        try b.store.savePlannedItem(PlannedItem(name: "Salary", direction: .inflow, amount: aed(5000),
                                                schedule: Schedule(start: Baseline.day(5), frequency: .monthly(every: 1)),
                                                accountId: b.main.id, categoryId: b.category("Salary").id))
        try bill(b, "Rent", 900, due: 5)
        let payday = try #require(b.s.nextIncomeDate)
        let untilPayday = b.s.safeToSpend(through: payday)
        #expect(LedgerStoreTests.dubai.isDate(payday, inSameDayAs: Baseline.day(5)))
        #expect(untilPayday.amount == aed(9600) && b.bal(b.main) == aed(10000) && b.netWorth == aed(13750))
        // Skipping that pay moves payday to the next one, and the rent stays held
        let first = try #require(b.s.occurrences.first { b.s.item(for: $0)?.name == "Salary" && LedgerStoreTests.dubai.isDate($0.dueDate, inSameDayAs: Baseline.day(5)) })
        try b.store.skip(occurrenceId: first.id)
        let next = try #require(b.s.nextIncomeDate)
        #expect(next > Baseline.day(5))
        #expect(b.s.safeToSpend(through: next).amount.map { $0 <= aed(9600) } == true)
    }

    @Test("STS06b income into savings doesn't end the spending period") func sts06b() throws {
        let b = try Baseline()
        try b.store.savePlannedItem(PlannedItem(name: "Interest", direction: .inflow, amount: aed(700),
                                                schedule: Schedule(start: Baseline.day(2), frequency: .monthly(every: 1)),
                                                accountId: b.savings.id, categoryId: b.category("Other income").id))
        try bill(b, "Rent", 900, due: 4)
        if let payday = b.s.nextIncomeDate { #expect(payday > Baseline.day(4)) }
    }

    @Test("STS07 seven and fourteen days") func sts07() throws {
        let b = try Baseline()
        try bill(b, "A", 100, due: 3)
        try bill(b, "B", 200, due: 10)
        #expect(b.s.safeToSpend(through: Baseline.day(7)).amount == aed(10400))
        #expect(b.s.safeToSpend(through: Baseline.day(14)).amount == aed(10200))
    }

    @Test("BUD01 plan, move and copy without moving money") func bud01() throws {
        let b = try Baseline()
        let month = b.s.monthKey
        let groceries = b.category("Groceries").id, dining = b.category("Dining out").id
        try b.store.setAllocation(aed(1000), categoryId: groceries, month: month)
        try b.store.setAllocation(aed(500), categoryId: dining, month: month)
        try b.store.moveAllocation(aed(200), from: groceries, to: dining, month: month)
        #expect(b.s.budget.allocated(groceries, month: month) == aed(800) && b.s.budget.allocated(dining, month: month) == aed(700))
        let next = BudgetMonth.adding(1, to: month, calendar: b.s.calendar)
        try b.store.copyPlan(from: month, to: next)
        try b.store.copyPlan(from: month, to: next)
        #expect(b.s.budget.allocationProgress(month: next).allocated == aed(1500))
        #expect(b.netWorth == aed(13750) && b.posted.isEmpty)
    }

    @Test("BUD02 overspending covered by moving budget") func bud02() throws {
        let b = try Baseline()
        let month = b.s.monthKey
        let groceries = b.category("Groceries"), dining = b.category("Dining out")
        try b.store.setAllocation(aed(100), categoryId: groceries.id, month: month)
        try b.expense(150, from: b.main)
        #expect(b.s.budget.line(groceries.id, month: month).remaining == aed(-50))
        try b.store.setAllocation(aed(100), categoryId: dining.id, month: month)
        try b.store.moveAllocation(aed(50), from: dining.id, to: groceries.id, month: month)
        #expect(b.s.budget.line(groceries.id, month: month).remaining.isZero)
        #expect(b.spending == aed(150) && b.bal(b.main) == aed(9850) && b.netWorth == aed(13600))
        try b.store.updateAccount(groceries) { $0.name = "Food" }
        #expect(b.s.entries(in: groceries.id, month: month).count == 1)
    }

    @Test("BIL01 partial payments and overpayment") func bil01() throws {
        let b = try Baseline()
        let item = try bill(b, "Fee", 300, due: 3)
        let occ = try #require(occurrence(b, item))
        try b.store.pay(occurrenceId: occ.id, amount: aed(100), accountId: b.main.id, categoryId: item.categoryId, date: Baseline.T, key: UUID())
        #expect(b.s.occurrences.first { $0.id == occ.id }?.remaining == aed(200))
        try b.store.pay(occurrenceId: occ.id, amount: aed(200), accountId: b.main.id, categoryId: item.categoryId, date: Baseline.T, key: UUID())
        #expect(b.s.occurrences.first { $0.id == occ.id }?.remaining.isZero == true)
        #expect(throws: (any Error).self) {
            try b.store.pay(occurrenceId: occ.id, amount: aed(50), accountId: b.main.id, categoryId: item.categoryId, date: Baseline.T, key: UUID())
        }
        #expect(b.bal(b.main) == aed(9700) && b.netWorth == aed(13450) && b.posted.count == 2)
    }

    @Test("BIL02 link an existing payment without posting again") func bil02() throws {
        let b = try Baseline()
        let item = try bill(b, "Rent", 900, due: 1)
        let paid = try b.expense(900, from: b.main, "Rent or mortgage", memo: "Rent")
        let occ = try #require(occurrence(b, item))
        try b.store.match(occurrenceId: occ.id, entryId: paid)
        #expect(b.s.occurrences.first { $0.id == occ.id }?.remaining.isZero == true)
        try b.store.unlink(entryId: paid)
        #expect(b.s.occurrences.first { $0.id == occ.id }?.remaining == aed(900))
        try b.store.match(occurrenceId: occ.id, entryId: paid)
        #expect(b.bal(b.main) == aed(9100) && b.spending == aed(900) && b.posted.count == 1)
    }

    @Test("BIL03 skip, undo and stop") func bil03() throws {
        let b = try Baseline()
        let item = try bill(b, "Music", 100, due: 0, category: "Entertainment", monthly: true)
        let first = try #require(occurrence(b, item))
        try b.store.pay(occurrenceId: first.id, amount: aed(100), accountId: b.main.id, categoryId: item.categoryId, date: Baseline.T, key: UUID())
        let second = try #require(b.s.occurrences.filter { $0.itemId == item.id }.sorted { $0.dueDate < $1.dueDate }.dropFirst().first)
        try b.store.skip(occurrenceId: second.id)
        try b.store.unskip(occurrenceId: second.id)
        try b.store.skip(occurrenceId: second.id)
        #expect(b.posted.count == 1 && b.bal(b.main) == aed(9900))
        try b.store.archivePlannedItem(item.id)
        #expect(b.s.occurrences.filter { $0.itemId == item.id && $0.dueDate > Baseline.T && !$0.remaining.isZero && !$0.skipped }.isEmpty)
        #expect(b.posted.count == 1)
    }

    @Test("BIL04 month ends keep to the 31st") func bil04() {
        let schedule = Schedule(start: LedgerStoreTests.date(2027, 1, 31), frequency: .monthly(every: 1))
        let dates = RecurrenceEngine.dates(for: schedule, from: LedgerStoreTests.date(2027, 1, 1), through: LedgerStoreTests.date(2027, 3, 31),
                                     calendar: LedgerStoreTests.dubai)
        let days = dates.map { LedgerStoreTests.dubai.component(.day, from: $0) }
        #expect(days == [31, 28, 31])
    }

    @Test("GOL01 set aside and release") func gol01() throws {
        let b = try Baseline()
        let goal = Reserve(name: "Holiday", amount: aed(1000), accountId: b.main.id, target: aed(2000))
        try b.store.saveReserve(goal)
        #expect(b.bal(b.main) == aed(10000) && b.netWorth == aed(13750) && b.safe == aed(9500))
        try b.store.takeFromGoal(goal.id, amount: aed(200), key: UUID())
        #expect(b.safe == aed(9700) && b.income.isZero)
        try b.store.releaseReserve(goal.id)
        #expect(b.safe == aed(10500) && b.posted.isEmpty)
    }

    @Test("GOL02 fund a goal by transfer, once") func gol02() throws {
        let b = try Baseline()
        let goal = Reserve(name: "Holiday", amount: aed(0), accountId: b.savings.id, target: aed(2000))
        try b.store.saveReserve(goal)
        let key = UUID()
        try b.store.addToGoal(goal.id, amount: aed(200), from: b.main.id, date: Baseline.T, key: key)
        try b.store.addToGoal(goal.id, amount: aed(200), from: b.main.id, date: Baseline.T, key: key)
        #expect(b.bal(b.main) == aed(9800) && b.bal(b.savings) == aed(5200) && b.netWorth == aed(13750) && b.spending.isZero)
        #expect(b.s.reserves.first { $0.id == goal.id }?.amount == aed(200))
        #expect(b.posted.count == 1)
        #expect(throws: (any Error).self) { try b.store.addToGoal(goal.id, amount: aed(50), from: UUID(), date: Baseline.T, key: UUID()) }
        #expect(b.posted.count == 1)
    }

    @Test("PAY01 salary once, plan copied once") func pay01() throws {
        let b = try Baseline()
        try b.store.savePlannedItem(PlannedItem(name: "Salary", direction: .inflow, amount: aed(5000),
                                                schedule: Schedule(start: Baseline.T, frequency: .monthly(every: 1)),
                                                accountId: b.main.id, categoryId: b.category("Salary").id))
        let previous = BudgetMonth.adding(-1, to: b.s.monthKey, calendar: b.s.calendar)
        try b.store.setAllocation(aed(1000), categoryId: b.category("Groceries").id, month: previous)
        let plan = PaydayPlan.make(b.s)
        #expect(plan.amount == aed(5000) && plan.occurrence != nil)
        _ = try plan.run(b.store, choices: .init(), date: Baseline.T, key: UUID())
        #expect(b.bal(b.main) == aed(15000) && b.netWorth == aed(18750))
        #expect(b.s.budget.allocationProgress(month: b.s.monthKey).allocated == aed(1000))
        let again = PaydayPlan.make(b.s)
        #expect(again.alreadyReceived != nil && again.occurrence == nil)
        #expect(b.posted.count == 1)
    }
}

// MARK: - Backups, erasing and privacy

@MainActor
struct AcceptanceRecoveryTests {
    @Test("REC01 / REC02 backup and restore, with a separate safety copy each time") func rec01rec02() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        try b.store.saveReserve(Reserve(name: "Holiday", amount: aed(300), accountId: b.main.id, target: aed(1000)))
        _ = try b.store.createCategory(name: "Pets", kind: .expense, group: "Lifestyle")
        let saved = try b.store.backupData()
        let before = (b.netWorth, b.posted.count, b.s.reserves.count, b.store.linkedAccount(forCard: "2222"))
        try b.expense(99, from: b.cash)
        let first = try #require(try b.store.restore(try LedgerStore.readBackup(saved)))
        let second = try #require(try b.store.restore(try LedgerStore.readBackup(saved)))
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path))
        #expect((b.netWorth, b.posted.count, b.s.reserves.count) == (before.0, before.1, before.2))
        #expect(b.store.linkedAccount(forCard: "2222") == before.3)
        #expect(b.s.expenseCategories.contains { $0.name == "Pets" })
        // The first safety copy still has the extra expense made before the first restore
        let copy = try LedgerStore.readBackup(try Data(contentsOf: first))
        #expect(copy.entries.count == before.1 + 1 + 7)
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
    }

    @Test("REC03 damaged backups are refused before anything changes") func rec03() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        let good = try b.store.backupData()
        var json = try #require(try JSONSerialization.jsonObject(with: good) as? [String: Any])
        var bad: [Data] = [good.prefix(good.count / 2)]
        var entries = try #require(json["entries"] as? [[String: Any]])
        if var lines = entries.last?["lines"] as? [[String: Any]] {
            lines[0]["accountId"] = UUID().uuidString
            entries[entries.count - 1]["lines"] = lines
            json["entries"] = entries
            bad.append(try JSONSerialization.data(withJSONObject: json))
        }
        for data in bad {
            #expect(throws: (any Error).self) { try LedgerStore.readBackup(data) }
        }
        #expect(b.posted.count == 1 && b.bal(b.main) == aed(9955))
    }

    @Test("REC05 erasing removes records and internal safety copies") func rec05() throws {
        let b = try Baseline()
        try b.expense(45, from: b.main)
        _ = try b.store.restore(try LedgerStore.readBackup(try b.store.backupData()))
        try b.store.eraseAllData()
        #expect(b.s.accounts.isEmpty && b.s.entryRecords.isEmpty && !b.store.settings.onboardingDone)
        if let folder = LedgerStore.safetyCopyFolder { #expect(!FileManager.default.fileExists(atPath: folder.path)) }
    }

    @Test("SEC01 Privacy Mode hides amounts in the app's own sentences") func sec01() throws {
        let b = try Baseline()
        let model = Redesign.AppModel(store: b.store, plus: PlusStore())
        model.privacy.on = true
        defer { model.privacy.on = false; model.privacy.store() }
        for sentence in ["Opened Main with AED 10,000.00", "Paid AED 100.00 to Loan (AED 10.00 interest)",
                         "Holiday: AED 1,000 of AED 2,000", "Adjusted by -AED 20.00 to match statement", "Set aside 1.250,50 €"] {
            let hidden = model.concealingAmounts(sentence)
            #expect(hidden.rangeOfCharacter(from: .decimalDigits) == nil, "\(sentence) → \(hidden)")
        }
        #expect(model.concealingAmounts("Paid Carrefour") == "Paid Carrefour")
    }

    @Test("CFG01 week start and a zero-decimal currency") func cfg01() throws {
        let b = try Baseline()
        try b.store.updateSettings { $0.firstWeekday = 7 }
        #expect(b.store.calendar.firstWeekday == 7)
        #expect(MoneyFormat.string(Money(1500, currency: "JPY")).contains("1,500") || MoneyFormat.string(Money(1500, currency: "JPY")).contains("1500"))
        #expect(!MoneyFormat.string(Money(1500, currency: "JPY")).contains(".00"))
    }
}

@MainActor
struct AcceptanceSplitTests {
    @Test("ENT03 one expense across two categories") func ent03() throws {
        let b = try Baseline()
        let groceries = b.category("Groceries").id, transport = b.category("Transport").id
        var form = EntryForm(kind: .expense, amount: aed(100), accountId: b.main.id, categoryId: groceries, memo: "Shop", date: Baseline.T)
        form.parts = [(groceries, aed(60)), (transport, aed(40))]
        let id = try b.store.save(form)
        let month = b.s.monthKey
        #expect(b.bal(b.main) == aed(9900) && b.netWorth == aed(13650) && b.spending == aed(100))
        #expect(b.s.budget.spent(groceries, month: month) == aed(60) && b.s.budget.spent(transport, month: month) == aed(40))
        // Parts that don't add up are refused and change nothing
        var wrong = form
        wrong.key = UUID()
        wrong.parts = [(groceries, aed(50)), (transport, aed(60))]
        #expect(throws: (any Error).self) { try b.store.save(wrong, replacing: id) }
        #expect(b.s.budget.spent(groceries, month: month) == aed(60))
        var even = form
        even.key = UUID()
        even.parts = [(groceries, aed(50)), (transport, aed(50))]
        try b.store.save(even, replacing: id)
        #expect(b.s.budget.spent(groceries, month: month) == aed(50) && b.s.budget.spent(transport, month: month) == aed(50))
        #expect(b.bal(b.main) == aed(9900) && b.spending == aed(100) && b.posted.count == 1)
    }
}

// MARK: - The Apple Pay journey: review only what was guessed

@MainActor
struct ApplePayJourneyTests {
    func wallet(_ b: Baseline, _ amount: Decimal, _ merchant: String, card: String) async -> UUID? {
        let capture = Capture(source: .applePay, direction: .spent, amount: aed(amount), merchant: merchant, cardHint: card,
                              date: b.store.now(), text: "\(card)|\(merchant)|\(amount)")
        switch await CaptureService.runCardPurchase(capture, store: b.store, isPlus: true).outcome {
        case .saved(let id), .merged(let id): return id
        default: return nil
        }
    }

    @Test("Correcting an unknown card's account keeps the card, so it can be linked from the edited entry")
    func editKeepsTheCard() async throws {
        let b = try Baseline()
        let first = try #require(await wallet(b, 45, "CARREFOUR", card: "ADCB Debit"))
        let record = try #require(b.store.entryRecord(first))
        let edited = try b.store.save(EntryForm(kind: .expense, amount: aed(45), accountId: b.cash.id, categoryId: b.category("Groceries").id,
                                                memo: record.memo, date: record.date), replacing: first)
        let after = try #require(b.store.entryRecord(edited))
        #expect(after.cardHint == "ADCB Debit" && after.source == .applePay)
        #expect(b.store.linkedAccount(forCard: "ADCB Debit") == nil)
    }

    @Test("Once the card is linked and the shop's category confirmed, the next purchase needs no review")
    func settledPurchasesSkipReview() async throws {
        let b = try Baseline()
        try b.store.linkCard("ADCB Debit", to: b.main.id)
        let first = try #require(await wallet(b, 45, "CARREFOUR", card: "ADCB Debit"))
        #expect(b.store.entryRecord(first)?.needsReview == true)
        try b.store.markReviewed(first)
        b.store.now = { Baseline.day(1) }
        let second = try #require(await wallet(b, 60, "CARREFOUR", card: "ADCB Debit"))
        #expect(b.store.entryRecord(second)?.needsReview == false)
        // A new shop is still checked
        let third = try #require(await wallet(b, 20, "NEW BAKERY", card: "ADCB Debit"))
        #expect(b.store.entryRecord(third)?.needsReview == true)
        #expect(b.bal(b.main) == aed(9875))
    }
}
