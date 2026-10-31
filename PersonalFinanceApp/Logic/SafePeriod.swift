//
//  SafePeriod.swift
//  Nokael Money
//
//  How far ahead safe to spend looks. The person picks it on the breakdown,
//  and Home, the breakdown and the widget all use it. It's this phone's choice,
//  so it's kept in UserDefaults rather than in the data a backup carries.
//

import Foundation
import NokaelCore

enum SafePeriod: String, CaseIterable {
    case untilPayday, week, monthEnd, date

    var title: String {
        switch self {
        case .untilPayday: "Until payday"
        case .week: "7 days"
        case .monthEnd: "Month end"
        case .date: "A date"
        }
    }

    private static let key = "safePeriod"
    private static let dateKey = "safePeriodDate"

    static var saved: SafePeriod {
        get { UserDefaults.standard.string(forKey: key).flatMap(SafePeriod.init) ?? .untilPayday }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var savedDate: Date {
        get { UserDefaults.standard.object(forKey: dateKey) as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: dateKey) }
    }

    /// The last moment counted; nil means the usual end (the day before payday, or the month's end)
    @MainActor func end(in s: FinanceSnapshot, picked: Date = SafePeriod.savedDate) -> Date? {
        switch self {
        case .untilPayday: return nil
        case .week: return s.endOfDay(s.calendar.date(byAdding: .day, value: 7, to: s.today) ?? s.today)
        case .monthEnd:
            let start = BudgetMonth.start(of: s.monthKey, calendar: s.calendar) ?? s.today
            return s.endOfDay(s.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? s.today)
        case .date:
            // A date that has passed falls back to payday rather than showing a period that's over
            return picked >= s.calendar.startOfDay(for: s.today) ? s.endOfDay(picked) : nil
        }
    }

    /// The saved choice, worked out on this snapshot
    @MainActor static func safeToSpend(_ s: FinanceSnapshot) -> SafeToSpend {
        s.safeToSpend(through: saved.end(in: s))
    }
}
