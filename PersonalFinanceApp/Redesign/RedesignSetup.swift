//
//  RedesignSetup.swift
//  Nokael Money
//
//  What comes before the tabs: five short, resumable onboarding steps ending
//  with what's actually free to spend, the Face ID lock, and the welcome tour.
//  Progress is saved after each step; pay, bills and essentials can be
//  skipped; nothing is invented.
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct Onboarding: View {
        @Environment(AppModel.self) private var app
        @State private var step = 0

        var body: some View {
            @Bindable var app = app
            VStack(spacing: 0) {
                if step > 0 {
                    HStack {
                        Button { go(step - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Back")
                        Spacer()
                        Text("Step \(step) of 5").rdText(.detailStrong).foregroundStyle(Theme.muted)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case 0: WelcomeStep(next: { go(1) })
                        case 1: CurrencyStep(next: { go(2) })
                        case 2: FirstAccountStep(next: { go(3) })
                        case 3: PayStep(next: { go(4) })
                        case 4: BillsStep(next: { go(5) })
                        default: EssentialsStep(finish: finish)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, step == 0 ? 60 : 8)
                    .padding(.bottom, 40)
                    .id(step)
                    .transition(.opacity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background.ignoresSafeArea())
            .overlay(alignment: .top) { ToastView() }
            .sheet(item: $app.sheet) { first in
                SheetStack(first: first)
                    .environment(app)
                    .environment(app.store)
                    .environment(app.plus)
            }
            .onAppear { step = app.store.settings.onboardingStep }
        }

        /// Saves where the person is, so relaunching resumes here
        private func go(_ s: Int) {
            withAnimation { step = s }
            try? app.store.updateSettings { $0.onboardingStep = s }
        }

        private func finish() {
            try? app.store.updateSettings { $0.onboardingDone = true; $0.onboardingStep = 5 }
        }
    }

    /// A step's heading and the line under it
    private struct StepTitle: View {
        let title: String
        let detail: String
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).rdText(.title)
                Text(detail).rdText(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 24)
        }
    }

    private struct WelcomeStep: View {
        let next: () -> Void
        @State private var restoring = false

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "leaf").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.primary)
                Text("NOKAEL MONEY").rdText(.overline).foregroundStyle(Theme.primary)
                Text("Let's make sense of your money.").rdText(.title)
                Text("A clearer view of what you have, what you owe, and what you can spend.")
                    .rdText(.body).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    point("building.columns", "See all your accounts in one place")
                    Redesign.hairline
                    point("calendar", "Plan bills and spending")
                    Redesign.hairline
                    point("chart.line.uptrend.xyaxis", "Build savings and reduce debt")
                }
                .padding(.horizontal, 16)
                .rdPanel(padding: 0)
                .padding(.vertical, 12)
                Button("Get started", action: next).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("getStarted")
                Button("Restore from a backup") { restoring = true }.buttonStyle(QuietButtonStyle())
                Text("Everything stays on this iPhone.").rdText(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .modifier(RestoreFlow(isPresented: $restoring))
        }

        private func point(_ symbol: String, _ text: String) -> some View {
            HStack(spacing: 14) {
                IconBox(symbol: symbol, small: true)
                Text(text).rdText(.cardTitle)
                Spacer()
            }
            .frame(minHeight: 62)
        }
    }

    private struct CurrencyStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        @State private var currency = CurrencyStep.phoneCurrency
        @State private var starters = true

        static var phoneCurrency: String { Locale.current.currency?.identifier ?? "USD" }

        /// The phone's own currency first, then common ones, then every other code by name
        private var codes: [String] {
            var list = [Self.phoneCurrency]
            for code in ["USD", "EUR", "GBP", "INR", "AED", "SAR", "CAD", "AUD", "PKR", "PHP", "NGN", "BRL"] where !list.contains(code) { list.append(code) }
            if !list.contains(currency) { list.insert(currency, at: 1) }
            let shown = Set(list)
            return list + Locale.commonISOCurrencyCodes.filter { !shown.contains($0) }
                .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        }

        private func name(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

        var body: some View {
            StepTitle(title: "Your currency", detail: "Amounts are shown and stored in this currency.")
            Field(label: "Currency") { Choice(value: $currency, options: codes) { "\($0) · \(name($0))" } }
            ToggleRow(title: "Start with common categories",
                      detail: "Groceries, rent, transport and a few more. You can rename or remove any of them. No amounts are added.",
                      isOn: $starters)
                .padding(.top, 16)
            Button("Continue") {
                try? app.store.updateSettings { $0.currency = currency; $0.localeIdentifier = Locale.current.identifier }
                if starters { try? app.store.addStarterCategories() }
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("continue")
            .padding(.top, 28)
            // Until this step has been saved, the stored currency is only the record's default
            .onAppear { if app.store.settings.onboardingStep > 1 { currency = app.store.settings.currency } }
        }
    }

    private struct FirstAccountStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void

        var body: some View {
            StepTitle(title: "Add an account", detail: "Start with the account you use most. You can add the rest any time.")
            if !app.accounts.isEmpty {
                Redesign.overline("Added")
                Divided(items: app.accounts) { AccountRow(account: $0, compact: true) }
                    .padding(.horizontal, 16)
                    .rdPanel(padding: 0)
                    .padding(.bottom, 20)
            }
            Button(app.accounts.isEmpty ? "Add an account" : "Add another account") { app.open(.newAccount(loan: false)) }
                .buttonStyle(app.accounts.isEmpty ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(QuietButtonStyle()))
                .accessibilityIdentifier("newAccount")
            if !app.accounts.isEmpty {
                Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("continue")
                    .padding(.top, 12)
            }
        }
    }

    private struct PayStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        @State private var amount = ""
        @State private var frequency: Frequency = .monthly(every: 1)
        @State private var nextDate = Date()
        @State private var problem: String?

        var body: some View {
            StepTitle(title: "Your pay", detail: "Helps plan until your next payday. It's never counted as money you have until it arrives.")
            VStack(alignment: .leading, spacing: 16) {
                AmountBox(label: "Usual pay in \(app.currency)", text: $amount, autofocus: false)
                Field(label: "How often") { Choice(value: $frequency, options: Redesign.frequencies) { $0.label } }
                Field(label: "Next payday") {
                    DatePicker("Next payday", selection: $nextDate, in: Date()..., displayedComponents: .date).labelsHidden()
                }
                Problem(text: problem)
                Button("Save and continue", action: save).buttonStyle(PrimaryButtonStyle()).padding(.top, 12)
                Button("Skip for now", action: next).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("skip")
            }
        }

        private func save() {
            guard let money = app.parse(amount), money.isPositive else { problem = "Enter your usual pay, or skip."; return }
            do {
                try app.store.setUpSalary(money, every: frequency, nextPayday: nextDate)
                next()
            } catch { problem = StoreError.from(error).errorDescription }
        }
    }

    private struct BillsStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void

        var body: some View {
            let reserves = app.snapshot.reserves
            StepTitle(title: "Bills and savings",
                      detail: "Add rent, loan payments or money you keep aside, so safe to spend can account for them. You can do this later in Bills and Budget.")
            if !app.bills.isEmpty {
                Redesign.overline("Bills")
                Divided(items: Array(app.bills.prefix(8))) { BillRow(bill: $0, compact: true) }
                    .padding(.horizontal, 16).rdPanel(padding: 0).padding(.bottom, 16)
            }
            if !reserves.isEmpty {
                Redesign.overline("Set aside")
                DetailCard {
                    ForEach(reserves) { r in DetailRow(label: app.hidesDetails ? "Savings" : r.name, value: app.money(r.amount)) }
                }
                .padding(.bottom, 16)
            }
            VStack(spacing: 12) {
                Button("Add a bill") { app.open(.entry(.bill)) }.buttonStyle(QuietButtonStyle())
                Button("Set money aside") { app.open(.reserve(nil, goal: false)) }.buttonStyle(QuietButtonStyle())
                Button(app.snapshot.items.isEmpty && reserves.isEmpty ? "Skip" : "Continue", action: next)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("continue")
                    .padding(.top, 12)
            }
        }
    }

    /// Plans the essentials for this month, then shows what's left and why
    private struct EssentialsStep: View {
        @Environment(AppModel.self) private var app
        let finish: () -> Void
        @State private var amounts: [UUID: String] = [:]
        @State private var problem: String?

        /// Starter essentials when they exist, otherwise the first few spending categories
        private var categories: [LedgerAccountRecord] {
            let all = app.snapshot.expenseCategories.sorted { $0.sortOrder < $1.sortOrder }
            let essentials = all.filter { $0.group == "Essentials" }
            return essentials.isEmpty ? Array(all.prefix(5)) : essentials
        }

        var body: some View {
            let s = app.snapshot
            let month = s.monthKey
            let result = s.safeToSpend()
            let unplanned = s.budget.availableToAllocate(month: month)
            StepTitle(title: "Plan the essentials",
                      detail: "Roughly what you spend each month on the basics, in \(app.currency). Bills you added are already counted, so leave those empty.")
            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { i, c in
                    let line = s.budget.line(c.id, month: month)
                    HStack(spacing: 12) {
                        IconBox(AppModel.look(c), small: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).rdText(.cardTitle)
                            if line.fromBills.isPositive {
                                Text(private: "\(app.money(line.fromBills)) in bills").rdText(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        TextField("0", text: binding(c.id, current: line.allocated))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .rdText(.figure)
                            .frame(width: 110)
                    }
                    .frame(minHeight: 62)
                    if i < categories.count - 1 { Redesign.hairline }
                }
            }
            .padding(.horizontal, 16)
            .rdPanel(padding: 0)

            if let amount = result.amount {
                Redesign.overline("What's actually free").padding(.top, 24)
                DetailCard {
                    DetailRow(label: "In spending accounts", value: app.money(result.spendableTotal))
                    if result.obligationsTotal.isPositive {
                        DetailRow(label: "Bills before \(app.day(result.periodEnd))", value: "−" + app.money(result.obligationsTotal))
                    }
                    if result.categoryReservationsTotal.isPositive {
                        DetailRow(label: "Planned for essentials", value: "−" + app.money(result.categoryReservationsTotal))
                    }
                    if result.reservesTotal.isPositive { DetailRow(label: "Set aside", value: "−" + app.money(result.reservesTotal)) }
                    if result.buffer.isPositive { DetailRow(label: "Buffer", value: "−" + app.money(result.buffer)) }
                    DetailRow(label: "Safe to spend",
                              value: amount.isNegative ? "Short by \(app.money(amount.magnitude))" : app.money(amount))
                }
                Redesign.footnote(amount.isNegative
                                  ? "Bills and plans need more than your spending accounts hold before payday. Home shows what to do about it."
                                  : "What you can spend on anything until payday, after bills and the essentials above. It's the big number on Home.")
                    .padding(.top, 10).padding(.horizontal, 4)
                if !unplanned.isZero {
                    DetailCard { DetailRow(label: "Not planned yet", value: app.money(unplanned)) }.padding(.top, 16)
                    Redesign.footnote(unplanned.isNegative
                                      ? "You've planned more than you have this month. Lower an amount above, or adjust it later in Budget."
                                      : "Money no budget uses yet. It isn't extra cash: give it a budget later, or leave it.")
                        .padding(.top, 10).padding(.horizontal, 4)
                }
            }
            Problem(text: problem).padding(.top, 16)
            Button("Finish") { saveAll(); if problem == nil { finish() } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("finish")
                .padding(.top, 28)
        }

        private func binding(_ id: UUID, current: Money) -> Binding<String> {
            Binding(get: { amounts[id] ?? MoneyFormat.editable(current, emptyWhenZero: true) },
                    // Saved as typed, so the summary below follows along; mistakes are only reported on Finish
                    set: { amounts[id] = $0; save(id, quietly: true) })
        }

        private func save(_ id: UUID, quietly: Bool = false) {
            guard let text = amounts[id] else { return }
            guard let amount = app.parse(text.isEmpty ? "0" : text), !amount.isNegative else {
                if !quietly { problem = "Enter each amount as a number." }
                return
            }
            if !quietly { problem = nil }
            do { try app.store.setAllocation(amount, categoryId: id, month: app.snapshot.monthKey) }
            catch { problem = StoreError.from(error).errorDescription }
        }

        private func saveAll() {
            problem = nil
            for id in amounts.keys { save(id); if problem != nil { return } }
        }
    }

    /// A button style chosen at run time
    struct AnyButtonStyle: ButtonStyle {
        private let make: (Configuration) -> AnyView
        init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
        func makeBody(configuration: Configuration) -> some View { make(configuration) }
    }
}

// MARK: - Lock and tour

extension Redesign {
    struct LockScreen: View {
        let unlock: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                Image(systemName: "lock").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.primary)
                Text("Nokael Money is locked").rdText(.heading)
                Button("Unlock", action: unlock).buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .onAppear(perform: unlock)
        }
    }

    /// Shown once after setup: where the few things that matter are
    struct WelcomeTour: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("3 things to know").rdText(.title).padding(.top, 40)
                point("plus", "The + at the bottom right",
                      "Add money spent or received, a transfer, or tap More… when you're not sure what to choose.")
                point("leaf", "Safe to spend, on Home",
                      "What you can spend until payday after bills and plans. Tap it to see how it's worked out.")
                point("questionmark", "Help, at the top of Home",
                      "Stuck? Type your question or just what happened, like “I got my salary”.")
                Spacer()
                Button("Got it") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .interactiveDismissDisabled()
        }

        private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
            HStack(alignment: .top, spacing: 16) {
                IconBox(symbol: symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).rdText(.section)
                    Text(detail).rdText(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
