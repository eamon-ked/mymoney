//
//  BudgetCalculatorTests.swift
//  PersonalFinanceAppTests
//
//  Hand-worked months for the YNAB-style budget formulas.
//

import Foundation
import Testing
@testable import PersonalFinanceApp

struct BudgetCalculatorTests {
    let checking = UUID()
    let card = UUID()
    let investments = UUID()
    let groceries = UUID()
    let savings = UUID()

    private var accounts: [BudgetCalculator.AccountInfo] {
        [.init(id: checking, openingBalance: 1000, onBudget: true),
         .init(id: card, openingBalance: 0, onBudget: true),
         .init(id: investments, openingBalance: 5000, onBudget: false)]
    }

    private func entry(_ type: TransactionType, _ amount: Decimal, _ month: String,
                       account: UUID? = nil, to: UUID? = nil, category: UUID? = nil) -> BudgetCalculator.Entry {
        .init(accountId: account ?? checking, transferAccountId: to, categoryId: category,
              amount: amount, type: type, month: month)
    }

    @Test func readyToAssignCountsOnBudgetMoneyOnly() {
        let calc = BudgetCalculator(
            accounts: accounts,
            entries: [entry(.income, 3000, "2026-10"),
                      entry(.income, 200, "2026-10", account: investments)],
            assignments: [.init(categoryId: groceries, month: "2026-10", assigned: 800)])
        // 1000 opening + 3000 salary − 800 assigned; investment money excluded
        #expect(calc.readyToAssign(through: "2026-10") == 3200)
    }

    @Test func futureAssignmentsReduceReadyToAssignNow() {
        let calc = BudgetCalculator(
            accounts: accounts, entries: [],
            assignments: [.init(categoryId: groceries, month: "2026-11", assigned: 300)])
        #expect(calc.readyToAssign(through: "2026-10") == 700)
    }

    @Test func futureIncomeIsNotAvailableYet() {
        let calc = BudgetCalculator(accounts: accounts,
                                    entries: [entry(.income, 3000, "2026-11")],
                                    assignments: [])
        #expect(calc.readyToAssign(through: "2026-10") == 1000)
        #expect(calc.readyToAssign(through: "2026-11") == 4000)
    }

    @Test func uncategorisedSpendingComesOutOfReadyToAssign() {
        let calc = BudgetCalculator(accounts: accounts,
                                    entries: [entry(.expense, 50, "2026-10")],
                                    assignments: [])
        #expect(calc.readyToAssign(through: "2026-10") == 950)
    }

    @Test func transfersOnlyMatterAcrossTheBudgetBoundary() {
        let calc = BudgetCalculator(
            accounts: accounts,
            entries: [entry(.transfer, 400, "2026-10", to: card),          // budget → budget: neutral
                      entry(.transfer, 100, "2026-10", to: investments),   // leaves the budget
                      entry(.transfer, 25, "2026-10", account: investments, to: checking)], // enters it
            assignments: [])
        #expect(calc.readyToAssign(through: "2026-10") == 925)
    }

    @Test func unspentMoneyRollsForward() {
        let calc = BudgetCalculator(
            accounts: accounts,
            entries: [entry(.expense, 300, "2026-10", category: groceries),
                      entry(.expense, 450, "2026-11", category: groceries)],
            assignments: [.init(categoryId: groceries, month: "2026-10", assigned: 500),
                          .init(categoryId: groceries, month: "2026-11", assigned: 500)])
        #expect(calc.line(for: groceries, month: "2026-10") == .init(assigned: 500, spent: 300, available: 200))
        #expect(calc.line(for: groceries, month: "2026-11") == .init(assigned: 500, spent: 450, available: 250))
    }

    @Test func overspendingCarriesForwardUntilCovered() {
        let calc = BudgetCalculator(
            accounts: accounts,
            entries: [entry(.expense, 120, "2026-10", account: card, category: groceries)],
            assignments: [.init(categoryId: groceries, month: "2026-10", assigned: 100)])
        #expect(calc.line(for: groceries, month: "2026-10").available == -20)
        #expect(calc.line(for: groceries, month: "2026-11").available == -20)
        // Card spending draws on the category, not on Ready to Assign
        #expect(calc.readyToAssign(through: "2026-10") == 900)
    }

    @Test func movingMoneyKeepsReadyToAssignUnchanged() {
        let before = BudgetCalculator(
            accounts: accounts, entries: [],
            assignments: [.init(categoryId: savings, month: "2026-10", assigned: 300)])
        let after = BudgetCalculator(
            accounts: accounts, entries: [],
            assignments: [.init(categoryId: savings, month: "2026-10", assigned: 250),
                          .init(categoryId: groceries, month: "2026-10", assigned: 50)])
        #expect(before.readyToAssign(through: "2026-10") == after.readyToAssign(through: "2026-10"))
        #expect(after.line(for: groceries, month: "2026-10").available == 50)
    }

    @Test func neededThisMonthUsesTarget() {
        let calc = BudgetCalculator(accounts: accounts, entries: [],
                                    assignments: [.init(categoryId: savings, month: "2026-10", assigned: 200)])
        let line = calc.line(for: savings, month: "2026-10")
        #expect(calc.neededThisMonth(target: 500, line: line) == 300)
        #expect(calc.neededThisMonth(target: 100, line: line) == 0)
        #expect(calc.neededThisMonth(target: nil, line: line) == 0)
    }

    @Test func monthKeysStepAcrossYears() {
        #expect(BudgetMonth.adding(1, to: "2026-12") == "2027-01")
        #expect(BudgetMonth.adding(-1, to: "2026-01") == "2025-12")
    }
}
