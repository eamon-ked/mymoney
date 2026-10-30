//
//  ReportsView.swift
//  Nokael Money
//
//  How did I do? This month's spending as one number, money in against money
//  out as a picture, then the few categories it mostly went to. The last six
//  months, comparisons and other months are Plus. Transfers aren't spending;
//  loan payments count in full, card payments don't (their purchases already did).
//

import SwiftUI
import Charts
import NokaelCore

struct ReportsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @State private var month: String?
    @State private var explanation: Explanation?
    @State private var paywall: PlusFeature?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var currentMonth: String { month ?? snapshot.monthKey }

    // Archived categories still count for the months they were used
    private var expenseCategories: [AccountInfo] { snapshot.accountRecords.filter { $0.kind == .expense }.map(\.info) }
    private var incomeCategories: [AccountInfo] { snapshot.accountRecords.filter { $0.kind == .income }.map(\.info) }

    var body: some View {
        NavigationStack {
            let report = Reports.month(currentMonth, ledger: snapshot.ledger, expenseCategories: expenseCategories,
                                       incomeCategories: incomeCategories, budget: snapshot.budget, calendar: snapshot.calendar,
                                       loanCategories: snapshot.loanCategories)
            List {
                Section {
                    banner(report).bannerRow()
                }

                // With nothing in, the banner already says so; an empty bar adds nothing
                if report.totals.income.isPositive {
                    Section {
                        InOutBars(income: report.totals.income, spending: report.totals.spending)
                            .padding(.vertical, 6)
                    }
                }

                Section {
                    if report.spending.isEmpty {
                        Text("No spending recorded this month").foregroundStyle(.secondary)
                    }
                    let total = report.totals.spending
                    ForEach(report.spending.prefix(5)) { line in
                        row(line, total: total)
                    }
                    if report.spending.count > 5 || !report.income.isEmpty {
                        NavigationLink("See all") { allLines(report) }
                    }
                } header: {
                    Text("Where it went")
                }

                if plus.isPlus {
                    storySection
                    Section("Last 6 months") {
                        trendChart(Reports.trend(endingAt: currentMonth, count: 6, ledger: snapshot.ledger,
                                                 expenseCategories: expenseCategories, incomeCategories: incomeCategories,
                                                 calendar: snapshot.calendar, loanCategories: snapshot.loanCategories))
                            .frame(height: 190).padding(.vertical, 8)
                    }
                } else {
                    Section {
                        Button { paywall = .reports } label: {
                            ListRow(title: "Your last 6 months", caption: "Trends, other months and how this one compares",
                                    symbol: "chart.bar.xaxis", color: Palette.brand) { PlusBadge() }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reportsPlus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .canvas()
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        Button { other(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous month")
                        Text(title(currentMonth)).font(.headline)
                        Button { other(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("Next month")
                            .disabled(currentMonth >= snapshot.monthKey)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }
                GlobalAddButton()
            }
            .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
            .paywall($paywall)
        }
    }

    /// Other months are Plus; this month is free
    private func other(_ step: Int) {
        guard plus.isPlus else { paywall = .reports; return }
        month = BudgetMonth.adding(step, to: currentMonth, calendar: snapshot.calendar)
    }

    private func row(_ line: CategoryTotal, total: Money) -> some View {
        CategoryReportRow(line: line, share: share(line.amount, of: total),
                          color: Color(hex: snapshot.account(line.categoryId)?.colorHex ?? "#8E8E93"),
                          symbol: snapshot.account(line.categoryId)?.icon ?? "tag.fill",
                          compare: plus.isPlus)
    }

    /// Every category and every income line, for the month on screen
    private func allLines(_ report: MonthReport) -> some View {
        List {
            Section("Spending") {
                ForEach(report.spending) { row($0, total: report.totals.spending) }
            }
            if !report.income.isEmpty {
                Section("Income") {
                    ForEach(report.income) { line in
                        ListRow(title: line.name, caption: plus.isPlus ? changeText(line, spending: false) : nil,
                                symbol: "arrow.down.circle.fill", color: .green) {
                            Text(line.amount.compact).monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .canvas()
        .navigationTitle(title(currentMonth))
    }

    @ViewBuilder private var storySection: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady {
            Section { MonthStoryView(monthKey: currentMonth) }
        }
        #endif
    }

    private func banner(_ report: MonthReport) -> some View {
        let t = report.totals
        let caption: String = {
            guard t.income.isPositive else { return "No income recorded this month" }
            return t.leftOver.isNegative
                ? "\(t.leftOver.magnitude.compact) more than came in"
                : "You kept \(t.leftOver.compact) of \(t.income.compact) that came in"
        }()
        // The month is in the switcher right above
        return SummaryBanner(title: "Spent", amount: t.spending.whole, caption: caption,
                             tint: Palette.brand, action: { explanation = explain(report) })
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
        .chartForegroundStyleScale(["Income": Color.green, "Spending": Palette.brand])
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityLabel("Income and spending for the last six months")
        .accessibilityValue(trend.map { "\(title($0.month)): income \($0.income.compact), spent \($0.spending.compact)" }.joined(separator: "; "))
    }

    private func explain(_ report: MonthReport) -> Explanation {
        let t = report.totals
        return Explanation(title: "Spent in \(title(currentMonth))", total: t.spending,
                           definition: "Everything recorded against spending categories this month, loan payments in full.",
                           sections: [("Income", report.income.map { BreakdownItem(label: $0.name, amount: $0.amount) }, "+"),
                                      ("Spending", report.spending.map { BreakdownItem(label: $0.name, amount: $0.amount) }, "−")],
                           notes: ["Left over: income \(t.income.compact) minus spending \(t.spending.compact) = \(t.leftOver.compact).",
                                   "Loan payments count in full; credit card payments don't, because the purchases already counted.",
                                   "Moving money between your own accounts and saving into goals aren't spending."])
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
    /// Against last month and the plan: Plus
    var compare = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListRow(title: line.name, caption: compare ? changeText(line, spending: true) : nil, symbol: symbol, color: color) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(line.amount.compact).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text("\(Int((share * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressBar(value: share, tint: color).padding(.leading, 52)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One fact under each row: the plan for spending, else the change since last month
private func changeText(_ line: CategoryTotal, spending: Bool) -> String? {
    if spending, let planned = line.planned {
        return line.amount > planned ? "Over the \(planned.compact) plan" : "Plan \(planned.compact)"
    }
    if line.previous.isZero { return nil }
    if line.change.isZero { return "Same as last month" }
    return "\(line.change.magnitude.compact) \(line.change.isPositive ? "more" : "less") than last month"
}

/// Money in against money out, as two bars a glance can compare
struct InOutBars: View {
    let income: Money
    let spending: Money

    var body: some View {
        let top = max(income.minorUnits, spending.minorUnits, 1)
        VStack(alignment: .leading, spacing: 14) {
            bar("Money in", income, Double(income.minorUnits) / Double(top), .green)
            bar("Money out", spending, Double(spending.minorUnits) / Double(top), Palette.brand)
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(_ label: String, _ amount: Money, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(amount.compact).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule().fill(color).frame(width: max(geo.size.width * value, value > 0 ? 8 : 0))
                }
            }
            .frame(height: 12)
        }
    }
}
