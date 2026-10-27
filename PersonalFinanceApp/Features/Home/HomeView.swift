//
//  HomeView.swift
//  Nokael Money
//
//  Where you stand in seconds: safe to spend, cash and debt, what's coming up,
//  how the budget is doing, and anything that needs attention.
//

import SwiftUI
import AppIntents
import NokaelCore

struct HomeView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @Environment(\.selectTab) private var selectTab
    @Environment(\.addEntry) private var addEntry
    @State private var showingSafeToSpend = false
    @State private var showingSettings = false
    @State private var explanation: Explanation?
    @State private var paying: Occurrence?
    @State private var showingAsk = false
    @State private var paywall: PlusFeature?
    @State private var reviewing: EntryRecord?
    @State private var showingHelp = false
    @State private var showingPayday = false
    @State private var fundingGoal: Reserve?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var suggestions: [BillSuggestion] { snapshot.billSuggestions }

    var body: some View {
        NavigationStack {
            List {
                // What I can spend, what I have and owe, what needs me, how the month is going
                Section { safeToSpendBanner.bannerRow() }

                Section {
                    HStack(spacing: 12) {
                        FigureCard(title: "Cash & bank", value: snapshot.cashAndBank.compact,
                                   detail: cashAccountCount,
                                   tint: Palette.accounts) { explanation = cashExplanation }
                        FigureCard(title: "Total debt", value: snapshot.totalDebt.compact,
                                   detail: "owed on \(snapshot.debtAccounts.filter { !snapshot.balance($0.id).isZero }.count) cards & loans",
                                   tint: snapshot.totalDebt.isPositive ? .red : .gray) { explanation = debtExplanation }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                ForEach(suggestions) { BillLinkCard(suggestion: $0, snapshot: snapshot) }

                alertsSection

                ReviewSection(selected: $reviewing)

                if snapshot.setupComplete { PaydayBanner { showingPayday = true } }

                budgetHealthSection
                comingUpSection
                reservesSection

                insightSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Your money")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    if !Self.screenshotMode { HelpButton() }
                }
                if AppleIntelligence.isReady {
                    ToolbarItem(placement: .primaryAction) {
                        Button { if plus.isPlus { showingAsk = true } else { paywall = .appleIntelligence } } label: {
                            Image(systemName: "sparkles")
                        }
                            .accessibilityLabel("Ask about your money")
                    }
                }
                GlobalAddButton()
            }
            .sheet(isPresented: $showingSafeToSpend) { SafeToSpendView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
            .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
            .sheet(item: $reviewing) { EntryDetailView(record: $0) }
            .sheet(isPresented: $showingHelp) { GuideView() }
            .sheet(isPresented: $showingPayday) { PaydaySheet() }
            .sheet(item: $fundingGoal) { GoalMoneySheet(goal: $0, adding: true) }
            .paywall($paywall)
            .sheet(isPresented: $showingAsk) {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *) { AskMoneyView() }
                #endif
            }
        }
    }

    // MARK: - Apple Intelligence

    /// DEBUG -screenshots: store screenshots leave out the live summary, which the simulator can't run
    private static var screenshotMode: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-screenshots")
        #else
        false
        #endif
    }

    @ViewBuilder private var insightSection: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady, snapshot.setupComplete, !Self.screenshotMode {
            if plus.isPlus {
                Section { InsightCard { showingAsk = true } }
            } else {
                Section {
                    Button { paywall = .appleIntelligence } label: {
                        HStack {
                            AIBadge(text: "Your month in brief")
                            Spacer()
                            PlusBadge()
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("A short summary of your month and answers to your questions, worked out on this iPhone.")
                }
            }
        }
        #endif
    }

    // MARK: - Safe to spend

    private var safeToSpendBanner: some View {
        let result = snapshot.safeToSpend()
        let through = result.periodEnd.formatted(.dateTime.day().month(.abbreviated))
        let amount: String
        let caption: String
        var alert: String?
        let tint: Color
        if let value = result.amount, snapshot.setupComplete {
            // Never less than zero, but a shortfall is said out loud, not hidden behind the zero
            amount = value.isNegative ? Money.zero(store.currency).compact : value.compact
            if value.isNegative { alert = "Short by \(value.magnitude.formatted)" }
            caption = value.isNegative
                ? "Bills and your buffer through \(through) need more than the money in your spending accounts"
                : "For flexible spending through \(through), after bills and money set aside"
            tint = value.isNegative ? .orange : Palette.home
        } else {
            amount = "—"
            caption = "Finish setup to calculate. Add an account with its balance."
            tint = .gray
        }
        return SummaryBanner(title: "Safe to spend", amount: amount, caption: caption, alert: alert, tint: tint,
                             action: { showingSafeToSpend = true }) {
            if result.amount != nil, snapshot.setupComplete {
                StatusLine(result: result)
                BannerFigures(figures: [("In spending accounts", result.spendableTotal.compact),
                                        ("Held back", (result.obligationsTotal + result.reservesTotal + result.categoryReservationsTotal + result.buffer).compact)])
                if let asOf = balancesAsOf { Text(asOf).font(.footnote).opacity(0.9) }
            }
        }
        .accessibilityIdentifier("safeToSpend")
    }

    /// When the spending accounts were last brought up to date
    private var balancesAsOf: String? {
        let dates = snapshot.accounts.filter(\.spendable).compactMap { snapshot.lastConfirmed[$0.id] }
        guard let newest = dates.max() else { return nil }
        if snapshot.calendar.isDate(newest, inSameDayAs: snapshot.today) { return "Balances as of today" }
        return "Balances as of \(newest.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: - Alerts

    @ViewBuilder private var alertsSection: some View {
        let suggested = Set(suggestions.map(\.occurrence.id))
        let bills = snapshot.upcomingBills(days: 1).filter { !suggested.contains($0.id) }
        let overdue = bills.filter { snapshot.state(of: $0) == .overdue }
        let dueToday = bills.filter { [.dueToday, .partiallyPaid].contains(snapshot.state(of: $0)) }
        let stale = snapshot.accounts.filter { a in
            guard a.kind.defaultSpendable || a.spendable else { return false }
            guard let d = snapshot.lastConfirmed[a.id] else { return true }
            return (snapshot.calendar.dateComponents([.day], from: d, to: snapshot.today).day ?? 0) > snapshot.settings.staleAfterDays
        }
        let overspent = snapshot.expenseCategories.filter { snapshot.budget.line($0.id, month: snapshot.monthKey).isOverspent }
        let unplanned = snapshot.setupComplete && !snapshot.expenseCategories.isEmpty
            ? snapshot.budget.availableToAllocate(month: snapshot.monthKey) : .zero(store.currency)
        let backupDue = needsBackup
        if !overdue.isEmpty || !dueToday.isEmpty || !stale.isEmpty || !overspent.isEmpty || !unplanned.isZero || backupDue {
            Section("Needs attention") {
                ForEach(overdue + dueToday) { occ in
                    Button { paying = occ } label: { billAlert(occ) }.buttonStyle(.plain)
                }
                ForEach(overspent, id: \.id) { c in
                    Button { selectTab(.budget) } label: {
                        AlertRow(symbol: "chart.pie.fill", color: .orange,
                                 text: "\(c.name) is over by \(snapshot.budget.line(c.id, month: snapshot.monthKey).remaining.magnitude.compact)",
                                 action: "Cover it")
                    }.buttonStyle(.plain)
                }
                if !unplanned.isZero {
                    Button { selectTab(.budget) } label: {
                        AlertRow(symbol: "chart.pie", color: unplanned.isNegative ? .red : Palette.budget,
                                 text: unplanned.isNegative
                                    ? "This month's budget plans \(unplanned.magnitude.compact) more than you have"
                                    : "\(unplanned.compact) in your budget has no job yet. It's not extra cash.",
                                 action: "Plan it")
                    }.buttonStyle(.plain)
                }
                ForEach(stale, id: \.id) { a in
                    Button { selectTab(.accounts) } label: {
                        AlertRow(symbol: "clock.badge.exclamationmark", color: .orange,
                                 text: "\(a.name) hasn't been updated for a while", action: "Check it")
                    }.buttonStyle(.plain)
                }
                if backupDue {
                    Button { showingSettings = true } label: {
                        AlertRow(symbol: "externaldrive.badge.exclamationmark", color: .orange,
                                 text: snapshot.settings.lastBackupAt == nil ? "Your money data isn't backed up yet"
                                     : "Your last backup was over a month ago",
                                 action: "Back up")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// "Rent · AED 2,500 · Due today · Payment not recorded"
    private func billAlert(_ occ: Occurrence) -> some View {
        let name = snapshot.item(for: occ)?.name ?? "A bill"
        let state = snapshot.state(of: occ)
        let when: String = switch state {
        case .overdue: "Was due \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))"
        case .partiallyPaid: "Part paid, \(occ.remaining.compact) left"
        default: "Due today"
        }
        return AlertRow(symbol: state == .overdue ? "exclamationmark.circle.fill" : "calendar.badge.exclamationmark",
                        color: state == .overdue ? .red : .orange,
                        text: "\(name) · \(occ.remaining.compact)",
                        detail: state == .partiallyPaid ? when : "\(when) · Payment not recorded",
                        action: "Record payment")
    }

    /// Once there's real data, remind until a backup is saved, then monthly
    private var needsBackup: Bool {
        guard snapshot.entries().count >= 5 else { return false }
        guard let last = snapshot.settings.lastBackupAt else { return true }
        return (snapshot.calendar.dateComponents([.day], from: last, to: snapshot.today).day ?? 0) > 30
    }

    // MARK: - Coming up

    @ViewBuilder private var comingUpSection: some View {
        let bills = snapshot.upcomingBills(days: 14).filter { ![.overdue, .dueToday, .partiallyPaid].contains(snapshot.state(of: $0)) }.prefix(3)
        Section {
            if bills.isEmpty {
                Button { selectTab(.plan) } label: {
                    Label(snapshot.items.isEmpty ? "Add your bills to see what's coming" : "Nothing due in the next 2 weeks",
                          systemImage: "calendar.badge.plus")
                }
            } else {
                ForEach(Array(bills)) { occ in
                    Button { paying = occ } label: { OccurrenceRow(occurrence: occ, snapshot: snapshot) }
                        .buttonStyle(.plain)
                }
            }
            if !snapshot.items.isEmpty {
                if plus.isPlus {
                    NavigationLink { ForecastView() } label: {
                        Label("See your balance ahead", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } else {
                    Button { paywall = .moneyAhead } label: {
                        HStack {
                            Label("See your balance ahead", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            PlusBadge()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Coming up")
                Spacer()
                Button("View plan") { selectTab(.plan) }.font(.subheadline)
            }
        }
    }

    // MARK: - Budget health

    @ViewBuilder private var budgetHealthSection: some View {
        let month = snapshot.monthKey
        let categories = snapshot.expenseCategories.filter { !snapshot.budget.allocated($0.id, month: month).isZero || !snapshot.budget.spent($0.id, month: month).isZero }
        Section {
            if categories.isEmpty {
                Button { selectTab(.budget) } label: { Label("Plan this month's spending", systemImage: "chart.pie") }
            } else {
                let lines = categories.map { snapshot.budget.line($0.id, month: month) }
                let planned = lines.map(\.planned).sum(store.currency)
                let spent = lines.map(\.spent).sum(store.currency)
                let over = categories.filter { snapshot.budget.line($0.id, month: month).isOverspent }.count
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(spent.compact) spent of \(planned.compact) planned")
                        Spacer()
                        if over > 0 { StatusBadge(text: "\(over) over", color: .red) }
                    }
                    .font(.subheadline)
                    ProgressBar(value: planned.isPositive ? Double(spent.minorUnits) / Double(planned.minorUnits) : 0,
                                tint: over > 0 ? .orange : Palette.budget)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { selectTab(.budget) }
            }
        } header: {
            Text("Budget this month")
        }
    }

    @ViewBuilder private var reservesSection: some View {
        // Goals show progress and what to save, even at zero; a plain set-aside only once it holds money
        let shown = snapshot.reserves.filter { $0.isGoal || $0.amount.isPositive }
        if !shown.isEmpty {
            Section {
                ForEach(shown) { r in
                    if let progress = snapshot.progress(of: r) {
                        Button { fundingGoal = r } label: { GoalRow(goal: r, progress: progress) }
                            .buttonStyle(.plain)
                    } else {
                        ListRow(title: r.name, caption: snapshot.account(r.accountId)?.name, symbol: "lock.fill", color: Palette.plan) {
                            AmountPill(r.amount)
                        }
                    }
                }
            } header: {
                Text("Savings")
            } footer: {
                if !snapshot.goals.isEmpty { Text("Tap a goal to add money to it.") }
            }
        }
    }

    private var cashAccountCount: String {
        let n = snapshot.cashAccounts.count
        return n == 1 ? "1 account" : "\(n) accounts"
    }

    // MARK: - Explanations

    private var cashExplanation: Explanation {
        let items = snapshot.cashAccounts.map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id)) }
        return Explanation(title: "Cash & bank", total: snapshot.cashAndBank,
                           definition: "The recorded balances of your cash, bank and savings accounts: all the money you have, before bills. Safe to spend starts from the spending accounts among them. Investments, debts and accounts left out of net worth aren't included.",
                           sections: [("Accounts", items, "")])
    }

    private var debtExplanation: Explanation {
        let items = snapshot.debtAccounts.map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id).negated) }
        return Explanation(title: "Total debt", total: snapshot.totalDebt,
                           definition: "What you currently owe on cards and loans, in full. Only each month's payment is held back from Safe to spend. Future interest isn't included.",
                           sections: [("Owed", items, "")])
    }
}

struct FigureCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the accounts included")
    }
}

struct AlertRow: View {
    let symbol: String
    let color: Color
    let text: String
    var detail: String? = nil
    let action: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(action).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// "Is this your Rent payment?" A payment already recorded that looks like an
/// unpaid bill. Linking only marks the bill paid; it never records money again.
struct BillLinkCard: View {
    @Environment(LedgerStore.self) private var store
    let suggestion: BillSuggestion
    let snapshot: FinanceSnapshot
    @State private var error: String?

    var body: some View {
        let s = suggestion
        let from = snapshot.account(s.payment.fromAccountId)?.name ?? "your account"
        let when = s.entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let what = s.entry.kind == .expense ? "An expense" : "A payment"
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.item.name).font(.headline)
                        Text("Bill due \(s.occurrence.dueDate.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(s.occurrence.remaining.formatted).font(.headline).monospacedDigit()
                }
                Text("\(what) of \(s.payment.amount.formatted) (\"\(s.entry.memo)\") was recorded from \(from) on \(when). Your \(s.item.name) bill still shows unpaid.")
                    .font(.subheadline)
                Text(s.isPartial
                     ? "Linking counts it as part of \(s.item.name), leaving \((s.occurrence.remaining - s.payment.amount).formatted) to pay. It won't record another expense or change your balance."
                     : "Linking marks the bill paid. It won't record another expense or change your balance.")
                    .font(.subheadline).foregroundStyle(.secondary)
                FieldError(message: error)
                HStack {
                    Button("Link to \(s.item.name)") {
                        do { try store.match(occurrenceId: s.occurrence.id, entryId: s.entry.id) }
                        catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not this bill") {
                        try? store.dismissBillMatch(entryId: s.entry.id, occurrenceId: s.occurrence.id)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 4)
        } header: {
            Text("Is this your \(s.item.name) payment?")
        }
    }
}

/// Reliable / estimated / stale, in words
struct StatusLine: View {
    let result: SafeToSpend

    var body: some View {
        let notes = result.statuses.compactMap { status -> String? in
            switch status {
            case .reliable: return nil
            case .estimated: return "Includes estimated bills"
            case .stale(let names): return "\(names.joined(separator: ", ")) may be out of date"
            case .shortfall, .incompleteSetup: return nil
            }
        }
        if !notes.isEmpty {
            Label(notes.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.2)))
        }
    }
}
