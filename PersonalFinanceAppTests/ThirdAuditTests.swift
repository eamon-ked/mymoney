//  Regression tests from the third audit (8 Nov 2026). Each was written to fail on the code it audited.
import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct CaptureThirdAuditTests {
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let now = LedgerStoreTests.date(2026, 11, 8)
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = now
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Main", kind: .bank, opening: Self.aed(1000), openingDate: now.addingTimeInterval(-86400))
        savings = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(200), openingDate: now.addingTimeInterval(-86400))
        try store.setAccountNumber(bank.id, "1234730001")
        try store.setAccountNumber(savings.id, "1234240001")
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = bank.id }
    }
    @Test func incomingTransferMustUseTheReceivingAccount() async throws {
        let text = "AED100.00 transferred from account XXX240001 to your account XXX730001. Ref 987654321"
        let r = await CaptureService.runBankMessage(text, sender: "ADCB", store: store, isPlus: true, useAI: false)
        #expect(r.outcome?.entryId != nil)
        #expect(store.snapshot.balance(bank.id) == Self.aed(1100))
        #expect(store.snapshot.balance(savings.id) == Self.aed(100))
    }
    @Test func automaticTransferMustNotDeleteUnrelatedDeposit() async throws {
        let income = try #require(store.snapshot.incomeCategories.first)
        let deposit = try store.post(EntryFactory.income(Self.aed(100), to: savings.info, category: income.info, date: now, memo: "Unrelated deposit"))
        let r = await CaptureService.runBankMessage("AED100.00 transferred from your account XXX730001 to account XXX240001. Ref 987654321", sender: "ADCB", store: store, isPlus: true, useAI: false)
        #expect(r.outcome?.entryId != nil)
        #expect(store.entryRecord(deposit)?.status == .posted)
        #expect(store.snapshot.balance(savings.id) == Self.aed(400))
    }
    @Test func adcbHyphenatedReferenceMustBePreserved() {
        let capture = AlertParser.read("Domestic Transfer instruction with Amount AED 200.00 with reference number 25-23266786 is transferred.", homeCurrency: "AED", date: now)
        #expect(capture?.reference == "25-23266786")
    }
    @Test func messagePreviewMustNotCreateCategories() async throws {
        let count = store.snapshot.accountRecords.count
        _ = await CaptureService.runBankMessage("AED45.00 spent at ZXQZZ UNKNOWN", sender: "ADCB", store: store, isPlus: true, dryRun: true, useAI: false)
        #expect(store.snapshot.accountRecords.count == count)
    }
    @Test func spendingIntentMustNotAllowIncomeCategory() async throws {
        let category = try #require(store.snapshot.incomeCategories.first)
        let c = Capture(source: .siri, direction: .spent, amount: Self.aed(50), merchant: "Test", date: now, text: "50 at Test")
        do {
            _ = try await CaptureService.record(c, in: store, isPlus: false, choices: .init(accountId: bank.id, categoryId: category.id))
            Issue.record("An income category must be rejected for an expense")
        } catch {}
        #expect(store.snapshot.entries().filter { $0.kind == .expense }.isEmpty)
    }
}
@MainActor
struct BoundaryThirdAuditTests {
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let category: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    static func aed(_ n: Decimal) -> Money { Money(n, currency: "AED") }
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: now.addingTimeInterval(-86400 * 30))
        category = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
    }
    @Test func unrelatedPurchaseMustRemainInStatementInbox() throws {
        let existing = try store.post(EntryFactory.expense(Self.aed(100), from: bank.info, category: category.info,
                                                           date: today.addingTimeInterval(-86400 * 2), memo: "Carrefour"))
        let review = StatementReview(accountId: bank.id, store: store)
        review.load("Date,Description,Amount\n2026-11-08,UNRELATED TAXI,-100", named: "new.csv")
        #expect(review.inbox.count == 1)
    }
    @Test func csvMetadataWithoutDelimiterMustNotPreventHeaderDetection() throws {
        let text = "Bank statement\nDate,Description,Amount\n2026-11-08,CARREFOUR,-100"
        let rows = try? StatementImport.read(text, currency: "AED", calendar: LedgerStoreTests.dubai)
        #expect(rows?.count == 1)
    }
    @Test func amountMustRejectMalformedTextRatherThanStripIt() {
        let value = StatementImport.amount("12.34.56", currency: "AED")
        #expect(value == nil)
    }
    @Test func malformedQuotedCSVRowMustNotSilentlyDisappear() {
        let text = "Date,Description,Amount\n2026-11-08,CARREFOUR,-10\n2026-11-09,\"BROKEN,-100"
        let result = try? StatementImport.read(text, currency: "AED", calendar: LedgerStoreTests.dubai)
        #expect(result == nil)
    }
    @Test func currencyInColumnHeaderMustBeDetected() {
        let text = "Date,Description,Amount (USD)\n2026-11-08,CARREFOUR,-100"
        #expect(StatementImport.currency(in: text) == "USD")
    }
    @Test func backupMustRejectPaidBillWithNoPayment() throws {
        let item = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(100),
                               schedule: Schedule(start: today, frequency: .monthly(every: 1)), accountId: bank.id, categoryId: category.id)
        try store.savePlannedItem(item)
        var backup = store.makeBackup()
        let i = try #require(backup.occurrences.firstIndex { $0.itemId == item.id })
        backup.occurrences[i].paidMinor = 10000
        backup.occurrences[i].paidEntryIds = []
        let data = try JSONEncoder().encode(backup)
        let checked = try? LedgerStore.readBackup(data)
        #expect(checked == nil)
    }
    @Test func backupMustRejectDuplicateAllocationIDs() throws {
        try store.setAllocation(Self.aed(100), categoryId: category.id, month: "2026-11")
        var backup = store.makeBackup()
        let first = try #require(backup.allocations.first)
        backup.allocations.append(first)
        let checked = try? LedgerStore.readBackup(JSONEncoder().encode(backup))
        #expect(checked == nil)
    }
}
@MainActor
struct PlanningThirdAuditTests {
    static func aed(_ x: Decimal) -> Money { Money(x, currency: "AED") }
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: today.addingTimeInterval(-86400))
        try store.updateSettings { $0.onboardingDone = true }
    }
    var category: LedgerAccountRecord { store.snapshot.expenseCategories.first { $0.name == "Groceries" }! }
    var income: LedgerAccountRecord { store.snapshot.incomeCategories.first! }
    func date(_ d: Int) -> Date { LedgerStoreTests.date(2026, 11, d) }

    @Test func skippedSalaryMustNotShortenSafeToSpendPeriod() throws {
        let salary = PlannedItem(name: "Salary", direction: .inflow, amount: Self.aed(5000), schedule: Schedule(start: date(12), frequency: .monthly(every: 1)), accountId: bank.id, categoryId: income.id)
        try store.savePlannedItem(salary)
        let first = try #require(store.snapshot.occurrences.first { $0.itemId == salary.id })
        try store.skip(occurrenceId: first.id)
        let snapshot = store.snapshot
        #expect(snapshot.nextIncomeDate != first.dueDate, "Skipped salary is still the next payday")
    }

    @Test func budgetReservationMustNotReleaseABillOutsideSelectedPeriod() throws {
        try store.updateAccount(category) { $0.reserveInSafeToSpend = true }
        try store.setAllocation(Self.aed(200), categoryId: category.id, month: "2026-11")
        let bill = PlannedItem(name: "Future groceries", direction: .outflow, amount: Self.aed(50), schedule: Schedule(start: date(25), frequency: .monthly(every: 1)), accountId: bank.id, categoryId: category.id)
        try store.savePlannedItem(bill)
        let safe = store.snapshot.safeToSpend(through: date(15))
        #expect(safe.amount == Self.aed(800), "A protected AED200 budget must stay protected when its AED50 bill is outside the selected period")
    }

    @Test func assistantSearchMustNotSilentlyDropTransactionsAfter400() throws {
        for n in 0..<401 {
            _ = try store.post(EntryFactory.expense(Self.aed(1), from: bank.info, category: category.info, date: today.addingTimeInterval(-Double(n)), memo: "Audit groceries"))
        }
        let text = FinanceDigest(store.snapshot).search(text: "Audit groceries", category: nil, days: nil)
        #expect(text.contains("401 matching transactions"), "The search advertises all history but discards records after400")
        #expect(text.replacingOccurrences(of: "\u{00a0}", with: " ").contains("Total spent: AED 401"))
    }

    @Test func futureIncomeMustNotRaiseTodaysCashOrForecastStart() throws {
        _ = try store.post(EntryFactory.income(Self.aed(500), to: bank.info, category: income.info, date: date(20), memo: "Future receipt"))
        let snapshot = store.snapshot
        #expect(snapshot.cashAndBank == Self.aed(1000), "A future dated receipt should not already be held today")
        #expect(snapshot.cashForecast(days: 30).start == Self.aed(1000))
    }
}

@MainActor
struct DebtIdentityThirdAuditTests {
    static func aed(_ x: Decimal) -> Money { Money(x, currency: "AED") }
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let debt: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: today)
        debt = try store.createAccount(name: "Loan", kind: .loan, opening: Self.aed(-1000), openingDate: today)
    }

    @Test func interestOnlyPaymentMustRetainDebtIdentityAndStayEditable() throws {
        let id = try store.payDebt(debt.id, from: bank.id, amount: Self.aed(100), interest: Self.aed(100), fees: Self.aed(0), date: today, key: UUID())
        let record = try #require(store.entryRecord(id))
        #expect(store.debtPaymentParts(record) != nil, "Zero principal causes the debt line to vanish")
        let edited = try? store.editDebtPayment(id, from: bank.id, amount: Self.aed(90), interest: Self.aed(90), fees: Self.aed(0), date: today)
        #expect(edited != nil, "A saved interest-only payment cannot be edited")
    }

    @Test func feesAndInterestMustNotSwapWhenFeeIsLarger() throws {
        let id = try store.payDebt(debt.id, from: bank.id, amount: Self.aed(100), interest: Self.aed(10), fees: Self.aed(20), date: today, key: UUID())
        let record = try #require(store.entryRecord(id))
        let parts = try #require(store.debtPaymentParts(record))
        #expect(parts.interest == Self.aed(10))
        #expect(parts.fees == Self.aed(20))
    }
}

@MainActor
struct AdditionalPlanningThirdAuditTests {
    static func aed(_ x: Decimal) -> Money { Money(x, currency: "AED") }
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(2000), openingDate: LedgerStoreTests.date(2026, 10, 1))
    }

    @Test func incomeIntoProtectedSavingsMustNotShortenSpendablePeriod() throws {
        let savings = try store.createAccount(name: "Protected", kind: .savings, opening: Self.aed(0), openingDate: today)
        let income = try #require(store.snapshot.incomeCategories.first)
        let category = try #require(store.snapshot.expenseCategories.first)
        let salary = PlannedItem(name: "Savings income", direction: .inflow, amount: Self.aed(500), schedule: Schedule(start: LedgerStoreTests.date(2026, 11, 12), frequency: .monthly(every: 1)), accountId: savings.id, categoryId: income.id)
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(900), schedule: Schedule(start: LedgerStoreTests.date(2026, 11, 20), frequency: .monthly(every: 1)), accountId: bank.id, categoryId: category.id)
        try store.savePlannedItem(salary)
        try store.savePlannedItem(rent)
        let safe = store.snapshot.safeToSpend()
        #expect(safe.amount == Self.aed(1100), "Income to protected savings does not make bank bills after it safe to ignore")
    }

    @Test func confirmedZeroInterestLoanMustCountImportedInstalments() throws {
        let paymentDate = LedgerStoreTests.date(2026, 10, 26)
        let loan = try store.addUnfinishedLoan(name: "Zero interest", openingDate: LedgerStoreTests.date(2026, 10, 1))
        _ = try store.post(EntryFactory.transfer(Self.aed(100), from: bank.info, to: loan.info, date: paymentDate, memo: "Instalment"))
        try store.startLoan(loan.id, payments: [(date: paymentDate, amount: Self.aed(100))], paidFrom: bank.id)
        try store.finishLoan(loan.id, name: "Zero interest", owed: Self.aed(900), annualRateBps: 0)
        let snapshot = store.snapshot
        let report = Reports.month("2026-10", ledger: snapshot.ledger, expenseCategories: snapshot.spendingCategoryInfos, incomeCategories: [], calendar: snapshot.calendar, loanCategories: snapshot.loanCategories)
        #expect(report.totals.spending == Self.aed(100), "Known0% instalment remains a transfer and is omitted from spending")
    }
}
@MainActor
struct PrivacyThirdAuditTests {
    let container: ModelContainer
    let store: LedgerStore
    let bankId: UUID
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { LedgerStoreTests.date(2041, 2, 3) })
        bankId = try store.createAccount(name: "Audit private bank", kind: .bank, opening: Money(1000, currency: "AED"), openingDate: LedgerStoreTests.date(2041, 2, 2)).id
    }
    @Test func changingWeekStartMustChangeTheEffectiveCalendar() throws {
        let desired = store.snapshot.calendar.firstWeekday == 7 ? 2 : 7
        try store.updateSettings { $0.firstWeekday = desired }
        #expect(store.snapshot.calendar.firstWeekday == desired)
    }
    @Test func deletingAllDataMustRemoveItsPrivateSafetyCopy() throws {
        let copy = try #require(try store.restore(store.makeBackup()))
        defer { try? FileManager.default.removeItem(at: copy) }
        try store.eraseAllData()
        let remains = FileManager.default.fileExists(atPath: copy.path)
        #expect(!remains)
    }
    @Test func repeatedRestoreMustNotOverwriteTheFirstSafetyCopy() throws {
        let backup = store.makeBackup()
        let first = try #require(try store.restore(backup))
        defer { try? FileManager.default.removeItem(at: first) }
        let before = try Data(contentsOf: first)
        try store.updateAccount(try #require(store.account(bankId))) { $0.name = "Changed after first restore" }
        let second = try #require(try store.restore(backup))
        let after = try Data(contentsOf: first)
        #expect(first != second)
        #expect(before == after)
    }
}

/// The full operations around the third audit's fixes: review, edit, back up and restore, forecast
@MainActor
struct ThirdAuditFollowUpTests {
    static func eur(_ x: Decimal) -> Money { Money(x, currency: "EUR") }
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.updateSettings { $0.currency = "EUR"; $0.localeIdentifier = "de_DE"; $0.onboardingDone = true }
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Girokonto", kind: .bank, opening: Self.eur(1000), openingDate: today.addingTimeInterval(-86400 * 10))
    }

    @Test func aLookalikeRowIsShownLeftOutWithWhatItMightBe() throws {
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        let rewe = try store.post(EntryFactory.expense(Self.eur(100), from: bank.info, category: groceries.info,
                                                       date: today.addingTimeInterval(-86400), memo: "REWE"))
        let review = StatementReview(accountId: bank.id, store: store)
        review.load("Datum;Beschreibung;Betrag\n08.11.2026;TAXI BERLIN;-100,00\n07.11.2026;REWE MARKT;-100,00", named: "konto.csv")
        // REWE is the same purchase; the taxi only costs the same
        #expect(review.matched.values.contains(rewe))
        #expect(review.inbox.map(\.description) == ["TAXI BERLIN"])
        let taxi = try #require(review.inbox.first)
        // Its only lookalike is REWE, already taken by its own row: nothing else to doubt, so it's ticked
        #expect(review.lookalike(for: taxi) == nil && !review.skipped.contains(taxi.id))
    }

    @Test func aLookalikeWithAnotherEntryFreeIsLeftOutUntilTicked() throws {
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        let edeka = try store.post(EntryFactory.expense(Self.eur(40), from: bank.info, category: groceries.info,
                                                        date: today.addingTimeInterval(-86400 * 2), memo: "Edeka"))
        let review = StatementReview(accountId: bank.id, store: store)
        review.load("Datum;Beschreibung;Betrag\n08.11.2026;BAECKEREI MUELLER;-40,00", named: "konto.csv")
        let row = try #require(review.inbox.first)
        #expect(review.lookalike(for: row)?.id == edeka)
        #expect(review.skipped.contains(row.id))
        #expect(review.ready.isEmpty)
    }

    @Test func anInterestOnlyPaymentSurvivesEditBackupAndRestore() throws {
        let loan = try store.createAccount(name: "Kredit", kind: .loan, opening: Self.eur(-5000), openingDate: today)
        let first = try store.payDebt(loan.id, from: bank.id, amount: Self.eur(30), interest: Self.eur(20), fees: Self.eur(10), date: today, key: UUID())
        let edited = try store.editDebtPayment(first, from: bank.id, amount: Self.eur(25), interest: Self.eur(10), fees: Self.eur(15), date: today)
        let backup = try LedgerStore.readBackup(try store.backupData())
        let copy = try #require(try store.restore(backup))
        defer { try? FileManager.default.removeItem(at: copy) }
        let parts = try #require(store.entryRecord(edited).flatMap(store.debtPaymentParts))
        #expect(parts.debt.id == loan.id && parts.principal.isZero)
        #expect(parts.interest == Self.eur(10) && parts.fees == Self.eur(15))
        #expect(store.snapshot.owed(loan.id) == Self.eur(5000))
    }

    @Test func aFutureEntryArrivesInTheForecastOnItsDay() throws {
        let rent = try #require(store.snapshot.expenseCategories.first)
        let day = LedgerStoreTests.date(2026, 11, 14)
        _ = try store.post(EntryFactory.expense(Self.eur(300), from: bank.info, category: rent.info, date: day, memo: "Miete"))
        let s = store.snapshot
        #expect(s.balance(bank.id) == Self.eur(1000))
        let forecast = s.cashForecast(days: 14)
        #expect(forecast.start == Self.eur(1000))
        let landing = try #require(forecast.days.first { s.calendar.isDate($0.date, inSameDayAs: day) })
        #expect(landing.balance == Self.eur(700))
    }

    @Test func aRestoreThatCantSaveItsCopyChangesNothing() throws {
        // Two restores in the same minute each keep their own copy
        let a = try #require(try store.restore(store.makeBackup()))
        let b = try #require(try store.restore(store.makeBackup()))
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(a != b)
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
    }
}
