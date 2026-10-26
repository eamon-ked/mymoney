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
    @AppStorage("showSiriTip") private var showSiriTip = true

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section { safeToSpendBanner.bannerRow() }

                if snapshot.setupComplete {
                    Section {
                        QuickActions()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                insightSection

                alertsSection

                ReviewSection(selected: $reviewing)

                Section {
                    HStack(spacing: 12) {
                        FigureCard(title: "Cash & bank", value: snapshot.cashAndBank.compact,
                                   detail: "\(snapshot.accounts.filter { $0.kind.isAsset && $0.kind != .investment }.count) accounts",
                                   tint: Palette.accounts) { explanation = cashExplanation }
                        FigureCard(title: "Total debt", value: snapshot.totalDebt.compact,
                                   detail: "\(snapshot.accounts.filter { $0.kind.isLiability && !snapshot.balance($0.id).isZero }.count) cards & loans",
                                   tint: snapshot.totalDebt.isPositive ? .red : .gray) { explanation = debtExplanation }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                comingUpSection
                budgetHealthSection
                reservesSection

                if !Self.screenshotMode {
                    Section {
                        Button { showingHelp = true } label: {
                            Label("Not sure how to do something? Ask the guide", systemImage: "questionmark.circle")
                        }
                    }
                }

                if snapshot.setupComplete && !Self.screenshotMode {
                    Section {
                        SiriTipView(intent: LogSpendingIntent(), isVisible: $showSiriTip)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
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
                        Button { if plus.isPlus { showingAsk = true } else { paywall = .appleIntelligence } } label: { Image(systemName: "sparkles") }
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
        let tint: Color
        if let value = result.amount, snapshot.setupComplete {
            amount = value.isNegative ? Money.zero(store.currency).compact : value.compact
            caption = value.isNegative
                ? "Your commitments through \(through) are \(value.magnitude.compact) more than your spendable money"
                : "For flexible spending through \(through)"
            tint = value.isNegative ? .orange : Palette.home
        } else {
            amount = "—"
            caption = "Finish setup to calculate. Add an account with its balance."
            tint = .gray
        }
        return SummaryBanner(title: "Safe to spend", amount: amount, caption: caption, tint: tint,
                             action: { showingSafeToSpend = true }) {
            if let value = result.amount, snapshot.setupComplete {
                StatusLine(result: result)
                BannerFigures(figures: [("Spendable", result.spendableTotal.compact),
                                        ("Set aside", (result.obligationsTotal + result.reservesTotal + result.categoryReservationsTotal + result.buffer).compact),
                                        ("Left", value.compact)])
            }
        }
        .accessibilityIdentifier("safeToSpend")
    }

    // MARK: - Alerts

    @ViewBuilder private var alertsSection: some View {
        let overdue = snapshot.upcomingBills().filter { snapshot.state(of: $0) == .overdue }
        let stale = snapshot.accounts.filter { a in
            guard a.kind.defaultSpendable || a.spendable else { return false }
            guard let d = snapshot.lastConfirmed[a.id] else { return true }
            return (snapshot.calendar.dateComponents([.day], from: d, to: snapshot.today).day ?? 0) > snapshot.settings.staleAfterDays
        }
        let overspent = snapshot.expenseCategories.filter { snapshot.budget.line($0.id, month: snapshot.monthKey).isOverspent }
        let backupDue = needsBackup
        if !overdue.isEmpty || !stale.isEmpty || !overspent.isEmpty || backupDue {
            Section("Needs attention") {
                ForEach(overdue) { occ in
                    Button { paying = occ } label: {
                        AlertRow(symbol: "exclamationmark.circle.fill", color: .red,
                                 text: "\(snapshot.item(for: occ)?.name ?? "A bill") was due \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))",
                                 action: "Mark paid")
                    }.buttonStyle(.plain)
                }
                ForEach(overspent, id: \.id) { c in
                    Button { selectTab(.budget) } label: {
                        AlertRow(symbol: "chart.pie.fill", color: .orange,
                                 text: "\(c.name) is over by \(snapshot.budget.line(c.id, month: snapshot.monthKey).remaining.magnitude.compact)",
                                 action: "Cover it")
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

    /// Once there's real data, remind until a backup is saved, then monthly
    private var needsBackup: Bool {
        guard snapshot.entries().count >= 5 else { return false }
        guard let last = snapshot.settings.lastBackupAt else { return true }
        return (snapshot.calendar.dateComponents([.day], from: last, to: snapshot.today).day ?? 0) > 30
    }

    // MARK: - Coming up

    @ViewBuilder private var comingUpSection: some View {
        let bills = snapshot.upcomingBills(days: 14).filter { snapshot.state(of: $0) != .overdue }.prefix(4)
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
                Button("View plan") { selectTab(.plan) }.font(.caption)
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
                let planned = lines.map { $0.allocated + $0.carriedIn }.sum(store.currency)
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
        if !snapshot.reserves.isEmpty {
            Section("Set aside") {
                ForEach(snapshot.reserves) { r in
                    ListRow(title: r.name, caption: snapshot.account(r.accountId)?.name, symbol: "lock.fill", color: Palette.plan) {
                        AmountPill(r.amount)
                    }
                }
            }
        }
    }

    // MARK: - Explanations

    private var cashExplanation: Explanation {
        let items = snapshot.accounts.filter { $0.kind.isAsset && $0.kind != .investment }
            .map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id)) }
        return Explanation(title: "Cash & bank", total: snapshot.cashAndBank,
                           definition: "The recorded balances of your cash, bank and savings accounts. Investments and debts aren't included.",
                           sections: [("Accounts", items, "")])
    }

    private var debtExplanation: Explanation {
        let items = snapshot.accounts.filter { $0.kind.isLiability }
            .map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id).negated) }
        return Explanation(title: "Total debt", total: snapshot.totalDebt,
                           definition: "What you currently owe on cards and loans. Future interest isn't included.",
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
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.caption).foregroundStyle(.secondary)
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
    let action: String

    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.subheadline)
            Spacer()
            Text(action).font(.caption.weight(.semibold)).foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
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
