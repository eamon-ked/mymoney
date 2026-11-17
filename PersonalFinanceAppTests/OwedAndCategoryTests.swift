//
//  OwedAndCategoryTests.swift
//  Nokael Money
//
//  Money owed that never went through an account, and turning budget categories off. Made-up data.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct OwedAndCategoryTests {
    static func eur(_ v: Decimal) -> Money { Money(v, currency: "EUR") }

    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord
    let calendar = LedgerStoreTests.dubai

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.updateSettings { $0.currency = "EUR" }
        try store.addStarterCategories()
        let start = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        current = try store.createAccount(name: "Current", kind: .bank, opening: Self.eur(1000), openingDate: start)
    }

    var longAgo: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))! }

    @Test func moneyLentLongAgoIsOwedWithoutTouchingAnAccount() throws {
        let sam = try store.lentAccount(named: "Sam")
        let worthBefore = store.snapshot.netWorth.total
        try store.changeOwed(Self.eur(200), person: sam.id, date: longAgo, memo: "Lent to Sam, not from an account")
        #expect(store.snapshot.balance(sam.id) == Self.eur(200))
        #expect(store.snapshot.balance(current.id) == Self.eur(1000))
        // What Sam owes was always yours, so it counts in net worth
        #expect(store.snapshot.netWorth.total == worthBefore + Self.eur(200))
        // Paid back in cash already spent: owed goes down, the account still doesn't move
        try store.changeOwed(Self.eur(-50), person: sam.id, date: longAgo, memo: "Paid back by Sam, not into an account")
        #expect(store.snapshot.balance(sam.id) == Self.eur(150) && store.snapshot.balance(current.id) == Self.eur(1000))
        // Never more paid back than owed
        #expect(throws: StoreError.self) { try store.changeOwed(Self.eur(-500), person: sam.id, date: longAgo, memo: "x") }
    }

    @Test func aDebtWhoseMoneyIsSpentIsOwedWithoutTouchingAnAccount() throws {
        let alex = try store.lentAccount(named: "Alex")
        try store.changeOwed(Self.eur(-300), person: alex.id, date: longAgo, memo: "Borrowed from Alex, not into an account")
        #expect(store.snapshot.balance(alex.id) == Self.eur(-300))
        #expect(store.snapshot.balance(current.id) == Self.eur(1000))
        #expect(throws: StoreError.self) { try store.changeOwed(Self.eur(400), person: alex.id, date: longAgo, memo: "x") }
    }

    @Test func aCategoryTurnedOffLeavesTheBudgetAndGivesBackItsPlan() throws {
        let s = store.snapshot
        let groceries = try #require(s.expenseCategories.first { $0.name == "Groceries" })
        let month = s.monthKey
        try store.setAllocation(Self.eur(300), categoryId: groceries.id, month: month)
        let unplanned = store.snapshot.budget.availableToAllocate(month: month)
        try store.setCategoryInUse(groceries.id, false)
        #expect(!store.snapshot.budgetCategories.contains { $0.id == groceries.id })
        #expect(store.snapshot.budget.allocated(groceries.id, month: month).isZero)
        #expect(store.snapshot.budget.availableToAllocate(month: month) == unplanned + Self.eur(300))
        // Back on, with no plan
        try store.setCategoryInUse(groceries.id, true)
        #expect(store.snapshot.budgetCategories.contains { $0.id == groceries.id })
    }
}
