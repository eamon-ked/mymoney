//
//  HomeTasksTests.swift
//  Nokael Money
//
//  Home's to-do list: everything that needs the person, most urgent first,
//  each thing once, and nothing at all when the month is in order.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct HomeTasksTests {
    let container: ModelContainer
    let store: LedgerStore
    let today = LedgerStoreTests.date(2026, 10, 27)

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today.addingTimeInterval(4 * 3600)
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.name == name }!
    }

    private func kind(_ task: HomeTask) -> String {
        switch task {
        case .bill: "bill"
        case .billLink: "billLink"
        case .sameBills: "sameBills"
        case .payday: "payday"
        case .overspent: "overspent"
        case .noBudget: "noBudget"
        case .review: "review"
        case .unplanned: "unplanned"
        case .person: "person"
        case .stale: "stale"
        case .backup: "backup"
        case .finding: "finding"
        case .setUp: "setUp"
        }
    }

    @Test("Bills due first, then a payment to link, overspending, entries to check, unplanned money and the backup")
    func order() throws {
        func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
        try store.addStarterCategories()
        let checking = try store.createAccount(name: "Checking", kind: .bank, opening: aed(5396.67), openingDate: today)
        try store.updateSettings { $0.onboardingDone = true }
        // Rent due today and already paid by hand, so it's offered for linking rather than listed as due
        try store.savePlannedItem(PlannedItem(name: "Rent", direction: .outflow, amount: aed(2500),
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: checking.id, categoryId: category("Rent or mortgage").id))
        try store.post(EntryFactory.expense(aed(2500), from: checking.info, category: category("Rent or mortgage").info,
                                            date: today.addingTimeInterval(3600), memo: "Rent"))
        // The phone bill is due today and not paid
        try store.savePlannedItem(PlannedItem(name: "Phone", direction: .outflow, amount: aed(100),
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: checking.id, categoryId: category("Phone & internet").id))
        // Groceries planned at 100, 150 spent
        try store.setAllocation(aed(100), categoryId: category("Groceries").id, month: store.snapshot.monthKey)
        try store.post(EntryFactory.expense(aed(150), from: checking.info, category: category("Groceries").info,
                                            date: today, memo: "Carrefour"))
        // Three purchases saved from Apple Pay, waiting to be checked, within what was planned for them
        try store.setAllocation(aed(60), categoryId: category("Other spending").id, month: store.snapshot.monthKey)
        for memo in ["Cafe", "Taxi", "Pharmacy"] {
            _ = try store.postCaptured(EntryFactory.expense(aed(20), from: checking.info, category: category("Other spending").info,
                                                            date: today, memo: memo),
                                       source: .applePay, cardHint: nil, needsReview: true)
        }

        let tasks = HomeTask.all(store.snapshot)
        // No pay planned, so Home also asks for a payday, after everything else
        #expect(tasks.map(kind) == ["bill", "billLink", "overspent", "review", "unplanned", "backup", "setUp"])
        if case .review(let count) = tasks[3] { #expect(count == 3) }
        if case .overspent(let c, let by) = tasks[2] { #expect(c.name == "Groceries" && by == aed(50)) }
        if case .bill(let occ) = tasks[0] { #expect(store.snapshot.item(for: occ)?.name == "Phone") }
    }

    @Test("A month in order outside the UAE has nothing to do; overspending in euros shows in euros")
    func euroMonth() throws {
        func eur(_ v: Decimal) -> Money { Money(v, currency: "EUR") }
        try store.updateSettings { $0.currency = "EUR"; $0.localeIdentifier = "de_DE" }
        try store.addStarterCategories()
        let giro = try store.createAccount(name: "Girokonto", kind: .bank, opening: eur(1000), openingDate: today)
        try store.updateSettings { $0.onboardingDone = true }
        try store.setAllocation(eur(1000), categoryId: category("Groceries").id, month: store.snapshot.monthKey)
        // Only the optional setup: a payday and bills, which this person hasn't added
        #expect(HomeTask.all(store.snapshot).map(\.id) == ["setUp-payday", "setUp-bills"])

        try store.post(EntryFactory.expense(eur(1200), from: giro.info, category: category("Groceries").info, date: today, memo: "Rewe"))
        let first = try #require(HomeTask.all(store.snapshot).first)
        guard case .overspent(_, let by) = first else { Issue.record("expected overspending first, got \(kind(first))"); return }
        #expect(by == eur(200))
    }

    @Test("Spending with no budget is its own item, not overspending, and it lowers money not in a budget")
    func spendingWithNoBudget() throws {
        func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Bank", kind: .bank, opening: aed(10000), openingDate: today)
        try store.updateSettings { $0.onboardingDone = true }
        let month = store.snapshot.monthKey
        try store.setAllocation(aed(1000), categoryId: category("Groceries").id, month: month)
        let before = store.snapshot.budget.availableToAllocate(month: month)
        try store.post(EntryFactory.expense(aed(4436), from: bank.info, category: category("Transport").info, date: today))
        try store.post(EntryFactory.expense(aed(42.87), from: bank.info, category: category("Phone & internet").info, date: today))

        let snapshot = store.snapshot
        #expect(snapshot.budget.availableToAllocate(month: month) == before - aed(4478.87))
        let tasks = HomeTask.all(snapshot)
        #expect(!tasks.contains { if case .overspent = $0 { true } else { false } })
        let noBudget = tasks.compactMap { task -> ([String], Money)? in
            if case .noBudget(let cs, let total) = task { (cs.map(\.name), total) } else { nil }
        }
        #expect(noBudget.first?.0 == ["Transport", "Phone & internet"])
        #expect(noBudget.first?.1 == aed(4478.87))
    }

    @Test("Nothing set up yet: no to-do items")
    func emptyStore() {
        #expect(HomeTask.all(store.snapshot).isEmpty)
    }

    @Test("Budget filters pick out over, unplanned and money-left categories")
    func budgetFilters() throws {
        func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Bank", kind: .bank, opening: aed(3000), openingDate: today)
        let month = store.snapshot.monthKey
        try store.setAllocation(aed(100), categoryId: category("Groceries").id, month: month)
        try store.setAllocation(aed(300), categoryId: category("Transport").id, month: month)
        try store.post(EntryFactory.expense(aed(150), from: bank.info, category: category("Groceries").info, date: today))
        try store.post(EntryFactory.expense(aed(20), from: bank.info, category: category("Dining out").info, date: today))

        let budget = store.snapshot.budget
        func names(_ f: BudgetFilter) -> Set<String> {
            Set(store.snapshot.expenseCategories.filter { f.matches(budget.line($0.id, month: month)) }.map(\.name))
        }
        // Dining out has spending but no budget: that's "no budget set", not "over"
        #expect(names(.over) == ["Groceries"])
        #expect(names(.moneyLeft) == ["Transport"])
        #expect(names(.notPlanned).contains("Dining out") && !names(.notPlanned).contains("Transport"))
        #expect(budget.line(category("Dining out").id, month: month).isUnbudgetedSpending)
        #expect(names(.all).count == store.snapshot.expenseCategories.count)
    }
}
