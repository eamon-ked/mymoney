//
//  RedesignInsights.swift
//  Nokael Money
//
//  Intelligence and its chat, Reports, Money ahead and Help. Every figure
//  goes through Privacy Mode like the rest of the app.
//

import SwiftUI
import Charts
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Intelligence

extension Redesign {
    struct IntelligencePage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            VStack(spacing: 8) {
                IntelligenceMark(size: 64).padding(.bottom, 8)
                Text("A little more understanding.").rdText(.heading)
                Text("A clear summary of your recorded finances, with a useful next step.")
                    .rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR FINANCIAL PICTURE").rdText(.overline).foregroundStyle(Theme.muted)
                summary.rdText(.body).lineSpacing(5)
                if let month = MonthSoFar(app.snapshot).sentence, !app.hidesAmounts, !app.hidesDetails {
                    Text(month).rdText(.body).lineSpacing(5)
                }
                Button { app.open(.breakdown) } label: {
                    HStack(spacing: 5) { Text("See the calculation"); Image(systemName: "arrow.right") }
                        .rdText(.captionStrong).foregroundStyle(Theme.primary)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .padding(1)
            .background(Theme.intelligence.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if AppleIntelligence.isReady {
                // A few questions a month are free, so people see what it does before Plus
                let free = FreeAllowance.ask
                Button { app.open(app.isPlus || free.left > 0 ? .ask : .paywall(.appleIntelligence)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(Theme.primary)
                        Text("Ask anything about your money").rdText(.body).foregroundStyle(Theme.muted)
                        Spacer()
                        if !app.isPlus {
                            if free.left > 0 { Text("\(free.left) free").rdText(.caption).foregroundStyle(Theme.muted) } else { PlusTag() }
                        }
                    }
                    .padding(16)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .accessibilityIdentifier("askButton")
            }

            SectionHeading(title: "A useful next step").padding(.top, 24)
            nextStep

            if let card = app.cards.first {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Credit isn't cash", systemImage: "creditcard").rdText(.detailStrong)
                    Redesign.footnote("Your card has \(app.money(card.balance)) outstanding. Any credit still available to borrow is excluded from safe to spend.")
                    Button { app.open(.account(card.id)) } label: {
                        HStack(spacing: 3) { Text("View credit card"); Image(systemName: "chevron.right") }
                            .rdText(.captionStrong).foregroundStyle(Theme.primary)
                    }
                }
                .rdPanel()
                .padding(.top, 12)
            }

            Text(AppleIntelligence.isReady ? "Worked out from what you've recorded. The chat uses Apple Intelligence, privately."
                 : "Worked out from what you've recorded, on this iPhone.")
                .rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 24)
        }

        /// Every figure goes through Privacy Mode, so the summary never reads out what the rest of the app hides
        private var summary: Text {
            if !app.setupComplete { return Text("Add the bank account or cash you spend from, and this will show what you can safely spend.") }
            if app.shortfall > 0 {
                return Text("You have ") + app.amount(app.cash).fontWeight(.semibold) + Text(" in cash and ")
                    + app.amount(app.reserved).fontWeight(.semibold) + Text(" held back for what's coming up. There is ")
                    + app.amount(app.shortfall).fontWeight(.semibold) + Text(" still to cover.")
            }
            return Text("Your cash covers your recorded commitments, leaving ") + app.amount(app.safe).fontWeight(.semibold)
                + Text(" safe to spend.")
        }

        @ViewBuilder private var nextStep: some View {
            if let task = HomeTask.all(app.snapshot).first {
                TaskRow(task: task).padding(.horizontal, 14).rdPanel(padding: 0)
            } else {
                Button { app.go(.budget) } label: {
                    HStack(spacing: 12) {
                        IconBox(symbol: "leaf", small: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Keep your monthly plan in view").rdText(.detailStrong)
                            Text("See how your spending compares to your budget.").rdText(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .rdPanel()
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Ask about your money, answered by Apple Intelligence from a summary of the person's own records
    struct AskPage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligence.isReady { AskChat() } else { unavailable }
            #else
            unavailable
            #endif
        }

        private var unavailable: some View {
            EmptyNote(text: "Apple Intelligence isn't available on this iPhone, or it's switched off in Settings.")
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    struct AskChat: View {
        @Environment(AppModel.self) private var app
        @State private var model = AskModel()
        @State private var question = ""
        @State private var freeLeft = FreeAllowance.ask.left

        private let suggestions = [
            "How much can I spend this week?",
            "What did I spend most on this month?",
            "Which bills are due soon?",
            "How does this month compare with last month?",
            "Am I over budget anywhere?",
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if model.messages.isEmpty {
                    Text(AppleIntelligence.engine(plus: app.isPlus) == .cloud
                         ? "Answered by Apple's larger model on Private Cloud Compute, from your accounts, budget and bills. Apple uses your data only to answer and doesn't keep it."
                         : "Answers come from your accounts, budget and bills, worked out privately on this iPhone. Nothing is sent anywhere.")
                        .rdText(.body).foregroundStyle(Theme.muted)
                    ForEach(suggestions, id: \.self) { s in
                        Button { send(s) } label: {
                            Text(s).rdText(.body).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(Theme.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(model.messages) { message in
                    HStack {
                        if message.fromPerson { Spacer(minLength: 40) }
                        Group {
                            if message.text.isEmpty { ProgressView() }
                            // Answers can quote figures, so they're hidden with the rest in Privacy Mode
                            else if !message.fromPerson && app.hidesAmounts { Text("Answer hidden in Privacy Mode.") }
                            else { Text(LocalizedStringKey(message.text)).textSelection(.enabled) }
                        }
                        .rdText(.body)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(message.fromPerson ? Theme.onPrimary : Theme.foreground)
                        .background(message.fromPerson ? Theme.primary : message.failed ? Theme.amberFill : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if !message.fromPerson { Spacer(minLength: 40) }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Ask anything about your money", text: $question, axis: .vertical)
                        .lineLimit(1...4).rdText(.body).submitLabel(.send)
                        .onSubmit { send(question) }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.secondary.opacity(0.9), in: Capsule())
                    Button { send(question) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                        .accessibilityIdentifier("askSend")
                        .accessibilityLabel("Send")
                }
                .padding(.top, 8)
                if !app.isPlus {
                    Text(FreeAllowance.ask.leftText("question") + ". Nokael Plus has no limit.")
                        .rdText(.caption).foregroundStyle(Theme.muted).id(freeLeft)
                }
                if !model.messages.isEmpty {
                    Button("New conversation") { model.reset() }.rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .onAppear {
                #if DEBUG
                if let q = UserDefaults.standard.string(forKey: "ask"), model.messages.isEmpty { send(q) }
                #endif
            }
        }

        private func send(_ text: String) {
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if !app.isPlus {
                guard FreeAllowance.ask.left > 0 else { app.open(.paywall(.appleIntelligence)); return }
                FreeAllowance.ask.spend()
                freeLeft = FreeAllowance.ask.left
            }
            model.ask(text, digest: FinanceDigest(app.snapshot), plus: app.isPlus)
            question = ""
        }
    }

    @available(iOS 26.0, *)
    struct MonthStory: View {
        @Environment(AppModel.self) private var app
        let monthKey: String
        @State private var text = ""
        @State private var loading = false
        @State private var error: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { IntelligenceMark(size: 22); Text("What happened this month").rdText(.detailStrong) }
                if app.hidesAmounts && !text.isEmpty {
                    Text("Hidden in Privacy Mode.").rdText(.body).foregroundStyle(Theme.muted)
                } else if !text.isEmpty {
                    Text(text).rdText(.body)
                } else if let error {
                    Text(error).rdText(.body).foregroundStyle(Theme.muted)
                }
                if !loading {
                    Button(text.isEmpty ? "Explain this month" : "Explain again") { Task { await explain() } }
                        .rdText(.label).foregroundStyle(Theme.primary)
                } else if text.isEmpty {
                    ProgressView()
                }
            }
            .rdPanel()
            .onChange(of: monthKey) { text = ""; error = nil }
        }

        private func explain() async {
            loading = true
            error = nil
            text = ""
            defer { loading = false }
            let digest = FinanceDigest(app.snapshot)
            let engine = AppleIntelligence.engine(plus: app.isPlus)
            do {
                for try await partial in MoneyAI.monthStory(digest, monthKey: monthKey, engine: engine) { text = partial.content }
            } catch where engine == .cloud && !(error is CancellationError) {
                do {
                    for try await partial in MoneyAI.monthStory(digest, monthKey: monthKey, engine: .onDevice) { text = partial.content }
                } catch { self.error = AppleIntelligence.message(for: error) }
            } catch {
                self.error = AppleIntelligence.message(for: error)
            }
        }
    }
    #endif
}

// MARK: - Reports

extension Redesign {
    struct ReportsPage: View {
        @Environment(AppModel.self) private var app
        @State private var month: String?
        @State private var showAll = false

        var body: some View {
            let s = app.snapshot
            let key = month ?? s.monthKey
            let expense = s.accountRecords.filter { $0.kind == .expense }.map(\.info)
            let income = s.accountRecords.filter { $0.kind == .income }.map(\.info)
            let report = Reports.month(key, ledger: s.ledger, expenseCategories: expense, incomeCategories: income,
                                       budget: s.budget, calendar: s.calendar, loanCategories: s.loanCategories)
            let total = report.totals.spending

            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text((BudgetMonth.start(of: key, calendar: s.calendar) ?? s.today).formatted(.dateTime.month(.wide).year())).rdText(.section)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
                    .disabled(key >= s.monthKey)
            }
            .foregroundStyle(Theme.primary)
            .rdPanel(padding: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Spent").rdText(.detail).foregroundStyle(Theme.muted)
                app.amount(total.decimal).rdText(.balance)
                let left = report.totals.leftOver
                Text(private: report.totals.income.isPositive
                     ? (left.isNegative ? "\(app.money(left.magnitude)) more than came in" : "You kept \(app.money(left)) of \(app.money(report.totals.income))")
                     : "No income recorded this month")
                    .rdText(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 24).padding(.horizontal, 4)

            if report.totals.income.isPositive {
                VStack(spacing: 10) {
                    bar("Money in", report.totals.income, max: max(report.totals.income, total))
                    bar("Money out", total, max: max(report.totals.income, total))
                }
                .rdPanel()
            }

            SectionHeading(title: "Where it went", action: report.spending.count > 5 || !report.income.isEmpty ? (showAll ? "Show fewer" : "See all") : nil) {
                withAnimation(.snappy) { showAll.toggle() }
            }
            .padding(.top, 24)
            if report.spending.isEmpty { EmptyNote(text: "No spending recorded this month.") }
            VStack(spacing: 0) {
                let lines = showAll ? report.spending : Array(report.spending.prefix(5))
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                    row(line, total: total)
                    if i < lines.count - 1 { Redesign.hairline }
                }
            }
            if showAll && !report.income.isEmpty {
                SectionHeading(title: "Money in").padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(report.income.enumerated()), id: \.element.id) { i, line in
                        row(line, total: report.totals.income)
                        if i < report.income.count - 1 { Redesign.hairline }
                    }
                }
            }

            #if canImport(FoundationModels)
            if app.isPlus, #available(iOS 26.0, *), AppleIntelligence.isReady { MonthStory(monthKey: key).padding(.top, 24) }
            #endif
            // Free shows enough months to see a trend; Plus shows six and every month before
            let months = app.isPlus ? 6 : FreePlan.reportMonths
            SectionHeading(title: "Last \(months) months").padding(.top, 24)
            let trend = Reports.trend(endingAt: key, count: months, ledger: s.ledger, expenseCategories: expense,
                                      incomeCategories: income, calendar: s.calendar, loanCategories: s.loanCategories)
            Group {
                if app.hidesCharts || app.hidesAmounts { ChartHidden(height: 190) } else { trendChart(trend) }
            }
            .rdPanel(padding: 14)
            if !app.isPlus {
                LinkRow(symbol: "chart.bar.xaxis", title: "Every month and longer trends", detail: "Six months side by side, and any month before",
                        badge: "PLUS") { app.open(.paywall(.reports)) }
                    .rdPanel(padding: 0)
                    .padding(.top, 12)
                    .accessibilityIdentifier("reportsPlus")
            }
        }

        /// This month and the two before are free; earlier months are Plus
        private func step(_ by: Int) {
            let s = app.snapshot
            let target = BudgetMonth.adding(by, to: month ?? s.monthKey, calendar: app.calendar)
            let oldestFree = BudgetMonth.adding(-(FreePlan.reportMonths - 1), to: s.monthKey, calendar: app.calendar)
            guard app.isPlus || target >= oldestFree else { app.open(.paywall(.reports)); return }
            month = target
        }

        private func bar(_ label: String, _ value: Money, max: Money) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(label).rdText(.caption).foregroundStyle(Theme.muted); Spacer(); app.amount(value.decimal).rdText(.amount) }
                ProgressBar(value: max.isPositive ? Double(value.minorUnits) / Double(max.minorUnits) : 0)
            }
        }

        private func row(_ line: CategoryTotal, total: Money) -> some View {
            let share = total.isPositive ? Double(line.amount.minorUnits) / Double(total.minorUnits) : 0
            let look = app.record(line.categoryId).map(AppModel.look) ?? ("tag", IconBox.Tone.green)
            return Button { if app.category(line.categoryId) != nil { app.open(.category(line.categoryId)) } } label: {
                HStack(spacing: 12) {
                    IconBox(look, small: true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(app.hidesDetails ? "Category" : line.name).rdText(.detailStrong)
                            Spacer()
                            app.amount(line.amount.decimal).rdText(.amount)
                        }
                        ProgressBar(value: share)
                        Text(private: caption(line, share: share)).rdText(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private func caption(_ line: CategoryTotal, share: Double) -> String {
            var parts = ["\(app.percent(share)) of the total"]
            if let plan = line.planned, plan.isPositive {
                parts.append(line.amount > plan ? "\(app.money(line.amount - plan)) over plan" : "\(app.money(plan - line.amount)) under plan")
            } else if line.previous.isPositive {
                let change = line.change
                parts.append(change.isZero ? "same as last month" : change.isNegative ? "\(app.money(change.magnitude)) less than last month"
                             : "\(app.money(change)) more than last month")
            }
            return parts.joined(separator: " · ")
        }

        private func trendChart(_ months: [MonthTotals]) -> some View {
            Chart {
                ForEach(months) { m in
                    let label = (BudgetMonth.start(of: m.month, calendar: app.calendar) ?? app.today).formatted(.dateTime.month(.abbreviated))
                    BarMark(x: .value("Month", label), y: .value("Amount", (m.income.decimal as NSDecimalNumber).doubleValue))
                        .position(by: .value("Kind", "In"))
                        .foregroundStyle(Theme.primary)
                    BarMark(x: .value("Month", label), y: .value("Amount", (m.spending.decimal as NSDecimalNumber).doubleValue))
                        .position(by: .value("Kind", "Out"))
                        .foregroundStyle(Theme.warm)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption).foregroundStyle(Theme.muted) } }
            .frame(height: 190)
            .accessibilityLabel("Money in and out over the last 6 months")
        }
    }
}

// MARK: - Money ahead

extension Redesign {
    struct ForecastPage: View {
        @Environment(AppModel.self) private var app
        @State private var days = "30 days"

        var body: some View {
            let length = ["30 days": 30, "60 days": 60, "90 days": 90][days] ?? 30
            let f = app.snapshot.cashForecast(days: length)
            Pills(options: ["30 days", "60 days", "90 days"], selection: $days)
            VStack(alignment: .leading, spacing: 6) {
                if let short = f.firstShortfall {
                    Text("Short of money on \(app.fullDay(short))").rdText(.detailStrong).foregroundStyle(Theme.destructive)
                } else {
                    Text("Lowest point in \(length) days").rdText(.detail).foregroundStyle(Theme.muted)
                }
                app.amount(f.lowest.decimal).rdText(.balance)
                Text("on \(app.fullDay(f.lowestDate))").rdText(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 24).padding(.horizontal, 4)
            DetailCard {
                DetailRow(label: "Now", value: app.money(f.start))
                DetailRow(label: "Coming in", value: app.money(f.moneyIn))
                DetailRow(label: "Going out", value: app.money(f.moneyOut))
                DetailRow(label: "At the end", value: app.money(f.end))
            }
            Group {
                if app.hidesCharts || app.hidesAmounts { ChartHidden(height: 180) } else { chart(f) }
            }
            .rdPanel(padding: 14)
            .padding(.top, 16)

            ForEach(f.days.filter { !$0.events.isEmpty }) { day in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).rdText(.detailStrong)
                        Spacer()
                        Text(private: "Then \(app.money(day.balance))").rdText(.caption).foregroundStyle(day.balance.isNegative ? Theme.destructive : Theme.muted)
                    }
                    .padding(.top, 20).padding(.bottom, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(day.events.enumerated()), id: \.element.id) { i, e in
                            Button { app.open(.bill(e.occurrenceId)) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.hidesDetails ? (e.amount.isPositive ? "Income" : "Bill") : e.name).rdText(.cardTitle)
                                        Text(e.isOverdue ? "Overdue since \(app.day(e.dueDate))" : e.amount.isPositive ? "Expected" : "Scheduled"
                                             + (e.isEstimate ? " · estimate" : ""))
                                            .rdText(.caption).foregroundStyle(e.isOverdue ? Theme.destructive : Theme.muted)
                                    }
                                    Spacer()
                                    Text(private: (e.amount.isPositive ? "+ " : "− ") + app.money(e.amount.magnitude))
                                        .rdText(.amount).foregroundStyle(e.amount.isPositive ? Theme.primary : Theme.foreground)
                                }
                                .padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < day.events.count - 1 { Redesign.hairline }
                        }
                    }
                    .rdPanel(padding: 14)
                }
            }
            Redesign.footnote("From your spendable accounts, with expected income and bills on their dates. Day-to-day spending isn't included.")
                .padding(.top, 20)
        }

        private func chart(_ f: CashForecast) -> some View {
            Chart {
                ForEach(f.days) { day in
                    LineMark(x: .value("Day", day.date), y: .value("Balance", (day.balance.decimal as NSDecimalNumber).doubleValue))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Theme.primary)
                }
                if f.lowest.isNegative { RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.destructive.opacity(0.5)) }
            }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption).foregroundStyle(Theme.muted) } }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(Theme.muted) } }
            .frame(height: 180)
            .accessibilityLabel("Balance over the coming days")
        }
    }
}

// MARK: - Help

extension Redesign {
    struct HelpPage: View {
        @Environment(AppModel.self) private var app
        @State private var question = ""
        @State private var asked = ""
        @State private var answer: String?
        @State private var thinking = false
        @State private var draft: DraftEntry?
        @State private var paydaySaid: Money??
        @State private var expanded: String?

        private var matches: [GuideTopic] { asked.isEmpty ? [] : AppGuide.match(asked) }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "questionmark.circle").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48).background(Theme.primary.opacity(0.1), in: Circle()).padding(.bottom, 8)
                Text("A little help, right here.").rdText(.heading)
                Text("Ask a question, or just say what happened.").rdText(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 20)

            HStack(spacing: 8) {
                TextField("e.g. I got my salary, or how do I import", text: $question, axis: .vertical)
                    .lineLimit(1...3).rdText(.body).submitLabel(.go)
                    .onSubmit(ask)
                Button(action: ask) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Ask")
            }
            .padding(.horizontal, 16).frame(minHeight: 50)
            .background(Theme.secondary.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                if let said = paydaySaid { paydayCard(said) }
                if let draft { draftCard(draft) }
                if thinking || answer != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { IntelligenceMark(size: 22); Text("Answer").rdText(.detailStrong) }
                        if let answer { Text(answer).rdText(.body) } else { HStack { ProgressView(); Text("Thinking…").rdText(.caption) } }
                    }
                    .rdPanel()
                }
                if !asked.isEmpty && matches.isEmpty && answer == nil && !thinking && draft == nil && paydaySaid == nil {
                    Redesign.footnote("I couldn't find that. Try different words, or pick a topic below.")
                }
                ForEach(paydaySaid == nil ? Array(matches.prefix(2)) : []) { topic in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(topic.title, systemImage: topic.symbol).rdText(.detailStrong)
                        topicBody(topic)
                    }
                    .rdPanel()
                }
            }
            .padding(.top, 16)

            Redesign.overline(asked.isEmpty ? "How do I…" : "Other topics").padding(.top, 24)
            VStack(spacing: 0) {
                let rest = AppGuide.topics.filter { t in !matches.prefix(2).contains(t) }
                ForEach(Array(rest.enumerated()), id: \.element.id) { i, topic in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { withAnimation(.snappy) { expanded = expanded == topic.id ? nil : topic.id } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: topic.symbol).foregroundStyle(Theme.primary).frame(width: 22)
                                Text(topic.title).rdText(.detailStrong).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "plus").font(.caption).foregroundStyle(Theme.muted).rotationEffect(.degrees(expanded == topic.id ? 45 : 0))
                            }
                            .frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if expanded == topic.id { topicBody(topic).padding(.bottom, 14) }
                    }
                    if i < rest.count - 1 { Redesign.hairline }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border.opacity(0.6)))

            Redesign.overline("Questions people ask").padding(.top, 24)
            VStack(spacing: 0) {
                ForEach(Array(faqs.enumerated()), id: \.offset) { i, faq in
                    FAQ(question: faq.0, answer: faq.1)
                    if i < faqs.count - 1 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border.opacity(0.6)))

            Button { app.open(.breakdown) } label: { HStack { Text("Understand My Safe to Spend"); Image(systemName: "arrow.right") } }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 24)
            Button { app.show(.activity) } label: { Label("Find a transaction", systemImage: "magnifyingglass") }
                .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44).padding(.top, 8)
                .onAppear {
                    #if DEBUG
                    if let q = UserDefaults.standard.string(forKey: "ask"), asked.isEmpty, UserDefaults.standard.string(forKey: "screen") == "guide" {
                        question = q
                        ask()
                    }
                    #endif
                }
        }

        @ViewBuilder private func topicBody(_ topic: GuideTopic) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").rdText(.captionStrong).frame(width: 22, height: 22)
                            .foregroundStyle(Theme.primary).background(Theme.primary.opacity(0.1), in: Circle())
                        Text(step).rdText(.detail).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let tip = topic.tip {
                    Label(tip, systemImage: "lightbulb").rdText(.caption).foregroundStyle(Theme.muted)
                }
                if let action = topic.action, let title = topic.actionTitle {
                    Button { run(action) } label: {
                        HStack { Text(title); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }

        private func run(_ action: GuideAction) {
            switch action {
            case .add(let kind):
                app.open(.entry(kind == .income ? .income : kind == .transfer ? .transfer : kind == .adjustment ? .adjustment : .expense))
            case .importStatement: app.open(.importStatement(nil))
            case .capture: app.show(.capture)
            case .tab(let tab):
                switch tab {
                case .home: app.go(.home)
                case .budget: app.go(.budget)
                case .accounts: app.go(.accounts)
                case .activity: app.show(.activity)
                case .reports: app.show(.reports)
                }
            case .bills: app.go(.bills)
            case .backup: app.show(.data)
            case .payDebt: app.open(.whatHappened)
            case .addLoan: app.open(.newAccount(loan: true))
            }
        }

        private func paydayCard(_ said: Money?) -> some View {
            let plan = PaydayPlan.make(app.snapshot, said: said)
            return Button {
                app.paydaySaid = said
                app.open(.payday)
            } label: {
                HStack(spacing: 12) {
                    IconBox(symbol: "arrow.down.left", small: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(private: plan.alreadyReceived != nil && said == nil ? "Salary already recorded this month"
                             : "Record \(app.money(plan.amount)) salary into \(app.accountLabel(plan.accountId))").rdText(.cardTitle)
                        Text(plan.item == nil ? "Then plan the month" : "From your plan, then budget and goals for the month")
                            .rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .rdPanel()
            }
            .buttonStyle(.plain)
        }

        private func draftCard(_ entry: DraftEntry) -> some View {
            let amount = entry.amount.map { app.money($0) } ?? ""
            let what = [entry.memo, entry.category ?? ""].first { !$0.isEmpty } ?? entry.kind.title
            return Button {
                app.draft = entry
                app.open(.entry(entry.kind == .income ? .income : .expense))
            } label: {
                HStack(spacing: 12) {
                    IconBox(symbol: entry.kind == .income ? "arrow.down.left" : "basket", tone: entry.kind == .income ? .green : .warm, small: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(private: "Add \(entry.kind.title.lowercased()): \(amount)").rdText(.cardTitle)
                        Text(app.hidesDetails ? "Opens the form filled in" : what).rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .rdPanel()
            }
            .buttonStyle(.plain)
        }

        private func ask() {
            let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            asked = text
            answer = nil
            draft = nil
            paydaySaid = nil
            let s = app.snapshot
            // "I got my salary 20,000" is something to add, not only a question
            let top = AppGuide.match(text).first?.id ?? ""
            if PaydayPlan.mentionsSalary(text) {
                paydaySaid = .some(AlertParser.spoken(text, homeCurrency: app.currency, date: Date())?.amount)
            } else if !["loan", "transfer", "balance"].contains(top),
                      let spoken = AlertParser.spoken(text, homeCurrency: app.currency, date: Date()) {
                var entry = DraftEntry()
                let lower = text.lowercased()
                let incoming = spoken.direction == .received || lower.contains("paid me")
                entry.kind = incoming ? .income : .expense
                entry.amount = spoken.amount.decimal
                let categories = incoming ? s.incomeCategories : s.expenseCategories
                if lower.contains("salary") { entry.category = categories.first { $0.name.lowercased().contains("salary") }?.name }
                entry.memo = spoken.merchant.isEmpty ? (entry.category ?? "") : spoken.merchant
                draft = entry
            }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligence.isReady, paydaySaid == nil {
                thinking = true
                Task {
                    defer { thinking = false }
                    let session = LanguageModelSession(instructions: """
                        You are the help guide inside Nokael Money, a budgeting app. Answer how-to questions in at most four short numbered steps, \
                        using only the instructions below and the exact button names in them. If the person describes money they received or spent, \
                        tell them how to add it. If the instructions don't cover it, say so briefly. No financial advice.

                        \(AppGuide.reference)
                        """)
                    if let reply = try? await session.respond(to: text, options: GenerationOptions(sampling: .greedy)) {
                        answer = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            #endif
        }

        private var faqs: [(String, String)] {
            [
                ("How is Safe to Spend calculated?",
                 "Your spendable cash (\(app.money(app.cash))) minus what's held back for unpaid bills, money set aside and your buffer (\(app.money(app.reserved))), with a minimum of zero. Loans and credit limits are never counted as cash. Your monthly budget isn't subtracted a second time."),
                ("How does my credit card affect my cash?",
                 "The outstanding card balance is money you owe, shown separately from cash. Available credit is borrowing capacity, not safe to spend. Paying the card reduces both cash and what you owe; it isn't counted as new spending."),
                ("I've already paid a bill. What should I do?",
                 "Open the bill and choose Link Existing Payment if the payment is already in Activity. If it isn't, choose Record Payment. Paid bills are removed from unpaid commitments."),
                ("Can I correct a mistake?",
                 "Use Undo in the confirmation right after saving. You can also open any transaction in Activity and edit or delete it. To fix a balance, tap +, then More…, then A balance is wrong."),
                ("Will this move real money?",
                 "No. Nokael records what you've already done. No bank is connected, and no payments or transfers are sent."),
            ]
        }

        private struct FAQ: View {
            let question: String
            let answer: String
            @State private var open = false

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(.snappy) { open.toggle() } } label: {
                        HStack(spacing: 12) {
                            Text(question).rdText(.detailStrong).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "plus").font(.caption).foregroundStyle(Theme.muted).rotationEffect(.degrees(open ? 45 : 0))
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open { Redesign.footnote(answer).padding(.bottom, 16) }
                }
            }
        }
    }
}
