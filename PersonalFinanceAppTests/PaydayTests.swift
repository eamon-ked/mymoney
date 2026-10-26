//
//  PaydayTests.swift
//  Nokael Money
//
//  "I received my salary" uses the salary saved in Plan and does the month's routine.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct PaydayTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 10, 25)

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        _ = try store.createAccount(name: "Cash", kind: .cash, opening: Self.aed(100), openingDate: today)
        bank = try store.createAccount(name: "ENBD Current", kind: .bank, opening: Self.aed(1000), openingDate: today)
        savings = try store.createAccount(name: "Wio Savings", kind: .savings, opening: Self.aed(0), openingDate: today)
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = nil }
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.name == name }!
    }

    private func addSalary() throws {
        try store.savePlannedItem(PlannedItem(name: "Salary", direction: .inflow, amount: Self.aed(20000),
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: bank.id, categoryId: category("Salary").id))
    }

    @Test func usesTheSalaryInPlanNotTheFirstAccountOrCategory() throws {
        try addSalary()
        let plan = PaydayPlan.make(store.snapshot)
        #expect(plan.amount == Self.aed(20000))
        #expect(plan.accountId == bank.id)
        #expect(plan.occurrence != nil)

        _ = try plan.run(store, choices: .init(copyBudget: false), date: today, key: UUID())
        #expect(store.snapshot.balance(bank.id) == Self.aed(21000))
        let entry = try #require(store.snapshot.entries().first { $0.kind == .income })
        #expect(entry.lines.contains { $0.accountId == category("Salary").id })
        #expect(entry.occurrenceId == plan.occurrence?.id)
        // Asking again the same month knows it's done
        #expect(PaydayPlan.make(store.snapshot).alreadyReceived != nil)
    }

    @Test func aDifferentAmountSaidThisMonthWins() throws {
        try addSalary()
        let plan = PaydayPlan.make(store.snapshot, said: Self.aed(21500))
        _ = try plan.run(store, choices: .init(copyBudget: false), date: today, key: UUID())
        #expect(store.snapshot.balance(bank.id) == Self.aed(22500))
    }

    @Test func doesTheMonthsBudgetAndGoals() throws {
        try addSalary()
        let previous = BudgetMonth.adding(-1, to: store.snapshot.monthKey, calendar: store.calendar)
        try store.setAllocation(Self.aed(1500), categoryId: category("Groceries").id, month: previous)
        try store.setAllocation(Self.aed(400), categoryId: category("Transport").id, month: previous)
        let target = store.calendar.date(byAdding: .month, value: 9, to: today)!
        try store.saveReserve(Reserve(name: "Holiday", amount: Self.aed(0), accountId: savings.id,
                                      target: Self.aed(5000), targetDate: target))

        let plan = PaydayPlan.make(store.snapshot)
        #expect(plan.budgetCount == 2 && plan.budgetTotal == Self.aed(1900))
        let goal = try #require(plan.goals.first)
        #expect(goal.amount == Self.aed(500))

        let done = try plan.run(store, choices: .init(copyBudget: true, goals: [goal.id]), date: today, key: UUID())
        #expect(done.count == 3)
        let month = store.snapshot.monthKey
        #expect(store.snapshot.budget.allocated(category("Groceries").id, month: month) == Self.aed(1500))
        #expect(store.snapshot.goals.first?.amount == Self.aed(500))
        #expect(store.snapshot.balance(savings.id) == Self.aed(500))
    }

    @Test func withNoSalaryInPlanItRemembersIt() throws {
        let plan = PaydayPlan.make(store.snapshot, said: Self.aed(18000))
        #expect(plan.item == nil)
        _ = try plan.run(store, choices: .init(copyBudget: false, remember: true), date: today, key: UUID())
        let saved = try #require(PaydayPlan.salaryItem(store.snapshot))
        #expect(saved.amount == Self.aed(18000))
    }

    @Test func recognisesSalaryWording() {
        #expect(PaydayPlan.mentionsSalary("I received my salary today"))
        #expect(PaydayPlan.mentionsSalary("got paid"))
        #expect(!PaydayPlan.mentionsSalary("received 200 from Sam"))
    }
}
