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
        let sts = SafePeriod.safeToSpend(snapshot)
        let due = snapshot.upcomingBills(days: 30)
        // Privacy Mode covers the widget too: the figures never leave the app while it's on
        let hidden = Redesign.Privacy.stored().on
        func shown(_ money: Money) -> String { hidden ? "\(money.currency) \(Redesign.hiddenDigits)" : money.compact }
        let summary = WidgetSummary(
            safeToSpend: snapshot.setupComplete ? sts.amount.map(shown) : nil,
            isNegative: sts.amount?.isNegative ?? false,
            through: sts.periodEnd,
            bills: due.prefix(3).compactMap { occ in
                snapshot.item(for: occ).map {
                    .init(name: $0.name, amount: shown(occ.remaining), due: occ.dueDate, overdue: snapshot.state(of: occ) == .overdue)
                }
            },
            billsTotal: shown(due.map(\.remaining).sum(snapshot.currency)),
            updated: Date(),
            isPlus: isPlus)
        try? summary.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
