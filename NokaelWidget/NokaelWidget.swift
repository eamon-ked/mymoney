//
//  NokaelWidget.swift
//  Nokael Money widget
//
//  Safe to spend and the next bills on the home and lock screens. Reads the
//  summary the app saves after every change; amounts are hidden while the
//  iPhone is locked.
//

import WidgetKit
import SwiftUI
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
        // The app reloads the widget on every change; midnight refreshes "due tomorrow" wording
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: [SummaryEntry(date: .now, summary: WidgetSummary.load())], policy: .after(midnight)))
    }
}

struct SafeToSpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        Group {
            if let summary = entry.summary {
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
    }

    private func amount(_ s: WidgetSummary) -> some View {
        Text(s.safeToSpend ?? "Finish setup")
            .font(.title2.weight(.bold)).monospacedDigit()
            .minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(s.isNegative ? .red : .primary)
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
                Text(due(next)).font(.caption2).foregroundStyle(next.overdue ? .red : .secondary)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Bills · \(s.billsTotal)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).privacySensitive()
                if s.bills.isEmpty { Text("Nothing due soon").font(.caption).foregroundStyle(.secondary) }
                ForEach(s.bills.prefix(3), id: \.name) { bill in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(bill.name).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(bill.amount).font(.caption).monospacedDigit().privacySensitive()
                        }
                        Text(due(bill)).font(.caption2).foregroundStyle(bill.overdue ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
        case ..<0: return "Overdue"
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        default: return "Due " + bill.due.formatted(.dateTime.weekday(.abbreviated).day())
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

@main
struct NokaelWidgets: WidgetBundle {
    var body: some Widget { SafeToSpendWidget() }
}

extension WidgetSummary {
    static let sample = WidgetSummary(
        safeToSpend: "AED 1,240", isNegative: false,
        through: Calendar.current.date(byAdding: .day, value: 9, to: .now) ?? .now,
        bills: [.init(name: "Rent", amount: "AED 6,500", due: Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now, overdue: false),
                .init(name: "Car loan", amount: "AED 1,850", due: Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now, overdue: false)],
        billsTotal: "AED 8,630", updated: .now)
}
