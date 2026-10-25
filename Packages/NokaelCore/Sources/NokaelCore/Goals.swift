//
//  Goals.swift
//  NokaelCore
//
//  Savings goals: how far along a goal is and what it takes each month to
//  reach the target by its date. The saved amount is money set aside (a
//  Reserve), so it's already kept out of safe-to-spend.
//

import Foundation

public enum GoalStatus: Hashable, Sendable {
    case reached
    /// Needs this much a month over the months left to hit the date
    case needsPerMonth(Money, months: Int)
    /// No date set, so there's no monthly amount to aim for
    case noDate
    /// The date has passed and the target wasn't reached
    case pastDue
}

public struct GoalProgress: Hashable, Sendable {
    public let saved: Money
    public let target: Money
    public let remaining: Money
    /// 0…1
    public let fraction: Double
    public let status: GoalStatus
}

public enum GoalCalculator {
    public static func progress(saved: Money, target: Money, targetDate: Date?, today: Date, calendar: Calendar) -> GoalProgress {
        let zero = Money.zero(target.currency)
        let remaining = Money.max(target - saved, zero)
        let fraction = target.isPositive ? min(1, max(0, Double(saved.minorUnits) / Double(target.minorUnits))) : 1
        let status: GoalStatus
        if !remaining.isPositive {
            status = .reached
        } else if let targetDate {
            let months = monthsLeft(from: today, to: targetDate, calendar: calendar)
            status = months > 0 ? .needsPerMonth(perMonth(remaining, months: months), months: months) : .pastDue
        } else {
            status = .noDate
        }
        return GoalProgress(saved: saved, target: target, remaining: remaining, fraction: fraction, status: status)
    }

    /// Monthly saving opportunities before the date: today's month counts while
    /// the date is still ahead, so a goal due later this month needs one payment.
    public static func monthsLeft(from today: Date, to date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        guard end >= start else { return 0 }
        let a = calendar.dateComponents([.year, .month], from: start)
        let b = calendar.dateComponents([.year, .month], from: end)
        return ((b.year ?? 0) - (a.year ?? 0)) * 12 + ((b.month ?? 0) - (a.month ?? 0)) + 1
    }

    /// Splits what's left evenly, rounding up so the target is met
    static func perMonth(_ remaining: Money, months: Int) -> Money {
        let m = Int64(max(months, 1))
        return Money(minorUnits: (remaining.minorUnits + m - 1) / m, currency: remaining.currency)
    }
}
