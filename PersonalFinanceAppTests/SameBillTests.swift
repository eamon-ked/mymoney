//
//  SameBillTests.swift
//  Nokael Money
//
//  One payment kept as two bills holds the money back twice. A loan takes over
//  a bill already kept for it, Home asks which to keep when two look the same,
//  and money sent to people stays out of the budget.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct SameBillTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 11, 2)
    /// Kept for as long as the store uses it
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        bank = try store.addAccount(name: "Current", kind: .bank, balance: Self.aed(20000), openingDate: today)
    }

    private func loanBill(day: Int) throws -> PlannedItem {
        let item = PlannedItem(name: "Loan payment", direction: .outflow, amount: Self.aed(5781),
                               schedule: Schedule(start: LedgerStoreTests.date(2026, 11, day), frequency: .monthly(every: 1)),
                               accountId: bank.id, categoryId: store.loanCategory.id)
        try store.savePlannedItem(item)
        return item
    }

    private func loan() throws -> LedgerAccountRecord {
        try store.addAccount(name: "Construction", kind: .loan, balance: Self.aed(200000), openingDate: today)
    }

    private var bills: [PlannedItem] { store.snapshot.items.filter { $0.direction == .outflow } }

    @Test func aLoanTakesOverTheBillAlreadyKeptForIt() throws {
        let kept = try loanBill(day: 26)
        let construction = try loan()
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(5781), dueDay: 30),
                                for: construction.id, paidFrom: bank.id)
        #expect(bills.count == 1)
        #expect(bills.first?.id == kept.id)
        #expect(store.snapshot.paymentItem(for: construction.id)?.id == kept.id)
        #expect(store.snapshot.duplicateBills.isEmpty)
    }

    @Test func aStatementLoanIsntAddedTwice() throws {
        let construction = try loan()
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(5781), dueDay: 30),
                                for: construction.id, paidFrom: bank.id)
        let finding = StatementFinding(kind: .loan, name: "Loan", amount: Self.aed(5781), nextDate: LedgerStoreTests.date(2026, 11, 26))
        try store.acceptFinding(finding, accountId: bank.id)
        #expect(bills.count == 1)
    }

    @Test func homeAsksWhichOfTwoLikeBillsToKeep() throws {
        // How the duplicate came about before: a loan's bill, and one kept by hand
        let byHand = try loanBill(day: 26)
        let other = PlannedItem(name: "Kredit", direction: .outflow, amount: Self.aed(5781),
                                schedule: Schedule(start: LedgerStoreTests.date(2026, 11, 30), frequency: .monthly(every: 1)),
                                accountId: bank.id, categoryId: store.loanCategory.id)
        try store.savePlannedItem(other)
        // A skipped month on one doesn't hide it
        let november = try #require(store.snapshot.occurrences.first { $0.itemId == byHand.id })
        try store.skip(occurrenceId: november.id)
        let task = try #require(HomeTask.all(store.snapshot).first { if case .sameBills = $0 { true } else { false } })

        // Keeping both stops the question
        try store.updateSettings { $0.dismissedFindings.append(task.id) }
        #expect(!HomeTask.all(store.snapshot).contains { $0.id == task.id })

        try store.keepBill(byHand.id, stopping: other.id)
        #expect(bills.map(\.id) == [byHand.id])
    }

    @Test func keepingTheHandMadeBillKeepsTheLoansLink() throws {
        let construction = try loan()
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(5781), dueDay: 30),
                                for: construction.id, paidFrom: bank.id)
        let linked = try #require(store.snapshot.paymentItem(for: construction.id))
        let byHand = try loanBill(day: 26)
        #expect(store.snapshot.duplicateBills.count == 1)
        try store.keepBill(byHand.id, stopping: linked.id)
        #expect(store.snapshot.paymentItem(for: construction.id)?.id == byHand.id)
        #expect(store.snapshot.duplicateBills.isEmpty)
    }

    @Test func differentLoansOrAmountsArentTheSameBill() throws {
        let a = try loan()
        let b = try store.addAccount(name: "Car", kind: .loan, balance: Self.aed(50000), openingDate: today)
        for l in [a, b] {
            try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(1000), dueDay: 5), for: l.id, paidFrom: bank.id)
        }
        _ = try loanBill(day: 26)
        #expect(bills.count == 3)
        #expect(store.snapshot.duplicateBills.isEmpty)
    }

    @Test func moneySentToPeopleIsntBudgeted() throws {
        try store.post(EntryFactory.expense(Self.aed(350), from: bank.info, category: store.peopleCategory.info, date: today))
        let s = store.snapshot
        #expect(!s.budgetCategories.contains { $0.id == store.peopleCategory.id })
        #expect(!HomeTask.all(s).contains { if case .noBudget = $0 { true } else { false } })
    }
}
