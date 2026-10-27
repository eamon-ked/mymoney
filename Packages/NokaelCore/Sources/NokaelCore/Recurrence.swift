import Foundation

// MARK: - Schedules

public enum Frequency: Hashable, Codable, Sendable {
    case weekly(every: Int)
    case monthly(every: Int)
    case quarterly
    case annually
    case everyDays(Int)

    public var label: String {
        switch self {
        case .weekly(1): return "Weekly"
        case .weekly(let n): return "Every \(n) weeks"
        case .monthly(1): return "Monthly"
        case .monthly(let n): return "Every \(n) months"
        case .quarterly: return "Quarterly"
        case .annually: return "Yearly"
        case .everyDays(let n): return "Every \(n) days"
        }
    }
}

public struct Schedule: Hashable, Codable, Sendable {
    public var start: Date
    public var frequency: Frequency
    public var end: Date?

    public init(start: Date, frequency: Frequency, end: Date? = nil) {
        self.start = start
        self.frequency = frequency
        self.end = end
    }
}

public enum RecurrenceEngine {
    /// Due dates in [from, through]. Each date is computed from the start, so a
    /// bill on the 31st lands on the last day of short months and returns to the 31st.
    public static func dates(for schedule: Schedule, from: Date, through: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        let limit = min(through, schedule.end ?? through)
        var k = 0
        while k < 5000 {
            guard let date = nth(k, schedule, calendar) else { break }
            if date > limit { break }
            if date >= from { result.append(date) }
            k += 1
        }
        return result
    }

    /// The first due date on or after `date`
    public static func next(for schedule: Schedule, onOrAfter date: Date, calendar: Calendar) -> Date? {
        var k = 0
        while k < 5000, let d = nth(k, schedule, calendar) {
            if let end = schedule.end, d > end { return nil }
            if d >= date { return d }
            k += 1
        }
        return nil
    }

    private static func nth(_ k: Int, _ s: Schedule, _ calendar: Calendar) -> Date? {
        switch s.frequency {
        case .weekly(let n): return calendar.date(byAdding: .day, value: 7 * max(n, 1) * k, to: s.start)
        case .monthly(let n): return calendar.date(byAdding: .month, value: max(n, 1) * k, to: s.start)
        case .quarterly: return calendar.date(byAdding: .month, value: 3 * k, to: s.start)
        case .annually: return calendar.date(byAdding: .year, value: k, to: s.start)
        case .everyDays(let n): return calendar.date(byAdding: .day, value: max(n, 1) * k, to: s.start)
        }
    }
}

// MARK: - Planned items and their occurrences

public enum Direction: String, Codable, Sendable {
    /// A bill or other payment going out
    case outflow
    /// Expected money coming in, like a salary
    case inflow
}

/// A bill or expected income: a schedule, never posted money by itself
public struct PlannedItem: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var direction: Direction
    public var amount: Money
    /// Variable amounts (utilities) are estimates until a payment confirms them
    public var isEstimate: Bool
    public var schedule: Schedule
    /// Account it is paid from (outflow) or received into (inflow)
    public var accountId: UUID?
    public var categoryId: UUID?
    /// The card or loan this pays, if it's a debt payment
    public var debtId: UUID?

    public init(id: UUID = UUID(), name: String, direction: Direction, amount: Money, isEstimate: Bool = false,
                schedule: Schedule, accountId: UUID? = nil, categoryId: UUID? = nil, debtId: UUID? = nil) {
        self.id = id
        self.name = name
        self.direction = direction
        self.amount = amount
        self.isEstimate = isEstimate
        self.schedule = schedule
        self.accountId = accountId
        self.categoryId = categoryId
        self.debtId = debtId
    }
}

public enum OccurrenceState: String, Codable, Sendable {
    case scheduled, dueToday, overdue, partiallyPaid, paid, skipped
}

/// One due date of a planned item, and what has actually been paid against it
public struct Occurrence: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let itemId: UUID
    public var dueDate: Date
    public var expected: Money
    public var isEstimate: Bool
    public var paid: Money
    public var paidEntryIds: [UUID]
    public var skipped: Bool
    /// The estimate a payment settled, kept so voiding that payment can put it back
    public var settledEstimate: Money?

    public init(id: UUID = UUID(), itemId: UUID, dueDate: Date, expected: Money, isEstimate: Bool = false,
                paid: Money? = nil, paidEntryIds: [UUID] = [], skipped: Bool = false, settledEstimate: Money? = nil) {
        self.id = id
        self.itemId = itemId
        self.dueDate = dueDate
        self.expected = expected
        self.isEstimate = isEstimate
        self.paid = paid ?? .zero(expected.currency)
        self.paidEntryIds = paidEntryIds
        self.skipped = skipped
        self.settledEstimate = settledEstimate
    }

    public var remaining: Money { Money.max(expected - paid, .zero(expected.currency)) }

    /// Paid, partly paid or skipped occurrences are history and never regenerated
    public var isSettledOrStarted: Bool { skipped || paid.isPositive }

    public func state(today: Date, calendar: Calendar) -> OccurrenceState {
        if skipped { return .skipped }
        if paid.isPositive && remaining.isZero { return .paid }
        if paid.isPositive { return .partiallyPaid }
        let startOfToday = calendar.startOfDay(for: today)
        if dueDate < startOfToday { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: today) { return .dueToday }
        return .scheduled
    }

    /// Records a posted payment against this occurrence. A payment that is
    /// already recorded is ignored, so matching twice never double-counts.
    public mutating func recordPayment(entryId: UUID, amount: Money) {
        guard !paidEntryIds.contains(entryId) else { return }
        paidEntryIds.append(entryId)
        paid += amount
        // A confirmed payment settles an estimate at the real amount
        if isEstimate {
            settledEstimate = expected
            isEstimate = false
        }
        if settledEstimate != nil { expected = paid }
    }

    /// Takes a payment back off. The state always follows from what's still
    /// linked: with no payments left, a settled estimate becomes an estimate again.
    public mutating func removePayment(entryId: UUID, amount: Money) {
        guard let i = paidEntryIds.firstIndex(of: entryId) else { return }
        paidEntryIds.remove(at: i)
        paid -= amount
        guard let estimate = settledEstimate else { return }
        if paidEntryIds.isEmpty {
            expected = estimate
            isEstimate = true
            settledEstimate = nil
        } else {
            expected = paid
        }
    }
}

public enum OccurrencePlanner {
    /// Rebuilds an item's occurrences up to `through` after its schedule or amount
    /// changed. History is kept untouched: anything before `from`, and anything
    /// paid, partly paid or skipped. Only unpaid occurrences from `from` on follow
    /// the new schedule.
    public static func regenerate(_ item: PlannedItem, existing: [Occurrence], from: Date, through: Date,
                                  calendar: Calendar) -> [Occurrence] {
        let mine = existing.filter { $0.itemId == item.id }
        let kept = mine.filter { $0.dueDate < from || $0.isSettledOrStarted }
        let keptDays = Set(kept.map { calendar.startOfDay(for: $0.dueDate) })
        let fresh = RecurrenceEngine.dates(for: item.schedule, from: from, through: through, calendar: calendar)
            .filter { !keptDays.contains(calendar.startOfDay(for: $0)) }
            .map { date -> Occurrence in
                // Reuse the id of an unpaid occurrence on the same day, so links stay stable
                let reused = mine.first { !$0.isSettledOrStarted && calendar.isDate($0.dueDate, inSameDayAs: date) }
                return Occurrence(id: reused?.id ?? UUID(), itemId: item.id, dueDate: date,
                                  expected: item.amount, isEstimate: item.isEstimate)
            }
        return (kept + fresh).sorted { $0.dueDate < $1.dueDate }
    }
}
