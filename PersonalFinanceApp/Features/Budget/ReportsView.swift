//
//  ReportsView.swift
//  Nokael Money
//
//  Where the money went: a month's income, spending and what was left,
//  six months side by side, and spending by category against last month
//  and the plan. Transfers and debt principal aren't spending.
//

import SwiftUI
import Charts
import NokaelCore

struct ReportsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var month: String?
    @State private var explanation: Explanation?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var currentMonth: String { month ?? snapshot.monthKey }

    // Archived categories still count for the months they were used
    private var expenseCategories: [AccountInfo] { snapshot.accountRecords.filter { $0.kind == .expense }.map(\.info) }
    private var incomeCategories: [AccountInfo] { snapshot.accountRecords.filter { $0.kind == .income }.map(\.info) }

    var body: some View {
        let report = Reports.month(currentMonth, ledger: snapshot.ledger, expenseCategories: expenseCategories,
                                   incomeCategories: incomeCategories, budget: snapshot.budget, calendar: snapshot.calendar)
        let trend = Reports.trend(endingAt: currentMonth, count: 6, ledger: snapshot.ledger, expenseCategories: expenseCategories,
                                  incomeCategories: incomeCategories, calendar: snapshot.calendar)
        List {
            Section { banner(report).bannerRow() }

            Section("Last 6 months") {
                trendChart(trend).frame(height: 190).padding(.vertical, 8)
            }

            Section {
                if report.spending.isEmpty {
                    Text("No spending recorded this month").foregroundStyle(.secondary)
                }
                let total = report.totals.spending
                ForEach(report.spending) { line in
                    CategoryReportRow(line: line, share: share(line.amount, of: total),
                                      color: Color(hex: snapshot.account(line.categoryId)?.colorHex ?? "#8E8E93"),
                                      symbol: snapshot.account(line.categoryId)?.icon ?? "tag.fill")
                }
            } header: {
                Text("Spending by category")
            } footer: {
                Text("Compared with \(title(BudgetMonth.adding(-1, to: currentMonth, calendar: snapshot.calendar))). Interest and fees on cards and loans count as spending; the part of a payment that lowers what you owe doesn't.")
            }

            if !report.income.isEmpty {
                Section("Income") {
                    ForEach(report.income) { line in
                        ListRow(title: line.name, caption: changeText(line, spending: false), symbol: "arrow.down.circle.fill", color: .green) {
                            Text(line.amount.compact).monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 14) {
                    Button { month = BudgetMonth.adding(-1, to: currentMonth, calendar: snapshot.calendar) } label: {
                        Image(systemName: "chevron.left")
                    }.accessibilityLabel("Previous month")
                    Text(title(currentMonth)).font(.headline)
                    Button { month = BudgetMonth.adding(1, to: currentMonth, calendar: snapshot.calendar) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next month")
                    .disabled(currentMonth >= snapshot.monthKey)
                }
            }
        }
        .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
    }

    private func banner(_ report: MonthReport) -> some View {
        let t = report.totals
        let diff = t.spending - report.previous.spending
        let caption: String = {
            guard report.previous.spending.isPositive else { return "Nothing spent the month before" }
            if diff.isZero { return "The same as last month" }
            return "\(diff.magnitude.compact) \(diff.isPositive ? "more" : "less") than last month"
        }()
        return SummaryBanner(title: "Spent in \(title(currentMonth))", amount: t.spending.formatted, caption: caption,
                             tint: Palette.budget, action: { explanation = explain(report) }) {
            BannerFigures(figures: [("Income", t.income.compact),
                                    ("Left over", t.leftOver.isNegative ? t.leftOver.signed : t.leftOver.compact),
                                    ("Kept", t.savingsRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")])
        }
    }

    private func trendChart(_ trend: [MonthTotals]) -> some View {
        Chart {
            ForEach(trend) { m in
                BarMark(x: .value("Month", shortTitle(m.month)), y: .value("Amount", m.income.decimal))
                    .foregroundStyle(by: .value("Type", "Income"))
                    .position(by: .value("Type", "Income"))
                BarMark(x: .value("Month", shortTitle(m.month)), y: .value("Amount", m.spending.decimal))
                    .foregroundStyle(by: .value("Type", "Spending"))
                    .position(by: .value("Type", "Spending"))
            }
        }
        .chartForegroundStyleScale(["Income": Color.green, "Spending": Palette.budget])
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityLabel("Income and spending for the last six months")
        .accessibilityValue(trend.map { "\(title($0.month)): income \($0.income.compact), spent \($0.spending.compact)" }.joined(separator: "; "))
    }

    private func explain(_ report: MonthReport) -> Explanation {
        let t = report.totals
        return Explanation(title: "Spent in \(title(currentMonth))", total: t.spending,
                           definition: "Everything recorded against spending categories this month, including interest and fees.",
                           sections: [("Income", report.income.map { BreakdownItem(label: $0.name, amount: $0.amount) }, "+"),
                                      ("Spending", report.spending.map { BreakdownItem(label: $0.name, amount: $0.amount) }, "−")],
                           notes: ["Left over: income \(t.income.compact) minus spending \(t.spending.compact) = \(t.leftOver.compact).",
                                   "Moving money between your own accounts, saving into goals and paying off what you owe aren't spending."])
    }

    private func share(_ amount: Money, of total: Money) -> Double {
        guard total.isPositive, amount.isPositive else { return 0 }
        return Double(amount.minorUnits) / Double(total.minorUnits)
    }

    private func title(_ key: String) -> String {
        (BudgetMonth.start(of: key, calendar: snapshot.calendar) ?? snapshot.today).formatted(.dateTime.month(.wide).year())
    }

    private func shortTitle(_ key: String) -> String {
        (BudgetMonth.start(of: key, calendar: snapshot.calendar) ?? snapshot.today).formatted(.dateTime.month(.abbreviated))
    }
}

struct CategoryReportRow: View {
    let line: CategoryTotal
    let share: Double
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListRow(title: line.name, caption: changeText(line, spending: true), symbol: symbol, color: color) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(line.amount.compact).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text("\(Int((share * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressBar(value: share, tint: color).padding(.leading, 46)
        }
        .accessibilityElement(children: .combine)
    }
}

/// e.g. "AED 300 less than last month · plan AED 1,500"
private func changeText(_ line: CategoryTotal, spending: Bool) -> String {
    var parts: [String] = []
    if line.previous.isZero {
        parts.append("None last month")
    } else if line.change.isZero {
        parts.append("Same as last month")
    } else {
        parts.append("\(line.change.magnitude.compact) \(line.change.isPositive ? "more" : "less") than last month")
    }
    if spending, let planned = line.planned {
        parts.append(line.amount > planned ? "over the \(planned.compact) plan" : "plan \(planned.compact)")
    }
    return parts.joined(separator: " · ")
}
