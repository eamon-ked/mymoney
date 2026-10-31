//
//  LendingTests.swift
//  Nokael Money
//
//  Money sent to other people: spending on them, or lent and owed back.
//  Lent money leaves safe-to-spend but stays in net worth and isn't spent;
//  what comes back isn't income; what never comes back becomes spending.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct LendingTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 10, 30)
    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        current = try store.createAccount(name: "Current account", kind: .bank, opening: Self.aed(10_000), openingDate: today)
    }

    private var month: String { store.snapshot.monthKey }
    private func spent(_ category: LedgerAccountRecord) -> Money { store.snapshot.budget.spent(category.id, month: month) }

    @Test func lendingIsNotSpending() throws {
        let ahmed = try store.lentAccount(named: "Ahmed")
        try store.lend(Self.aed(2000), to: ahmed.id, from: current.id, date: today)
        let s = store.snapshot
        #expect(s.balance(ahmed.id) == Self.aed(2000))
        #expect(s.balance(current.id) == Self.aed(8000))
        #expect(s.safeToSpend().spendableTotal == Self.aed(8000))
        #expect(s.netWorth.total == Self.aed(10_000))
        #expect(s.expenseCategories.allSatisfy { spent($0).isZero })
        #expect(try store.lentAccount(named: "ahmed ").id == ahmed.id)
    }

    @Test func paidBackIsNotIncome() throws {
        let ahmed = try store.lentAccount(named: "Ahmed")
        try store.lend(Self.aed(2000), to: ahmed.id, from: current.id, date: today)
        try store.receiveRepayment(Self.aed(500), from: ahmed.id, into: current.id, date: today)
        #expect(store.snapshot.balance(ahmed.id) == Self.aed(1500))
        #expect(store.snapshot.balance(current.id) == Self.aed(8500))
        #expect(throws: StoreError.self) { try store.receiveRepayment(Self.aed(1501), from: ahmed.id, into: current.id, date: today) }
    }

    @Test func notPaidBackBecomesSpending() throws {
        let ahmed = try store.lentAccount(named: "Ahmed")
        try store.lend(Self.aed(2000), to: ahmed.id, from: current.id, date: today)
        try store.forgive(Self.aed(2000), owedBy: ahmed.id, date: today)
        #expect(store.snapshot.balance(ahmed.id).isZero)
        #expect(store.snapshot.netWorth.total == Self.aed(8000))
        #expect(store.peopleCategory.name == "Sent to people")
        #expect(store.snapshot.expenseCategories.filter { $0.name == "Sent to people" }.count == 1)
    }

    @Test func aTransferRecordedAsSpendingBecomesLent() throws {
        let people = store.peopleCategory
        let id = try store.post(EntryFactory.expense(Self.aed(750), from: current.info, category: people.info, date: today, memo: "TRF TO SARA"))
        #expect(spent(people) == Self.aed(750))
        let sara = try store.lentAccount(named: "Sara")
        try store.recordAsLending(id, person: sara.id)
        #expect(spent(people).isZero)
        #expect(store.snapshot.balance(sara.id) == Self.aed(750))
        #expect(store.snapshot.balance(current.id) == Self.aed(9250))
        #expect(store.entryRecord(id)?.status == .void)
    }

    @Test func moneyBackRecordedAsIncomeBecomesARepayment() throws {
        let sara = try store.lentAccount(named: "Sara")
        try store.lend(Self.aed(1000), to: sara.id, from: current.id, date: today)
        let other = try #require(store.snapshot.incomeCategories.first { $0.name == "Other income" })
        let id = try store.post(EntryFactory.income(Self.aed(400), to: current.info, category: other.info, date: today, memo: "TRF FROM SARA"))
        try store.recordAsLending(id, person: sara.id)
        #expect(store.snapshot.balance(sara.id) == Self.aed(600))
        #expect(store.snapshot.balance(current.id) == Self.aed(9400))
    }

    @Test func moneySentToSomeoneIsGuessedAsSpendingOnPeople() async throws {
        let s = store.snapshot
        #expect(CategoryRules.guess("IPP TRF TO MOHAMMED", income: false, categories: s.expenseCategories.map(\.name)) == "Sent to people")
        #expect(CategoryRules.guess("Zelle payment to John", income: false, categories: s.expenseCategories.map(\.name)) == "Sent to people")
        // A transfer fee is still a fee
        #expect(CategoryRules.guess("TRF CHARGES", income: false, categories: s.expenseCategories.map(\.name)) == "Interest & fees")
        #expect(!CategoryRules.isSentToPeople("CARREFOUR CITY"))
    }

    @Test func withoutTheCategoryItIsAddedWhenNeeded() async throws {
        // An older setup with no "Sent to people" yet
        let people = store.peopleCategory
        try store.updateAccount(people) { $0.name = "Gifts to family" }
        let found = try await CaptureService.category(for: "UPI transfer 8812", income: false, snapshot: store.snapshot, store: store)
        #expect(found.id == people.id)
    }

    // MARK: Both ways, splits and reminders

    @Test func borrowingIsNotIncomeAndPayingBackIsNotSpending() throws {
        let sam = try store.lentAccount(named: "Sam")
        try store.borrow(Self.aed(500), from: sam.id, into: current.id, date: today)
        var s = store.snapshot
        #expect(s.balance(sam.id) == Self.aed(-500))
        #expect(s.balance(current.id) == Self.aed(10_500))
        #expect(s.netWorth.total == Self.aed(10_000))
        #expect(s.incomeCategories.allSatisfy { s.budget.spent($0.id, month: month).isZero })
        #expect(throws: StoreError.self) { try store.payBack(Self.aed(501), to: sam.id, from: current.id, date: today) }
        try store.payBack(Self.aed(500), to: sam.id, from: current.id, date: today)
        s = store.snapshot
        #expect(s.balance(sam.id).isZero)
        #expect(s.expenseCategories.allSatisfy { spent($0).isZero })
    }

    @Test func lendingOnACard() throws {
        let card = try store.addAccount(name: "Card", kind: .creditCard, balance: Self.aed(0), openingDate: today)
        let sam = try store.lentAccount(named: "Sam")
        try store.lend(Self.aed(200), to: sam.id, from: card.id, date: today)
        #expect(store.snapshot.balance(sam.id) == Self.aed(200))
        #expect(store.snapshot.owed(card.id) == Self.aed(200))
    }

    @Test func moneyFromSomeoneWhoOwedNothingIsBorrowed() throws {
        let sara = try store.lentAccount(named: "Sara")
        let other = try #require(store.snapshot.incomeCategories.first { $0.name == "Other income" })
        let id = try store.post(EntryFactory.income(Self.aed(300), to: current.info, category: other.info, date: today, memo: "TRF FROM SARA"))
        try store.recordAsLending(id, person: sara.id)
        #expect(store.snapshot.balance(sara.id) == Self.aed(-300))
    }

    @Test func aSplitBillCountsOnlyYourShare() throws {
        let food = try #require(store.snapshot.expenseCategories.first { $0.name == "Dining out" } ?? store.snapshot.expenseCategories.first)
        let sam = try store.lentAccount(named: "Sam")
        let alex = try store.lentAccount(named: "Alex")
        var form = EntryForm(kind: .expense, amount: Self.aed(300), accountId: current.id, categoryId: food.id, memo: "Dinner", date: today)
        form.shares = [(sam.id, Self.aed(100)), (alex.id, Self.aed(100))]
        let id = try store.save(form)
        let s = store.snapshot
        #expect(spent(food) == Self.aed(100))
        #expect(s.balance(sam.id) == Self.aed(100))
        #expect(s.balance(alex.id) == Self.aed(100))
        #expect(s.balance(current.id) == Self.aed(9700))
        // The list shows what left the account
        let app = Redesign.AppModel(store: store, plus: PlusStore())
        let t = try #require(app.transaction(id))
        #expect(t.amount == 300)
        #expect(t.accountId == current.id)
    }

    @Test func aBillAFriendPaidIsYourSpendingAndWhatYouOweThem() throws {
        let food = try #require(store.snapshot.expenseCategories.first)
        let sam = try store.lentAccount(named: "Sam")
        let id = try store.save(EntryForm(kind: .expense, amount: Self.aed(80), accountId: sam.id, categoryId: food.id, date: today))
        #expect(spent(food) == Self.aed(80))
        #expect(store.snapshot.balance(sam.id) == Self.aed(-80))
        #expect(store.snapshot.balance(current.id) == Self.aed(10_000))
        let t = try #require(Redesign.AppModel(store: store, plus: PlusStore()).transaction(id))
        #expect(t.amount == 80)
        #expect(t.flow == .out)
    }

    @Test func peopleNeedYouWhenPastTheirDateOrQuietForAMonth() throws {
        let sam = try store.lentAccount(named: "Sam")
        let old = LedgerStoreTests.date(2026, 9, 1)
        try store.lend(Self.aed(200), to: sam.id, from: current.id, date: old)
        #expect(HomeTask.people(store.snapshot).count == 1)
        // A date still ahead holds the reminder back; once it passes, it's due either way
        try store.setOwedBackBy(LedgerStoreTests.date(2026, 11, 5), for: sam.id)
        #expect(HomeTask.people(store.snapshot).isEmpty)
        let alex = try store.lentAccount(named: "Alex")
        try store.borrow(Self.aed(50), from: alex.id, into: current.id, date: today)
        #expect(HomeTask.people(store.snapshot).isEmpty)
        try store.setOwedBackBy(LedgerStoreTests.date(2026, 10, 20), for: alex.id)
        let tasks = HomeTask.people(store.snapshot)
        #expect(tasks.count == 1)
        if case .person(let p, let balance, _) = tasks.first { #expect(p.id == alex.id); #expect(balance == Self.aed(-50)) }
        // The date survives a backup
        let backup = try LedgerStore.readBackup(try store.backupData())
        #expect(backup.accounts.first { $0.id == alex.id }?.owedBackBy != nil)
    }
}
