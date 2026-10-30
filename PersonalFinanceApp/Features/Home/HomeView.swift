//
//  HomeView.swift
//  Nokael Money
//
//  One question: can I spend, and does anything need me? Safe to spend, the
//  to-do list, pinned categories and what's coming up. Nothing else.
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
    @State private var paying: Occurrence?
    @State private var showingAsk = false
    @State private var paywall: PlusFeature?
    @State private var showingPayday = false
    @State private var linking: BillSuggestion?
    @State private var showingReview = false
    @State private var showingAllTasks = false

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                // What I can spend, then what needs me
                Section {
                    safeToSpendBanner.bannerRow()
                }

                insightSection
                todoSection
                pinnedSection
                comingUpSection
            }
            .listStyle(.insetGrouped)
            .canvas()
            .navigationTitle("Home")
            // Safe to spend is the first thing on screen, not a big title
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                if AppleIntelligence.isReady {
                    ToolbarItem(placement: .primaryAction) {
                        Button { if plus.isPlus { showingAsk = true } else { paywall = .appleIntelligence } } label: {
                            // Words, not just a glyph: nobody guesses what sparkles do
                            // (the toolbar drops a Label's title, so this is plain text)
                            Text("Ask").fontWeight(.semibold)
                        }
                            .accessibilityLabel("Ask about your money")
                            .accessibilityIdentifier("askButton")
                    }
                }
                GlobalAddButton()
            }
            .sheet(isPresented: $showingSafeToSpend) { SafeToSpendView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
            .sheet(item: $linking) { BillLinkSheet(id: $0.id) }
            .sheet(isPresented: $showingReview) { ReviewSheet() }
            .sheet(isPresented: $showingPayday) { PaydaySheet() }
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

    /// One sentence about the month so far, the same for everyone. The app writes it from the
    /// ledger, so the figures are exact. Tapping it opens the month in Reports.
    @ViewBuilder private var insightSection: some View {
        if let sentence = MonthSoFar(snapshot).sentence {
            Section {
                MonthSoFarCard(sentence: sentence) {
                    selectTab(.reports)
                }
            }
        }
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
            amount = value.isNegative ? Money.zero(store.currency).compact : value.whole
            if value.isNegative { alert = "Short by \(value.magnitude.compact)" }
            caption = value.isNegative
                ? "Bills and your buffer through \(through) need more than the money in your spending accounts"
                : "Until \(through), after bills and savings"
            tint = value.isNegative ? .orange : Palette.home
        } else {
            amount = "—"
            caption = "Finish setup to calculate. Add an account with its balance."
            tint = .gray
        }
        // Estimates and out-of-date balances are explained in "How it's calculated"; the card stays calm
        return SummaryBanner(title: "Safe to spend", amount: amount, caption: caption, alert: alert, tint: tint,
                             action: { showingSafeToSpend = true }, glow: tint == Palette.home) {
        }
        .accessibilityIdentifier("safeToSpend")
    }

    // MARK: - To do

    @ViewBuilder private var todoSection: some View {
        let tasks = HomeTask.all(snapshot)
        let shown = showingAllTasks ? tasks : Array(tasks.prefix(3))
        if snapshot.setupComplete || !tasks.isEmpty {
            Section {
                if tasks.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Palette.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're all caught up").font(.headline)
                            Text("Nothing needs you right now.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                ForEach(shown) { task in
                    Button { open(task) } label: { row(task) }.buttonStyle(.plain)
                }
                if tasks.count > 3 {
                    Button(showingAllTasks ? "Show fewer" : "Show \(tasks.count - 3) more") {
                        withAnimation { showingAllTasks.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } header: {
                Text("To do")
            }
        }
    }

    private func open(_ task: HomeTask) {
        switch task {
        case .bill(let occ): paying = occ
        case .billLink(let s): linking = s
        case .payday: showingPayday = true
        case .overspent, .noBudget, .unplanned: selectTab(.budget)
        case .review: showingReview = true
        case .stale: selectTab(.accounts)
        case .backup: showingSettings = true
        }
    }

    private func row(_ task: HomeTask) -> some View {
        switch task {
        case .bill(let occ):
            return billAlert(occ)
        case .billLink(let s):
            return AlertRow(symbol: "link", color: Palette.plan,
                            text: "Is this your \(s.item.name) payment?",
                            detail: "\(s.payment.amount.compact) recorded \(s.entry.date.formatted(.dateTime.day().month(.abbreviated)))",
                            action: "Check")
        case .payday(let item, let occ):
            return AlertRow(symbol: "banknote.fill", color: .green,
                            text: "Payday? Got your \(item.name.lowercased())?",
                            detail: "\(occ.remaining.compact) expected \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))",
                            action: "Record it")
        case .overspent(let c, let by):
            return AlertRow(symbol: "chart.pie.fill", color: .orange,
                            text: "\(c.name) went \(by.compact) over its budget", action: "Fix it")
        case .noBudget(let categories, let total):
            return AlertRow(symbol: "questionmark.circle.fill", color: .orange,
                            text: "\(total.compact) spent with no budget",
                            detail: categories.prefix(3).map(\.name).joined(separator: ", "),
                            action: categories.count == 1 ? "Set budget" : "Set budgets")
        case .review(let count):
            return AlertRow(symbol: "checklist", color: Palette.accounts,
                            text: count == 1 ? "1 new entry to check" : "\(count) new entries to check",
                            detail: "Saved from Apple Pay, your bank or Siri",
                            action: "Check")
        case .unplanned(let money):
            return AlertRow(symbol: "chart.pie", color: money.isNegative ? .red : Palette.budget,
                            text: money.isNegative
                                ? "This month's budget plans \(money.magnitude.compact) more than you have"
                                : "\(money.compact) isn't planned yet",
                            action: "Plan it")
        case .stale(let a):
            return AlertRow(symbol: "clock.badge.exclamationmark", color: .orange,
                            text: "\(a.name) hasn't been updated for a while", action: "Check it")
        case .backup(let never):
            return AlertRow(symbol: "externaldrive.badge.exclamationmark", color: .orange,
                            text: never ? "Your money data isn't backed up yet" : "Your last backup was over a month ago",
                            action: "Back up")
        }
    }

    /// "Rent · AED 2,500 · Due today · Payment not recorded"
    private func billAlert(_ occ: Occurrence) -> AlertRow {
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

    // MARK: - Pinned

    @ViewBuilder private var pinnedSection: some View {
        let pinned = snapshot.settings.pinnedCategoryIds.compactMap { id in snapshot.expenseCategories.first { $0.id == id } }
        if !pinned.isEmpty {
            Section("Pinned") {
                ForEach(pinned, id: \.id) { c in
                    Button { selectTab(.budget) } label: {
                        BudgetRow(category: c, line: snapshot.budget.line(c.id, month: snapshot.monthKey), holdsLoans: snapshot.holdsLoans(c.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Coming up

    @ViewBuilder private var comingUpSection: some View {
        let bills = snapshot.upcomingBills(days: 14).filter { ![.overdue, .dueToday, .partiallyPaid].contains(snapshot.state(of: $0)) }.prefix(3)
        Section {
            if bills.isEmpty {
                NavigationLink { BillsView() } label: {
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
                        Label("Money ahead", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } else {
                    Button { paywall = .moneyAhead } label: {
                        HStack {
                            Label("Money ahead", systemImage: "chart.line.uptrend.xyaxis")
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
                NavigationLink("See all") { BillsView() }.font(.subheadline).accessibilityIdentifier("seeAllBills")
            }
        }
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

/// One bill-link question from the to-do list; closes itself once answered
struct BillLinkSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    var body: some View {
        let snapshot = store.snapshot
        let suggestion = snapshot.billSuggestions.first { $0.id == id }
        NavigationStack {
            List {
                if let suggestion { BillLinkCard(suggestion: suggestion, snapshot: snapshot) }
            }
            .navigationTitle("Bill payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: suggestion == nil) { _, answered in if answered { dismiss() } }
    }
}

/// Captured entries to check, from the to-do list; closes itself when none are left
struct ReviewSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing: EntryRecord?

    var body: some View {
        let left = store.snapshot.entries().filter(\.needsReview).count
        NavigationStack {
            List { ReviewSection(selected: $reviewing) }
                .navigationTitle("Check new entries")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .sheet(item: $reviewing) { EntryDetailView(record: $0) }
        }
        .onChange(of: left == 0) { _, done in if done { dismiss() } }
    }
}

