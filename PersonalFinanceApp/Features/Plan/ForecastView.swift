//
//  ForecastView.swift
//  Nokael Money
//
//  The calendar of money in and out: the balance of spendable accounts day
//  by day as bills are paid and income arrives, its lowest point, and a
//  warning before it would go below zero. A projection; nothing is posted.
//

import SwiftUI
import Charts
import NokaelCore

/// Pays a scheduled item with the right sheet: debts are split into interest and principal
struct PayScheduledSheet: View {
    @Environment(LedgerStore.self) private var store
    let occurrence: Occurrence

    var body: some View {
        let snapshot = store.snapshot
        if let debt = snapshot.item(for: occurrence)?.debtId.flatMap(snapshot.account) {
            PayDebtSheet(debt: debt, occurrence: occurrence)
        } else {
            PayOccurrenceSheet(occurrence: occurrence)
        }
    }
}

struct ForecastView: View {
    @Environment(LedgerStore.self) private var store
    @State private var days = 60
    @State private var paying: Occurrence?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        let forecast = snapshot.cashForecast(days: days)
        List {
            Section { banner(forecast).bannerRow() }

            Section {
                Picker("Period", selection: $days) {
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if !forecast.days.isEmpty { chart(forecast).frame(height: 180).padding(.vertical, 8) }
            }

            if forecast.days.isEmpty {
                Section {
                    EmptyStateView(symbol: "calendar", title: "Nothing scheduled",
                                   message: "Add bills and expected income in Plan to see your balance ahead.")
                }
            }

            ForEach(forecast.days) { day in
                Section {
                    ForEach(day.events) { event in
                        Button { paying = snapshot.occurrences.first { $0.id == event.occurrenceId } } label: {
                            ForecastEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Spacer()
                        Text("Then \(day.balance.compact)")
                            .foregroundStyle(day.balance.isNegative ? .red : .secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section {
            } footer: {
                Text(footnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Money ahead")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { GlobalAddButton() }
        .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
    }

    private func banner(_ forecast: CashForecast) -> some View {
        let short = forecast.firstShortfall
        let title = short == nil ? "Lowest point in \(days) days" : "Short of money"
        let caption: String = {
            if let short {
                return "Spendable accounts go below zero on \(short.formatted(.dateTime.day().month(.wide))). Move money in or reschedule a bill."
            }
            return forecast.days.isEmpty ? "No bills or income scheduled"
                : "on \(forecast.lowestDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
        }()
        return SummaryBanner(title: title, amount: forecast.lowest.formatted, caption: caption,
                             tint: short == nil ? Palette.plan : .red) {
            BannerFigures(figures: [("Now", forecast.start.compact),
                                    ("Coming in", forecast.moneyIn.compact),
                                    ("Going out", forecast.moneyOut.compact),
                                    ("At the end", forecast.end.compact)])
        }
    }

    /// Balance as a step line: flat between events, changing on each event day
    private func chart(_ forecast: CashForecast) -> some View {
        let end = snapshot.calendar.date(byAdding: .day, value: days, to: snapshot.calendar.startOfDay(for: snapshot.today)) ?? snapshot.today
        let points = [(snapshot.calendar.startOfDay(for: snapshot.today), forecast.start)]
            + forecast.days.map { ($0.date, $0.balance) }
            + [(end, forecast.end)]
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.0), y: .value("Balance", point.1.decimal))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.plan)
            }
            if forecast.lowest.isNegative {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(.red.opacity(0.6)).lineStyle(StrokeStyle(dash: [4, 3]))
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .accessibilityLabel("Projected balance chart")
        .accessibilityValue("Starts at \(forecast.start.compact), lowest \(forecast.lowest.compact), ends at \(forecast.end.compact)")
    }

    private var footnote: String {
        var lines = ["Starts from what your spendable accounts hold today, then applies each unpaid bill and expected income on its date. Nothing here is recorded until you mark it paid."]
        if !snapshot.reserves.isEmpty {
            lines.append("Money set aside is still in these balances.")
        }
        lines.append("Expected income is included here. Safe-to-spend doesn't count it until it arrives.")
        return lines.joined(separator: "\n\n")
    }
}

struct ForecastEventRow: View {
    let event: ForecastEvent

    var body: some View {
        ListRow(title: event.name, caption: caption,
                symbol: event.amount.isPositive ? "arrow.down.circle.fill" : "calendar",
                color: event.amount.isPositive ? .green : (event.isOverdue ? .red : Palette.plan)) {
            Text(event.amount.signed)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(event.amount.isPositive ? .green : .primary)
        }
    }

    private var caption: String {
        var parts: [String] = []
        if event.isOverdue { parts.append("Overdue since " + event.dueDate.formatted(.dateTime.day().month(.abbreviated))) }
        parts.append(event.amount.isPositive ? "Expected" : "Scheduled")
        if event.isEstimate { parts.append("estimate") }
        return parts.joined(separator: " · ")
    }
}
