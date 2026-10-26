//
//  WidgetSync.swift
//  Nokael Money
//
//  Saves the widget's figures to the shared App Group after each change and
//  asks WidgetKit to redraw. Demo and UI-test runs leave the real widget alone.
//

import Foundation
import WidgetKit
import NokaelCore

@MainActor
enum WidgetSync {
    static func update(_ snapshot: FinanceSnapshot, isPlus: Bool) {
        let args = CommandLine.arguments
        guard !(args.contains("-uiTesting") || args.contains("-demoData")) || args.contains("-widgetData") else { return }
        let sts = snapshot.safeToSpend()
        let due = snapshot.upcomingBills(days: 30)
        let summary = WidgetSummary(
            safeToSpend: snapshot.setupComplete ? sts.amount?.compact : nil,
            isNegative: sts.amount?.isNegative ?? false,
            through: sts.periodEnd,
            bills: due.prefix(3).compactMap { occ in
                snapshot.item(for: occ).map {
                    .init(name: $0.name, amount: occ.remaining.compact, due: occ.dueDate, overdue: snapshot.state(of: occ) == .overdue)
                }
            },
            billsTotal: due.map(\.remaining).sum(snapshot.currency).compact,
            updated: Date(),
            isPlus: isPlus)
        try? summary.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
