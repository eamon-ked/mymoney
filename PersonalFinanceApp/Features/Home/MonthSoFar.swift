//
//  MonthSoFar.swift
//  Nokael Money
//
//  The one line under Safe to spend: this month's spending so far against the
//  same point last month. Worked out from the ledger, so every figure is exact;
//  the To do list already covers anything over budget, so this never repeats it.
//

import Foundation
import NokaelCore
import SwiftUI

struct MonthSoFar: Equatable {
    let spent: Money
    /// Spending last month up to the same day; nil when there's nothing to compare with
    let lastMonth: Money?
    /// The category with the most spending when there's no comparison to make
    let biggest: String?

    init(spent: Money, lastMonth: Money?, biggest: String?) {
        self.spent = spent
        self.lastMonth = lastMonth
        self.biggest = biggest
    }

    @MainActor init(_ snapshot: FinanceSnapshot) {
        let calendar = snapshot.calendar
        let month = snapshot.monthKey
        let start = BudgetMonth.start(of: month, calendar: calendar) ?? snapshot.today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: snapshot.today)) ?? snapshot.today
        let elapsed = calendar.dateComponents([.day], from: start, to: tomorrow).day ?? 1

        let previous = BudgetMonth.adding(-1, to: month, calendar: calendar)
        let previousStart = BudgetMonth.start(of: previous, calendar: calendar) ?? start
        // Same number of days into last month, never past its end
        let previousCut = min(calendar.date(byAdding: .day, value: elapsed, to: previousStart) ?? start, start)

        // The same categories Reports counts, so the two figures always agree
        let categories = snapshot.accountRecords.filter { $0.kind == .expense }.map(\.info)
        let ledger = snapshot.ledger
        let now = categories.map { ($0.name, ledger.spending(on: $0.id, from: start, to: tomorrow, loanCategories: snapshot.loanCategories)) }
        let before = categories.map { ledger.spending(on: $0.id, from: previousStart, to: previousCut, loanCategories: snapshot.loanCategories) }.sum(snapshot.currency)

        spent = now.map(\.1).sum(snapshot.currency)
        lastMonth = before.isPositive ? before : nil
        biggest = now.filter { $0.1.isPositive }.max { $0.1 < $1.1 }?.0
    }

    /// Nil when there's nothing worth saying yet: no spending this month or last
    var sentence: String? {
        guard spent.isPositive || lastMonth != nil else { return nil }
        guard let lastMonth else {
            if let biggest { return "You've spent \(spent.compact), most of it on \(biggest)." }
            return "You've spent \(spent.compact)."
        }
        guard spent.isPositive else { return "Nothing spent yet. By now last month it was \(lastMonth.compact)." }
        let difference = spent - lastMonth
        // Within 5% reads as the same; a few coins either way isn't news
        if difference.magnitude.minorUnits * 20 <= lastMonth.minorUnits {
            return "You've spent \(spent.compact), about the same as this time last month."
        }
        return difference.isNegative
            ? "You've spent \(spent.compact), \(difference.magnitude.compact) less than this time last month."
            : "You've spent \(spent.compact), \(difference.compact) more than this time last month."
    }
}

/// The month under Safe to spend. Tapping it goes deeper.
struct MonthSoFarCard: View {
    let sentence: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This month so far").font(.caption.weight(.semibold)).foregroundStyle(Palette.brand)
                    Text(sentence).font(.subheadline).foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monthSoFar")
    }
}
