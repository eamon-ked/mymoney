//
//  NotificationPlanner.swift
//  NokaelCore
//
//  Every notification the phone schedules for itself, as facts: what it's
//  about, when it fires and how much it matters. The app turns them into words
//  (so they can be translated) and replaces what's scheduled whenever data
//  changes. iOS keeps at most 64 waiting, so the most urgent win the places.
//

import Foundation

public enum NoticeKind: String, Sendable, CaseIterable, Codable {
    // Scheduled ahead
    case billDue, billMissed, runningShort, payday, trialEnding
    case backup, setUp, statement, friend, monthReview
    // Sent the moment something happens
    case milestone, purchase, payArrived, unknownAccount, foreignCurrency, unusual

    /// Lower comes first when there are more than iOS will hold
    public var priority: Int {
        switch self {
        case .runningShort: 0
        case .billMissed: 1
        case .billDue: 2
        case .trialEnding: 3
        case .payday: 4
        case .backup: 5
        case .friend: 6
        case .setUp: 7
        case .statement: 8
        case .monthReview: 9
        case .milestone, .purchase, .payArrived, .unknownAccount, .foreignCurrency, .unusual: 10
        }
    }
}

public struct PlannedNotice: Hashable, Sendable, Identifiable {
    /// Stable, so replacing the schedule never sends one twice
    public let id: String
    public let kind: NoticeKind
    public let fireDate: Date
    public var name: String = ""
    public var amount: Money?
    public var isEstimate = false
    /// When the thing it's about happens: a bill's due date, a trial's first charge
    public var date: Date?
    public var occurrenceId: UUID?
    public var itemId: UUID?
    /// The account, person, goal or loan it's about
    public var subjectId: UUID?
    /// 0 is "due today"; only for bill reminders
    public var daysBefore: Int?

    public init(id: String, kind: NoticeKind, fireDate: Date, name: String = "", amount: Money? = nil,
                isEstimate: Bool = false, date: Date? = nil, occurrenceId: UUID? = nil, itemId: UUID? = nil,
                subjectId: UUID? = nil, daysBefore: Int? = nil) {
        self.id = id; self.kind = kind; self.fireDate = fireDate; self.name = name; self.amount = amount
        self.isEstimate = isEstimate; self.date = date; self.occurrenceId = occurrenceId; self.itemId = itemId
        self.subjectId = subjectId; self.daysBefore = daysBefore
    }

    /// Worth breaking through Focus: a bill due today, or money about to run out
    public var isUrgent: Bool { kind == .runningShort || (kind == .billDue && daysBefore == 0) }
}

public enum NotificationPlanner {
    /// iOS holds 64; four stay free for the ones sent the moment spending arrives
    public static let limit = 60

    /// The most urgent first, then the soonest, up to `limit`
    public static func fit(_ notices: [PlannedNotice], limit: Int = limit, calendar: Calendar = .current) -> [PlannedNotice] {
        // A running-short warning (there's only ever one) always stays. Then soonest first, so a reminder due
        // today is never pushed out by follow-ups months away; the kind only decides between notices on one day
        Array(notices.sorted { a, b in
            let dayA = calendar.startOfDay(for: a.fireDate), dayB = calendar.startOfDay(for: b.fireDate)
            return (a.kind == .runningShort ? 0 : 1, dayA, a.kind.priority, a.fireDate, a.id)
                < (b.kind == .runningShort ? 0 : 1, dayB, b.kind.priority, b.fireDate, b.id)
        }.prefix(limit))
    }

    // MARK: - Bills

    /// Reminders before each bill, and a "did it go out?" the morning after one that's still unpaid
    public static func bills(items: [PlannedItem], occurrences: [Occurrence], daysBefore: [UUID: Int],
                             now: Date, hour: Int, calendar: Calendar) -> [PlannedNotice] {
        let due = ReminderPlanner.plan(items: items, occurrences: occurrences, daysBefore: daysBefore, now: now,
                                       hour: hour, limit: .max, calendar: calendar).map { r in
            PlannedNotice(id: "bill-\(r.occurrenceId)", kind: .billDue, fireDate: r.fireDate, name: r.name, amount: r.amount,
                          isEstimate: r.isEstimate, date: r.dueDate, occurrenceId: r.occurrenceId, itemId: r.itemId,
                          daysBefore: r.daysBefore)
        }
        let bills = Dictionary(items.filter { $0.direction == .outflow }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let missed = occurrences.compactMap { occ -> PlannedNotice? in
            guard !occ.skipped, occ.remaining.isPositive, let item = bills[occ.itemId], (daysBefore[item.id] ?? 2) >= 0,
                  let fire = morning(after: occ.dueDate, days: 1, hour: hour, calendar: calendar), fire > now else { return nil }
            return PlannedNotice(id: "missed-\(occ.id)", kind: .billMissed, fireDate: fire, name: item.name, amount: occ.remaining,
                                 isEstimate: occ.isEstimate, date: occ.dueDate, occurrenceId: occ.id, itemId: item.id)
        }
        return due + missed
    }

    /// The bill that would take spendable money below zero in the next two weeks, the morning before it's due
    public static func runningShort(_ forecast: CashForecast, now: Date, hour: Int, calendar: Calendar) -> PlannedNotice? {
        // The lowest point in the day counts, so rent going out on payday morning still warns
        guard let day = forecast.days.first(where: { $0.low.isNegative }),
              let bill = day.events.filter({ $0.amount.isNegative }).min(by: { $0.amount < $1.amount }) else { return nil }
        let today = calendar.startOfDay(for: now)
        // The morning before, or this morning's hour if that's passed but the day hasn't come yet
        let candidates = [morning(after: day.date, days: -1, hour: hour, calendar: calendar),
                          day.date > today ? morning(after: now, days: 0, hour: hour, calendar: calendar) : nil]
        guard let fire = candidates.compactMap({ $0 }).first(where: { $0 > now }) else { return nil }
        return PlannedNotice(id: "short-\(bill.occurrenceId)", kind: .runningShort, fireDate: fire, name: bill.name,
                             amount: day.low.negated, date: day.date, occurrenceId: bill.occurrenceId, itemId: bill.itemId)
    }

    /// The morning pay is expected, while it hasn't been recorded
    public static func payday(items: [PlannedItem], occurrences: [Occurrence], now: Date, hour: Int,
                              calendar: Calendar) -> PlannedNotice? {
        let pay = Dictionary(items.filter { $0.direction == .inflow }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return occurrences.filter { !$0.skipped && $0.remaining.isPositive && pay[$0.itemId] != nil }
            .compactMap { occ -> PlannedNotice? in
                guard let fire = morning(after: occ.dueDate, days: 0, hour: hour, calendar: calendar), fire > now else { return nil }
                return PlannedNotice(id: "payday-\(occ.id)", kind: .payday, fireDate: fire, name: pay[occ.itemId]!.name,
                                     amount: occ.remaining, isEstimate: occ.isEstimate, date: occ.dueDate,
                                     occurrenceId: occ.id, itemId: occ.itemId)
            }
            .min { $0.fireDate < $1.fireDate }
    }

    /// Two days before a free trial's first charge, while it can still be cancelled
    public static func trials(items: [PlannedItem], occurrences: [Occurrence], trialIds: Set<UUID>, now: Date, hour: Int,
                              calendar: Calendar) -> [PlannedNotice] {
        items.filter { trialIds.contains($0.id) }.compactMap { item in
            let first = calendar.startOfDay(for: item.schedule.start)
            guard let occ = occurrences.first(where: { $0.itemId == item.id && calendar.startOfDay(for: $0.dueDate) == first }),
                  !occ.skipped, occ.remaining.isPositive,
                  let fire = [morning(after: first, days: -2, hour: hour, calendar: calendar),
                              morning(after: first, days: -1, hour: hour, calendar: calendar)]
                    .compactMap({ $0 }).first(where: { $0 > now }) else { return nil }
            return PlannedNotice(id: "trial-\(occ.id)", kind: .trialEnding, fireDate: fire, name: item.name, amount: occ.expected,
                                 isEstimate: occ.isEstimate, date: occ.dueDate, occurrenceId: occ.id, itemId: item.id)
        }
    }

    // MARK: - Dates

    /// `hour` o'clock, `days` after the day `date` falls on
    public static func morning(after date: Date, days: Int, hour: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
            .flatMap { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) }
    }

    /// The first of `anchor`, anchor + a week, anchor + two weeks… that's still ahead, at `hour`.
    /// Nags that wait on the person (a backup, say) come at most once a week this way, however often data changes.
    public static func weekly(from anchor: Date, after now: Date, hour: Int, calendar: Calendar) -> Date? {
        guard var fire = morning(after: anchor, days: 0, hour: hour, calendar: calendar) else { return nil }
        if fire <= now {
            let days = calendar.dateComponents([.day], from: fire, to: now).day ?? 0
            fire = calendar.date(byAdding: .day, value: (days / 7) * 7, to: fire) ?? fire
            while fire <= now { fire = calendar.date(byAdding: .day, value: 7, to: fire) ?? now.addingTimeInterval(7 * 86400) }
        }
        return fire
    }

    /// `day` of the next month that hasn't reached it yet, at `hour`
    public static func next(dayOfMonth day: Int, after now: Date, hour: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month], from: now)
        parts.day = day; parts.hour = hour
        guard let thisMonth = calendar.date(from: parts) else { return nil }
        return thisMonth > now ? thisMonth : calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }
}
