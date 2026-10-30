//
//  Reports.swift
//  NokaelCore
//
//  Where the money went: income, spending and what was left for a month,
//  spending by category against last month and the plan, and a trend over
//  several months. Built from category activity, so transfers between accounts
//  never count as spending. A loan payment counts in full under its loan's
//  category; a card's principal doesn't, since its purchases already counted.
//

import Foundation

public struct CategoryTotal: Hashable, Sendable, Identifiable {
    public var id: UUID { categoryId }
    public let categoryId: UUID
    public let name: String
    public let amount: Money
    public let previous: Money
    /// What was planned in Budget for the month, if anything
    public let planned: Money?

    public var change: Money { amount - previous }
}

public struct MonthTotals: Hashable, Sendable, Identifiable {
    public var id: String { month }
    public let month: String
    public let income: Money
    public let spending: Money

    public var leftOver: Money { income - spending }
    /// Share of income not spent, 0…1; nil without income
    public var savingsRate: Double? {
        guard income.isPositive else { return nil }
        return Double(leftOver.minorUnits) / Double(income.minorUnits)
    }
}

public struct MonthReport: Hashable, Sendable {
    public let totals: MonthTotals
    public let previous: MonthTotals
    /// Spending categories with activity this month or last, largest first
    public let spending: [CategoryTotal]
    /// Income categories with activity this month or last, largest first
    public let income: [CategoryTotal]
}

public enum Reports {
    public static func totals(_ month: String, ledger: Ledger, expenseCategories: [AccountInfo],
                              incomeCategories: [AccountInfo], calendar: Calendar, loanCategories: [UUID: UUID] = [:]) -> MonthTotals {
        let range = bounds(month, calendar: calendar)
        let income = incomeCategories.map { ledger.activity(on: $0.id, from: range.start, to: range.end) }.sum(ledger.currency)
        let spending = expenseCategories
            .map { ledger.spending(on: $0.id, from: range.start, to: range.end, loanCategories: loanCategories) }
            .sum(ledger.currency)
        return MonthTotals(month: month, income: income, spending: spending)
    }

    public static func month(_ month: String, ledger: Ledger, expenseCategories: [AccountInfo],
                             incomeCategories: [AccountInfo], budget: Budget? = nil, calendar: Calendar,
                             loanCategories: [UUID: UUID] = [:]) -> MonthReport {
        let previousKey = BudgetMonth.adding(-1, to: month, calendar: calendar)
        let now = bounds(month, calendar: calendar)
        let before = bounds(previousKey, calendar: calendar)
        func lines(_ categories: [AccountInfo], planned: Bool) -> [CategoryTotal] {
            categories.map { c in
                let plan = planned ? budget?.allocated(c.id, month: month) : nil
                func amount(_ range: (start: Date, end: Date)) -> Money {
                    planned ? ledger.spending(on: c.id, from: range.start, to: range.end, loanCategories: loanCategories)
                        : ledger.activity(on: c.id, from: range.start, to: range.end)
                }
                return CategoryTotal(categoryId: c.id, name: c.name,
                                     amount: amount(now), previous: amount(before),
                                     planned: plan.flatMap { $0.isZero ? nil : $0 })
            }
            .filter { !$0.amount.isZero || !$0.previous.isZero }
            .sorted { ($0.amount.minorUnits, $0.name) > ($1.amount.minorUnits, $1.name) }
        }
        return MonthReport(
            totals: totals(month, ledger: ledger, expenseCategories: expenseCategories, incomeCategories: incomeCategories,
                           calendar: calendar, loanCategories: loanCategories),
            previous: totals(previousKey, ledger: ledger, expenseCategories: expenseCategories, incomeCategories: incomeCategories,
                             calendar: calendar, loanCategories: loanCategories),
            spending: lines(expenseCategories, planned: true),
            income: lines(incomeCategories, planned: false))
    }

    /// `count` months ending with `month`, oldest first
    public static func trend(endingAt month: String, count: Int, ledger: Ledger, expenseCategories: [AccountInfo],
                             incomeCategories: [AccountInfo], calendar: Calendar, loanCategories: [UUID: UUID] = [:]) -> [MonthTotals] {
        (0..<max(count, 1)).reversed().map {
            totals(BudgetMonth.adding(-$0, to: month, calendar: calendar), ledger: ledger,
                   expenseCategories: expenseCategories, incomeCategories: incomeCategories, calendar: calendar,
                   loanCategories: loanCategories)
        }
    }

    private static func bounds(_ month: String, calendar: Calendar) -> (start: Date, end: Date) {
        let start = BudgetMonth.start(of: month, calendar: calendar) ?? .distantPast
        return (start, BudgetMonth.end(of: month, calendar: calendar) ?? start)
    }
}
