//
//  Reminders.swift
//  NokaelCore
//
//  Which bill reminders should be waiting on the device right now. The app
//  replaces its scheduled notifications with this list whenever data changes,
//  so a paid, skipped or edited bill never sends a stale reminder.
//

import Foundation

public struct BillReminder: Hashable, Sendable, Identifiable {
    /// The occurrence's id; one reminder per due date
    public var id: UUID { occurrenceId }
    public let occurrenceId: UUID
    public let itemId: UUID
    public let name: String
    public let amount: Money
    public let isEstimate: Bool
    public let dueDate: Date
    public let fireDate: Date
    /// 0 means on the day it's due
    public let daysBefore: Int
}

public enum ReminderPlanner {
    /// iOS keeps at most 64 pending notifications per app; leave room for others
    public static let defaultLimit = 60

    /// Unpaid, unskipped bills whose reminder time is still ahead, soonest first.
    /// `daysBefore` per item; a negative value turns reminders off for that bill.
    public static func plan(items: [PlannedItem], occurrences: [Occurrence], daysBefore: [UUID: Int],
                            now: Date, hour: Int, limit: Int = defaultLimit, calendar: Calendar) -> [BillReminder] {
        let bills = Dictionary(items.filter { $0.direction == .outflow }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [BillReminder] = []
        for occ in occurrences where !occ.skipped && occ.remaining.isPositive {
            guard let item = bills[occ.itemId] else { continue }
            let days = daysBefore[item.id] ?? 2
            guard days >= 0,
                  let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: occ.dueDate)),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now else { continue }
            out.append(BillReminder(occurrenceId: occ.id, itemId: item.id, name: item.name, amount: occ.remaining,
                                    isEstimate: occ.isEstimate, dueDate: occ.dueDate, fireDate: fire, daysBefore: days))
        }
        return Array(out.sorted { ($0.fireDate, $0.name) < ($1.fireDate, $1.name) }.prefix(limit))
    }
}
