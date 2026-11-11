import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct SecondAuditTests {
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let category: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 11, 8)
    static func aed(_ x: Decimal) -> Money { Money(x, currency: "AED") }
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let date = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { date })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(1000), openingDate: date.addingTimeInterval(-86400))
        category = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = bank.id }
    }
    @Test func editingBalanceCorrectionMustReachRequestedBalance() throws {
        let original = try store.save(EntryForm(kind: .adjustment, amount: Self.aed(1100), accountId: bank.id, date: today, reason: "Bank correction"))
        _ = try store.save(EntryForm(kind: .adjustment, amount: Self.aed(1200), accountId: bank.id, date: today, reason: "Corrected figure"), replacing: original)
        let actual = store.snapshot.balance(bank.id).minorUnits
        #expect(actual == 120000)
    }
    @Test func editingBillPaymentMustRejectOverpayment() throws {
        let item = PlannedItem(name: "Bill", direction: .outflow, amount: Self.aed(100), schedule: Schedule(start: today, frequency: .monthly(every: 1)), accountId: bank.id, categoryId: category.id)
        try store.savePlannedItem(item)
        let occ = try #require(store.snapshot.occurrences.first { $0.itemId == item.id })
        let id = try store.pay(occurrenceId: occ.id, amount: Self.aed(100), accountId: bank.id, categoryId: category.id, date: today, key: UUID())
        var rejected = false
        do { _ = try store.save(EntryForm(kind: .expense, amount: Self.aed(150), accountId: bank.id, categoryId: category.id, date: today, occurrenceId: occ.id), replacing: id) } catch { rejected = true }
        #expect(rejected)
    }
    @Test func repeatedSaveMustNotCreateTwoSchedules() throws {
        let form = EntryForm(kind: .expense, amount: Self.aed(100), accountId: bank.id, categoryId: category.id, memo: "Monthly groceries", date: today, repeats: true)
        let first = try store.save(form); let again = try store.save(form)
        #expect(first == again)
        #expect(store.snapshot.items.count == 1)
    }
    @Test func undoRepeatingEntryMustUndoItsSchedule() throws {
        let app = Redesign.AppModel(store: store, plus: PlusStore())
        let form = EntryForm(kind: .expense, amount: Self.aed(100), accountId: bank.id, categoryId: category.id, memo: "Monthly groceries", date: today, repeats: true)
        #expect(app.save(form) == nil)
        app.undoLast()
        #expect(store.snapshot.balance(bank.id) == Self.aed(1000))
        #expect(store.snapshot.items.isEmpty)
    }
    @Test func archivedMoneyMustNotRemainAvailableToAllocate() throws {
        let second = try store.createAccount(name: "Active", kind: .bank, opening: Self.aed(200), openingDate: today)
        try store.updateAccount(bank) { $0.archived = true }
        let s = store.snapshot
        #expect(s.cashAndBank == Self.aed(200))
        #expect(s.budget.availableToAllocate(month: s.monthKey) == s.balance(second.id))
    }
    @Test func replayingGoalRequestAfterAnotherRequestMustNotAddAgain() throws {
        let goal = Reserve(name: "Trip", amount: Self.aed(0), accountId: bank.id, target: Self.aed(500))
        try store.saveReserve(goal)
        let a = UUID(), b = UUID()
        try store.addToGoal(goal.id, amount: Self.aed(100), from: nil, date: today, key: a)
        try store.addToGoal(goal.id, amount: Self.aed(50), from: nil, date: today, key: b)
        try store.addToGoal(goal.id, amount: Self.aed(100), from: nil, date: today, key: a)
        let saved = store.snapshot.reserves.first { $0.id == goal.id }?.amount.minorUnits
        #expect(saved == 15000)
    }
    @Test func retryingFullDebtPaymentMustReturnExistingPayment() throws {
        let debt = try store.createAccount(name: "Loan", kind: .loan, opening: Self.aed(-100), openingDate: today)
        let key = UUID()
        let first = try store.payDebt(debt.id, from: bank.id, amount: Self.aed(100), interest: Self.aed(0), fees: Self.aed(0), date: today, key: key)
        let retried = try? store.payDebt(debt.id, from: bank.id, amount: Self.aed(100), interest: Self.aed(0), fees: Self.aed(0), date: today, key: key)
        #expect(retried == first)
    }
    @Test func anInvalidGoalFundingAccountMustNotCreateReservedMoney() throws {
        let goal = Reserve(name: "Trip", amount: Self.aed(0), accountId: bank.id, target: Self.aed(500))
        try store.saveReserve(goal)
        var rejected = false
        do { try store.addToGoal(goal.id, amount: Self.aed(100), from: UUID(), date: today, key: UUID()) } catch { rejected = true }
        #expect(rejected)
        #expect(store.snapshot.reserves.first { $0.id == goal.id }?.amount == Self.aed(0))
    }
    @Test func backupMustRejectCurrenciesThatDisagreeWithTheLedger() throws {
        let data = try store.backupData()
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try #require(obj["entries"] as? [[String: Any]])
        var lines = try #require(entries[0]["lines"] as? [[String: Any]])
        for i in lines.indices { lines[i]["currency"] = "USD" }
        entries[0]["lines"] = lines; obj["entries"] = entries
        let altered = try JSONSerialization.data(withJSONObject: obj)
        var rejected = false
        do { _ = try LedgerStore.readBackup(altered) } catch { rejected = true }
        #expect(rejected)
    }
}

@MainActor
struct SecondAuditCrossAccountTests {
    @Test func reconcilingOneSideOfTransferMustNotReconcileTheOther() throws {
        let fixture = try SecondAuditTests(); let store = fixture.store
        let other = try store.createAccount(name: "Savings", kind: .savings, opening: SecondAuditTests.aed(0), openingDate: fixture.today)
        let id = try store.post(EntryFactory.transfer(SecondAuditTests.aed(100), from: fixture.bank.info, to: other.info, date: fixture.today))
        try store.reconcile(accountId: fixture.bank.id, statementDate: fixture.today, statementBalance: SecondAuditTests.aed(900), reason: nil)
        let otherCheck = Reconciler.check(ledger: store.snapshot.ledger, accountId: other.id, statementDate: fixture.today, statementBalance: SecondAuditTests.aed(100))
        #expect(otherCheck.unreconciled.contains { $0.id == id })
    }
    @Test func repeatingJanuary31MustReturnToMarch31() throws {
        let fixture = try SecondAuditTests(); let store = fixture.store
        let cal = LedgerStoreTests.dubai
        let jan = LedgerStoreTests.date(2027, 1, 31), march = LedgerStoreTests.date(2027, 3, 1)
        let form = EntryForm(kind: .expense, amount: SecondAuditTests.aed(100), accountId: fixture.bank.id, categoryId: fixture.category.id, date: jan, repeats: true)
        let item = try #require(form.repeatItem(in: store.snapshot))
        let next = try #require(RecurrenceEngine.next(for: item.schedule, onOrAfter: march, calendar: cal))
        #expect(cal.component(.day, from: next) == 31)
    }
}

@MainActor
struct SecondAuditAssistantFiguresTests {
    @Test func assistantSpendingMustUseOwnShareOfSplitBill() throws {
        let f = try SecondAuditTests(); let store = f.store
        let friend = try store.lentAccount(named: "Sam")
        _ = try store.post(EntryFactory.splitExpense(SecondAuditTests.aed(300), from: f.bank.info, category: f.category.info, shares: [(friend.info, SecondAuditTests.aed(200))], date: f.today, memo: "Dinner split"))
        let answer = FinanceDigest(store.snapshot).search(text: "Dinner split", category: nil, days: nil)
        #expect(answer.contains("Total spent: \(SecondAuditTests.aed(100).compact)"))
    }
    @Test func assistantMustNotCountCardPrincipalAsNewSpending() throws {
        let f = try SecondAuditTests(); let store = f.store
        let card = try store.createAccount(name: "Visa", kind: .creditCard, opening: SecondAuditTests.aed(-100), openingDate: f.today)
        _ = try store.payDebt(card.id, from: f.bank.id, amount: SecondAuditTests.aed(100), interest: SecondAuditTests.aed(0), fees: SecondAuditTests.aed(0), date: f.today, key: UUID())
        let answer = FinanceDigest(store.snapshot).search(text: "Visa payment", category: nil, days: nil)
        #expect(answer.contains("Total spent: \(SecondAuditTests.aed(0).compact)"))
    }
}
