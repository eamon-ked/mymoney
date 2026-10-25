//
//  Forecast.swift
//  NokaelCore
//
//  The calendar of money in and out: starting from what's in spendable
//  accounts today, each unpaid bill and expected income is applied on its
//  date to show the balance ahead, its lowest point and any shortfall.
//  A projection only; nothing here touches the ledger.
//

import Foundation

public struct ForecastEvent: Hashable, Sendable, Identifiable {
    public var id: UUID { occurrenceId }
    public let occurrenceId: UUID
    public let itemId: UUID
    public let name: String
    /// Positive for money coming in, negative for money going out
    public let amount: Money
    public let dueDate: Date
    public let isEstimate: Bool
    /// Was due before today and is still unpaid; counted today
    public let isOverdue: Bool
}

public struct ForecastDay: Hashable, Sendable, Identifiable {
    public var id: Date { date }
    /// Start of the day
    public let date: Date
    public let events: [ForecastEvent]
    /// Spendable balance at the end of the day
    public let balance: Money

    public var net: Money { events.map(\.amount).sum(balance.currency) }
}

public struct CashForecast: Hashable, Sendable {
    public let start: Money
    /// Only days with something happening, in date order
    public let days: [ForecastDay]
    public let lowest: Money
    public let lowestDate: Date
    /// The first day the projected balance goes below zero
    public let firstShortfall: Date?

    public var end: Money { days.last?.balance ?? start }
    public var moneyIn: Money { days.flatMap(\.events).map(\.amount).filter(\.isPositive).sum(start.currency) }
    public var moneyOut: Money { days.flatMap(\.events).map(\.amount).filter(\.isNegative).sum(start.currency).negated }
}

public enum CashForecaster {
    /// - Parameters:
    ///   - start: what spendable accounts hold today
    ///   - spendableAccountIds: items paid from or into other accounts don't move this balance;
    ///     items without an account are assumed to use spendable money
    public static func forecast(start: Money, items: [PlannedItem], occurrences: [Occurrence],
                                spendableAccountIds: Set<UUID>, today: Date, through end: Date,
                                calendar: Calendar) -> CashForecast {
        let todayStart = calendar.startOfDay(for: today)
        let itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var events: [ForecastEvent] = []
        for occ in occurrences where !occ.skipped && occ.remaining.isPositive && occ.dueDate <= end {
            guard let item = itemsById[occ.itemId] else { continue }
            if let account = item.accountId, !spendableAccountIds.contains(account) { continue }
            let overdue = occ.dueDate < todayStart
            events.append(ForecastEvent(occurrenceId: occ.id, itemId: item.id, name: item.name,
                                        amount: item.direction == .inflow ? occ.remaining : occ.remaining.negated,
                                        dueDate: occ.dueDate, isEstimate: occ.isEstimate, isOverdue: overdue))
        }

        // Overdue items land today; same-day money out is applied before money in,
        // so a shortfall on a payday isn't hidden by the salary arriving later that day
        let byDay = Dictionary(grouping: events) { max(calendar.startOfDay(for: $0.dueDate), todayStart) }
        var balance = start
        var lowest = start
        var lowestDate = todayStart
        var firstShortfall: Date? = start.isNegative ? todayStart : nil
        var days: [ForecastDay] = []
        for date in byDay.keys.sorted() {
            let dayEvents = byDay[date]!.sorted { ($0.amount.isNegative ? 0 : 1, $0.name) < ($1.amount.isNegative ? 0 : 1, $1.name) }
            for e in dayEvents {
                balance += e.amount
                if balance < lowest { lowest = balance; lowestDate = date }
                if balance.isNegative && firstShortfall == nil { firstShortfall = date }
            }
            days.append(ForecastDay(date: date, events: dayEvents, balance: balance))
        }
        return CashForecast(start: start, days: days, lowest: lowest, lowestDate: lowestDate, firstShortfall: firstShortfall)
    }
}
