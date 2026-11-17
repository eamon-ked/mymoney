//
//  NokaelWidget.swift
//  Nokael Money widget
//
//  Safe to spend and the next bills on the home and lock screens, and a
//  Control Center button to log spending. Reads the summary the app saves
//  after every change; amounts are hidden while the iPhone is locked.
//

import WidgetKit
import SwiftUI
import AppIntents
import NokaelCore

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: .now, summary: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: .now, summary: context.isPreview ? (WidgetSummary.load() ?? .sample) : WidgetSummary.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        // The app reloads the widget on every change; midnight refreshes "due tomorrow" wording, and a
        // summary whose period has ended is no longer shown (see the view): it asks for the app instead
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let summary = WidgetSummary.load()
        var entries = [SummaryEntry(date: .now, summary: summary)]
        if let end = summary?.through, end > .now, end < midnight { entries.append(SummaryEntry(date: end.addingTimeInterval(1), summary: summary)) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct SafeToSpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SummaryEntry

    /// Tinted and clear Home Screens drop colour, so red alone can't mark what's late or below zero
    private var warning: Color { renderingMode == .fullColor ? .red : .primary }

    var body: some View {
        Group {
            if let summary = entry.summary, summary.isPlus == false {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nokael Plus", systemImage: "star.circle.fill").font(.caption.weight(.semibold))
                    Text("Unlock the widget with Nokael Plus in the app").font(.caption).foregroundStyle(.secondary)
                }
            } else if let summary = entry.summary, summary.through >= entry.date {
                switch family {
                case .accessoryInline: inline(summary)
                case .accessoryRectangular: rectangular(summary)
                case .systemMedium: medium(summary)
                default: small(summary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nokael Money", systemImage: "banknote").font(.caption.weight(.semibold))
                    Text("Open the app to see what's safe to spend").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetLink.breakdown.url)
    }

    private func amount(_ s: WidgetSummary) -> some View {
        Text(s.safeToSpend ?? "Finish setup")
            .font(.title2.weight(.bold)).monospacedDigit()
            .minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(s.isNegative ? warning : .primary)
            .widgetAccentable(s.isNegative)
            .privacySensitive()
    }

    private func small(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Safe to spend").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            amount(s)
            Text("until \(s.through.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let next = s.bills.first {
                Text("Next: \(next.name)").font(.caption2.weight(.medium)).lineLimit(1)
                Text(due(next)).font(.caption2.weight(next.overdue ? .semibold : .regular))
                    .foregroundStyle(next.overdue ? warning : .secondary).widgetAccentable(next.overdue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WidgetSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe to spend").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                amount(s)
                Text("until \(s.through.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link(destination: WidgetLink.addExpense.url) {
                    Image(systemName: "plus").font(.body.weight(.semibold))
                        .frame(width: 36, height: 36).background(.fill.secondary, in: Circle())
                }
                .accessibilityLabel(Text("Add spending"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Link(destination: WidgetLink.bills.url) { bills(s) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func bills(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bills · \(s.billsTotal)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).privacySensitive()
            if s.bills.isEmpty { Text("Nothing due soon").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(s.bills.prefix(3).enumerated()), id: \.offset) { _, bill in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(bill.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(bill.amount).font(.caption).monospacedDigit().privacySensitive()
                    }
                    Text(due(bill)).font(.caption2.weight(bill.overdue ? .semibold : .regular))
                        .foregroundStyle(bill.overdue ? warning : .secondary).widgetAccentable(bill.overdue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangular(_ s: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Safe to spend").font(.caption2)
            Text(s.safeToSpend ?? "—").font(.headline).monospacedDigit().privacySensitive()
            if let next = s.bills.first { Text("\(next.name) \(due(next).lowercased())").font(.caption2).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: WidgetSummary) -> some View {
        Text("Safe to spend \(s.safeToSpend ?? "—")").privacySensitive()
    }

    private func due(_ bill: WidgetSummary.Bill) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: entry.date), to: cal.startOfDay(for: bill.due)).day ?? 0
        switch days {
        case ..<0: return String(localized: "Overdue")
        case 0: return String(localized: "Due today")
        case 1: return String(localized: "Due tomorrow")
        default: return String(localized: "Due \(bill.due.formatted(.dateTime.weekday(.abbreviated).day()))")
        }
    }
}

struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SafeToSpend", provider: SummaryProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
        }
        .configurationDisplayName("Safe to spend")
        .description("What you can spend until payday, and the bills coming up.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

/// Control Center, the Lock Screen and the Action button: opens Add Expense in the app
@available(iOS 18.0, *)
struct LogSpendingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogSpending") {
            ControlWidgetButton(action: OpenAddExpenseIntent()) {
                Label("Log spending", systemImage: "plus.circle")
            }
        }
        .displayName("Log spending")
        .description("Opens Nokael Money to add something you spent.")
    }
}

@available(iOS 18.0, *)
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log spending"
    // Only the control uses it; Siri and Shortcuts have their own "Log spending" action
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.addExpense.url))
    }
}

@main
struct NokaelWidgets: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
        if #available(iOS 18.0, *) { LogSpendingControl() }
    }
}

extension WidgetSummary {
    /// The widget gallery's preview, in the currency of the person's region
    static var sample: WidgetSummary {
        let code = Locale.current.currency?.identifier ?? "USD"
        func money(_ amount: Int) -> String { Decimal(amount).formatted(.currency(code: code).precision(.fractionLength(0))) }
        func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: .now) ?? .now }
        return WidgetSummary(
            safeToSpend: money(1240), isNegative: false, through: day(9),
            bills: [.init(name: String(localized: "Rent"), amount: money(1500), due: day(3), overdue: false),
                    .init(name: String(localized: "Phone"), amount: money(45), due: day(5), overdue: false)],
            billsTotal: money(1545), updated: .now, isPlus: true)
    }
}
