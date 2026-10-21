//
//  BudgetCalculator.swift
//  PersonalFinanceApp
//
//  YNAB-style budget math over plain values, so it can be unit-tested without
//  SwiftData. Nothing here is a stored running total.
//
//  Ready to Assign (as of month m) =
//      opening balances of on-budget accounts
//    + inflows to the budget through month m
//    − outflows from the budget that have no category, through month m
//    − everything assigned in any month (future months included, as in YNAB)
//
//  Available(c, m) = Σ assigned(c, k ≤ m) − Σ spent(c, k ≤ m)
//  Unspent money rolls forward; overspending carries forward until covered.
//

import Foundation

enum BudgetMonth {
    /// "yyyy-MM" in the user's calendar and time zone
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    static func adding(_ months: Int, to key: String, calendar: Calendar = .current) -> String {
        guard let start = date(from: key, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: start) else { return key }
        return self.key(for: moved, calendar: calendar)
    }
}

struct BudgetCalculator {
    struct AccountInfo {
        let id: UUID
        let openingBalance: Decimal
        let onBudget: Bool
    }

    struct Entry {
        let accountId: UUID
        let transferAccountId: UUID?
        let categoryId: UUID?
        let amount: Decimal
        let type: TransactionType
        let month: String
    }

    struct Assignment {
        let categoryId: UUID
        let month: String
        let assigned: Decimal
    }

    struct CategoryLine: Equatable {
        let assigned: Decimal   // this month only
        let spent: Decimal      // this month only, positive number
        let available: Decimal  // cumulative through this month
    }

    let accounts: [AccountInfo]
    let entries: [Entry]
    let assignments: [Assignment]

    private var onBudgetIds: Set<UUID> {
        Set(accounts.filter(\.onBudget).map(\.id))
    }

    // MARK: - Ready to Assign

    func readyToAssign(through month: String) -> Decimal {
        let budgetIds = onBudgetIds
        var total = accounts.filter(\.onBudget).reduce(Decimal(0)) { $0 + $1.openingBalance }

        for e in entries where e.month <= month {
            let fromBudget = budgetIds.contains(e.accountId)
            switch e.type {
            case .income:
                if fromBudget { total += e.amount }
            case .expense:
                // Categorised spending draws on its category instead
                if fromBudget && e.categoryId == nil { total -= e.amount }
            case .transfer:
                guard let to = e.transferAccountId else { continue }
                let toBudget = budgetIds.contains(to)
                // Between two budget accounts a transfer moves cash, not budget
                if fromBudget && !toBudget { total -= e.amount }
                if !fromBudget && toBudget { total += e.amount }
            }
        }

        total -= assignments.reduce(Decimal(0)) { $0 + $1.assigned }
        return total
    }

    // MARK: - Categories

    func line(for categoryId: UUID, month: String) -> CategoryLine {
        let budgetIds = onBudgetIds
        var assignedThisMonth: Decimal = 0
        var assignedToDate: Decimal = 0
        for a in assignments where a.categoryId == categoryId && a.month <= month {
            assignedToDate += a.assigned
            if a.month == month { assignedThisMonth += a.assigned }
        }

        var spentThisMonth: Decimal = 0
        var spentToDate: Decimal = 0
        for e in entries where e.type == .expense
            && e.categoryId == categoryId
            && e.month <= month
            && budgetIds.contains(e.accountId) {
            spentToDate += e.amount
            if e.month == month { spentThisMonth += e.amount }
        }

        return CategoryLine(assigned: assignedThisMonth,
                            spent: spentThisMonth,
                            available: assignedToDate - spentToDate)
    }

    /// How much more the category needs this month to meet its monthly target
    func neededThisMonth(target: Decimal?, line: CategoryLine) -> Decimal {
        guard let target, target > 0 else { return 0 }
        return max(0, target - line.assigned)
    }
}
