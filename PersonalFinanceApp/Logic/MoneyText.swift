//
//  MoneyText.swift
//  Nokael Money
//
//  Amounts as words for Siri, the AI and notifications, and the budget
//  states the rules use. Screens draw amounts through Redesign.AppModel.
//

import Foundation
import NokaelCore

extension Money {
    /// Full precision, e.g. "AED 1,250.50"
    var formatted: String { MoneyFormat.string(self) }
    /// Drops ".00" on whole amounts, for rows and pills
    var compact: String { MoneyFormat.string(self, dropWholeFraction: true) }
    /// Rounded to whole units, for the big figure on a summary card, e.g. "AED 1,216"
    var whole: String {
        let unit = Int64((0..<Currency.scale(of: currency)).reduce(1) { r, _ in r * 10 })
        let rounded = (minorUnits + (minorUnits < 0 ? -unit : unit) / 2) / unit * unit
        return Money(minorUnits: rounded, currency: currency).compact
    }
    /// With an explicit sign for changes, e.g. "+AED 50" / "−AED 85"
    var signed: String {
        if isZero { return compact }
        return (isNegative ? "−" : "+") + magnitude.compact
    }
}

extension CategoryLine {
    /// More spent than the budget allowed. Spending where no budget was set isn't "over"
    var isOverBudget: Bool { planned.isPositive && isOverspent }
    /// Money spent in a category that has no budget this month
    var isUnbudgetedSpending: Bool { !planned.isPositive && spent.isPositive }
}

extension Payoff {
    /// One line for rows, e.g. "Paid off Aug 2029"
    var shortText: String {
        switch self {
        case .alreadyPaidOff: return "Paid off"
        case .paidOff(_, let last, _, _): return "Paid off " + last.formatted(.dateTime.month(.abbreviated).year())
        case .never: return "Payment doesn't cover interest"
        case .beyondHorizon: return "Over 50 years to pay off"
        }
    }
}

extension DebtTerms {
    var rateText: String { "\(annualRatePercent.formatted(.number.precision(.fractionLength(0...2))))% a year" }
}

extension GoalProgress {
    /// e.g. "Save 1,000 a month", "Goal reached"
    var advice: String {
        switch status {
        case .reached: return "Goal reached"
        case .needsPerMonth(let amount, let months):
            return months == 1 ? "Save \(amount.compact) this month" : "Save \(amount.compact) a month"
        case .noDate: return "\(remaining.compact) to go"
        case .pastDue: return "Date passed, \(remaining.compact) to go"
        }
    }
}

/// Budget's filter pills
enum BudgetFilter: CaseIterable {
    case all, over, notPlanned, moneyLeft

    /// The pill's label
    var title: String {
        switch self {
        case .all: "All"
        case .over: "Over"
        case .notPlanned: "No budget"
        case .moneyLeft: "Money left"
        }
    }

    func matches(_ line: CategoryLine) -> Bool {
        switch self {
        case .all: true
        case .over: line.isOverBudget
        case .notPlanned: !line.planned.isPositive
        case .moneyLeft: line.remaining.isPositive
        }
    }
}
