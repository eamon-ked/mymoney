//
//  Debt.swift
//  NokaelCore
//
//  Cards and loans: what a month of interest costs, how a payment splits
//  into interest and principal, and when the debt is paid off at a given
//  monthly payment. Amounts owed are positive here; the ledger stores them
//  as negative balances.
//

import Foundation

/// How a card or loan is charged and repaid
public struct DebtTerms: Hashable, Codable, Sendable {
    /// Yearly interest rate in hundredths of a percent: 1250 is 12.50%
    public var annualRateBps: Int
    /// What the person plans to pay each month (the instalment, or a card's minimum or more)
    public var monthlyPayment: Money
    /// Day of the month the payment is due, 1–31; short months use their last day
    public var dueDay: Int?

    public init(annualRateBps: Int, monthlyPayment: Money, dueDay: Int? = nil) {
        self.annualRateBps = annualRateBps
        self.monthlyPayment = monthlyPayment
        self.dueDay = dueDay
    }

    /// The rate as a percentage, e.g. 12.5
    public var annualRatePercent: Decimal { Decimal(annualRateBps) / 100 }

    /// Parses "12.5" or "12.5%" into basis points; nil when it isn't a rate
    public static func rateBps(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let d = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              d >= 0, d <= 100 else { return nil }
        var bps = d * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &bps, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

/// One payment, divided the way lenders apply it: interest and fees first, then principal
public struct PaymentSplit: Hashable, Sendable {
    public let interest: Money
    public let fees: Money
    public let principal: Money
    /// Paid beyond what was owed; nothing is left to apply it to
    public let overpaid: Money

    public var total: Money { interest + fees + principal + overpaid }
}

/// When a debt is paid off at a fixed monthly payment
public enum Payoff: Hashable, Sendable {
    case alreadyPaidOff
    /// Months of payments, the date of the last one, interest paid on the way and the last (smaller) payment
    case paidOff(months: Int, lastPayment: Date, totalInterest: Money, finalPayment: Money)
    /// The payment doesn't cover the interest, so the balance never falls
    case never(monthlyInterest: Money)
    /// Longer than the horizon (50 years)
    case beyondHorizon
}

public enum DebtCalculator {
    /// The longest payoff worked out, in months
    public static let horizonMonths = 600

    /// One month's interest on what's owed: owed × rate ÷ 12, rounded half up to the minor unit
    public static func monthlyInterest(owed: Money, annualRateBps: Int) -> Money {
        guard owed.isPositive, annualRateBps > 0 else { return .zero(owed.currency) }
        let numerator = owed.minorUnits * Int64(annualRateBps)
        let denominator: Int64 = 12 * 10_000
        return Money(minorUnits: (numerator + denominator / 2) / denominator, currency: owed.currency)
    }

    /// Splits a payment into interest, fees and principal. Interest defaults to one
    /// month at the debt's rate and never exceeds the payment; principal never
    /// exceeds what's owed, and anything beyond that is reported as overpaid.
    public static func split(payment: Money, owed: Money, annualRateBps: Int,
                             interest: Money? = nil, fees: Money? = nil) -> PaymentSplit {
        let c = payment.currency
        let zero = Money.zero(c)
        guard payment.isPositive else { return PaymentSplit(interest: zero, fees: zero, principal: zero, overpaid: zero) }
        let feePart = Money.min(Money.max(fees ?? zero, zero), payment)
        let interestDue = interest ?? monthlyInterest(owed: owed, annualRateBps: annualRateBps)
        let interestPart = Money.min(Money.max(interestDue, zero), payment - feePart)
        let rest = payment - feePart - interestPart
        let principal = Money.min(rest, Money.max(owed, zero))
        return PaymentSplit(interest: interestPart, fees: feePart, principal: principal, overpaid: rest - principal)
    }

    /// Works out the payoff month by month: interest is added, then the payment taken off.
    /// `extra` is added to every monthly payment to show the effect of paying more.
    public static func payoff(owed: Money, terms: DebtTerms, extra: Money? = nil,
                              firstPayment: Date, calendar: Calendar) -> Payoff {
        guard owed.isPositive else { return .alreadyPaidOff }
        let payment = terms.monthlyPayment + (extra ?? .zero(owed.currency))
        let firstInterest = monthlyInterest(owed: owed, annualRateBps: terms.annualRateBps)
        guard payment.isPositive, firstInterest < payment else { return .never(monthlyInterest: firstInterest) }

        var balance = owed
        var totalInterest = Money.zero(owed.currency)
        for month in 1...horizonMonths {
            let interest = monthlyInterest(owed: balance, annualRateBps: terms.annualRateBps)
            totalInterest += interest
            balance += interest
            if !(payment < balance) {
                let date = paymentDate(month - 1, after: firstPayment, dueDay: terms.dueDay, calendar: calendar)
                return .paidOff(months: month, lastPayment: date, totalInterest: totalInterest, finalPayment: balance)
            }
            balance -= payment
        }
        return .beyondHorizon
    }

    /// The date of the payment `offset` months after the first, kept on the due day
    static func paymentDate(_ offset: Int, after first: Date, dueDay: Int?, calendar: Calendar) -> Date {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: first) else { return first }
        guard let dueDay else { return shifted }
        var parts = calendar.dateComponents([.year, .month, .hour], from: shifted)
        let days = calendar.range(of: .day, in: .month, for: shifted)?.count ?? 28
        parts.day = min(dueDay, days)
        return calendar.date(from: parts) ?? shifted
    }

    /// The next due date on or after `date` for a due day
    public static func nextDueDate(dueDay: Int, onOrAfter date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        var parts = calendar.dateComponents([.year, .month], from: start)
        parts.hour = 12
        for _ in 0..<2 {
            guard let monthStart = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1, hour: 12)) else { break }
            let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
            parts.day = min(dueDay, days)
            if let candidate = calendar.date(from: parts), candidate >= start { return candidate }
            if let next = calendar.date(byAdding: .month, value: 1, to: monthStart) {
                parts = calendar.dateComponents([.year, .month], from: next)
                parts.hour = 12
            }
        }
        return date
    }
}
