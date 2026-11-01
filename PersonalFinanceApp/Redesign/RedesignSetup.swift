//
//  RedesignSetup.swift
//  Nokael Money
//
//  What comes before the tabs: one question per screen (your name and
//  currency, then a bank account started from a statement or a typed balance,
//  or cash), ending on Home; then the Face ID lock and the welcome tour. Pay,
//  bills and a budget come later, from Home. Progress is saved after each step.
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct Onboarding: View {
        @Environment(AppModel.self) private var app
        @State private var step = 0
        @State private var forward = true
        /// The account just added, for the balance check after a statement
        @State private var newAccount: UUID?
        /// Accounts were already in when this step opened: it's "Add another", which can be left
        @State private var hadAccounts = false

        /// Welcome, name and currency, account, balance check, your accounts
        private static let last = 4

        var body: some View {
            @Bindable var app = app
            VStack(spacing: 0) {
                if step > 0 {
                    HStack(spacing: 12) {
                        // Adding another account goes back to the list; the first goes back to the name
                        if step <= 2 {
                            Button { go(step == 2 && hadAccounts ? Self.last : step - 1) } label: {
                                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Back")
                            .accessibilityIdentifier("back")
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                        // Name, account, done
                        HStack(spacing: 6) {
                            ForEach(1...3, id: \.self) { i in
                                Capsule().fill(i <= min(step, 3) ? Theme.primary : Theme.border).frame(height: 4)
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Step \(min(step, 3)) of 3")
                        // Changed their mind about another account: straight to Home
                        if step == 2 && hadAccounts {
                            Button("Cancel", action: finish)
                                .rdText(.label).foregroundStyle(Theme.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("cancelAddAccount")
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Group {
                    switch step {
                    case 0: WelcomeStep(next: { go(1) })
                    case 1: NameStep(next: { go(2) })
                    case 2: AccountStep(added: { id, imported in newAccount = id; go(imported ? 3 : 4) })
                        .onAppear { hadAccounts = !app.accounts.isEmpty }
                    case 3: BalanceCheckStep(accountId: newAccount, next: { go(4) })
                    default: AccountsStep(addAnother: { go(2) }, finish: finish)
                    }
                }
                .id(step)
                // The old question leaves at once so the two never overlap; the new one eases in
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                                        removal: .identity))
            }
            .background(Theme.background.ignoresSafeArea())
            .overlay(alignment: .top) { ToastView() }
            .sheet(item: $app.sheet) { first in
                SheetStack(first: first)
                    .environment(app)
                    .environment(app.store)
                    .environment(app.plus)
            }
            .onAppear {
                // Without an account, setup resumes at most at the account question; with one, at the list
                let saved = min(app.store.settings.onboardingStep, Self.last)
                step = app.accounts.isEmpty ? min(saved, 2) : (saved >= 2 ? Self.last : saved)
            }
        }

        /// Saves where the person is, so relaunching resumes here
        private func go(_ s: Int) {
            // The next question shouldn't open under the last one's keyboard
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            forward = s > step
            withAnimation(.easeInOut(duration: 0.3)) { step = s }
            try? app.store.updateSettings { $0.onboardingStep = s }
        }

        private func finish() {
            try? app.store.updateSettings { $0.onboardingDone = true; $0.onboardingStep = Self.last }
        }
    }

    /// One setup question: the question and its line, the answer, and the step's
    /// buttons kept above the keyboard
    private struct StepPage<Content: View, Actions: View>: View {
        let title: String
        var detail: String? = nil
        @ViewBuilder let content: Content
        @ViewBuilder let actions: Actions

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).rdText(.title).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).rdText(.body).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    content.padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) { actions }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Theme.background)
            }
        }
    }

    private struct WelcomeStep: View {
        let next: () -> Void
        @State private var restoring = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Image(systemName: "leaf").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.primary)
                Text("Nokael Money").rdText(.detailStrong).foregroundStyle(Theme.primary)
                Text("Know what's safe to spend.").rdText(.title).fixedSize(horizontal: false, vertical: true)
                Text("Add the account you spend from and you're in. Your pay, bills and budget can come later.")
                    .rdText(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Get started", action: next).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("getStarted")
                Button("Restore from a backup") { restoring = true }.buttonStyle(QuietButtonStyle())
                Text("No account or sign-in. Everything stays on this iPhone.").rdText(.caption).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .modifier(RestoreFlow(isPresented: $restoring))
        }
    }

    /// The person's first name and the currency their money is in; the phone's currency unless changed
    private struct NameStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        @State private var name = ""
        @State private var currency = NameStep.phoneCurrency

        static var phoneCurrency: String { Locale.current.currency?.identifier ?? "USD" }

        /// The phone's own currency first, then common ones, then every other code by name
        private var codes: [String] {
            var list = [Self.phoneCurrency]
            for code in ["USD", "EUR", "GBP", "INR", "AED", "SAR", "CAD", "AUD", "PKR", "PHP", "NGN", "BRL"] where !list.contains(code) { list.append(code) }
            if !list.contains(currency) { list.insert(currency, at: 1) }
            let shown = Set(list)
            return list + Locale.commonISOCurrencyCodes.filter { !shown.contains($0) }
                .sorted { label($0).localizedCaseInsensitiveCompare(label($1)) == .orderedAscending }
        }

        private func label(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

        var body: some View {
            StepPage(title: "What should we call you?", detail: "Your first name, for Home. You can leave it empty.") {
                VStack(alignment: .leading, spacing: 16) {
                    Field(label: "First name") {
                        TextField("e.g. Sam", text: $name)
                            .textContentType(.givenName)
                            .submitLabel(.next)
                            .onSubmit(save)
                            .accessibilityIdentifier("firstName")
                    }
                    if app.accounts.isEmpty {
                        Field(label: "Your money is in") {
                            Choice(value: $currency, options: codes) { "\($0) · \(label($0))" }
                        }
                        .accessibilityIdentifier("currency")
                    }
                }
            } actions: {
                Button("Continue", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("continue")
            }
            .onAppear {
                name = app.holder
                if app.store.settings.onboardingStep > 1 { currency = app.store.settings.currency }
            }
        }

        private func save() {
            app.holder = name.trimmingCharacters(in: .whitespaces)
            if app.accounts.isEmpty {
                // The currency is set first so balances are read and kept in it
                try? app.store.updateSettings { $0.currency = currency; $0.localeIdentifier = Locale.current.identifier }
            }
            try? app.store.addStarterCategories()
            next()
        }
    }

    /// A bank account, started from a statement or a typed balance, or cash on hand
    private struct AccountStep: View {
        @Environment(AppModel.self) private var app
        /// The account and whether a statement went into it
        let added: (UUID, Bool) -> Void
        @State private var cash = false
        @State private var name = ""
        @State private var amount = ""
        /// Bank only: typing today's balance instead of importing
        @State private var typing = false
        /// The bank account made for a statement, kept if they switch to typing instead
        @State private var created: UUID?
        @State private var importing = false
        /// Set once the account is handed on, so leaving doesn't undo it
        @State private var done = false
        @State private var problem: String?

        private var defaultName: String {
            if cash { return "Cash" }
            return app.accounts.isEmpty ? "Main account" : "Account \(app.accounts.count + 1)"
        }

        var body: some View {
            StepPage(title: app.accounts.isEmpty ? "Add your main account" : "Add another account",
                     detail: cash ? "The cash you have on you now."
                        : typing ? "What your bank app shows as the balance right now."
                        : "Import a statement and the app starts from your bank's own balance, with your recent spending already in.") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Kind", selection: $cash) {
                        Text("Bank account").tag(false)
                        Text("Cash").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(created != nil)
                    if !cash {
                        Field(label: "Name") {
                            TextField(defaultName, text: $name).accessibilityIdentifier("accountName")
                        }
                    }
                    if cash || typing {
                        AmountBox(label: cash ? "Cash on you" : "Balance today", text: $amount, autofocus: false,
                                  identifier: "openingBalance", keyboardDone: false)
                    } else {
                        Redesign.footnote("Download it from your bank's app or website as CSV (sometimes called Excel), and save it to Files.")
                    }
                    Problem(text: problem)
                }
            } actions: {
                if cash || typing {
                    Button("Add account", action: saveTyped).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveAccount")
                    if !cash {
                        Button("Import a statement instead") { typing = false; problem = nil }
                            .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button("Import a statement", action: startImport).buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("importStatement")
                    Button("Enter the balance instead") { typing = true; problem = nil }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("enterBalance")
                }
            }
            // Left with Back: an account made for a statement that never came is taken away again
            .onDisappear {
                if !done, let created { try? app.store.discardUnusedAccount(created) }
            }
            .onChange(of: app.sheet == nil) { _, closed in
                guard closed, importing, let id = created else { return }
                importing = false
                if app.snapshot.entries(touching: id).contains(where: { $0.kind != .openingBalance }) {
                    done = true
                    added(id, true)
                } else {
                    problem = "Nothing was imported. Try another file, or enter the balance instead."
                }
            }
        }

        private var finalName: String {
            let typed = name.trimmingCharacters(in: .whitespaces)
            return typed.isEmpty ? defaultName : typed
        }

        /// The account is made first, at nothing, so the statement has somewhere to go
        private func startImport() {
            problem = nil
            do {
                let id = try created ?? app.store.addAccount(name: finalName, kind: .bank, balance: .zero(app.currency),
                                                             openingDate: app.snapshot.today).id
                created = id
                importing = true
                app.open(.importStatement(id))
            } catch { problem = StoreError.from(error).errorDescription }
        }

        private func saveTyped() {
            problem = nil
            guard let money = app.parse(amount.isEmpty ? "0" : amount), !money.isNegative else {
                problem = "Enter the balance as a number."
                return
            }
            do {
                if let created {
                    try app.store.correctOpeningBalance(created, to: money)
                    done = true
                    added(created, false)
                } else {
                    let account = try app.store.addAccount(name: cash ? "Cash" : finalName, kind: cash ? .cash : .bank,
                                                           balance: money, openingDate: app.snapshot.today)
                    done = true
                    added(account.id, false)
                }
            } catch { problem = StoreError.from(error).errorDescription }
        }
    }

    /// After a statement: the balance it ends on against what the bank app shows now,
    /// which differs by anything on hold or since
    private struct BalanceCheckStep: View {
        @Environment(AppModel.self) private var app
        let accountId: UUID?
        let next: () -> Void
        @State private var different = false
        @State private var amount = ""
        @State private var problem: String?

        var body: some View {
            let balance = accountId.map { app.snapshot.balance($0) } ?? .zero(app.currency)
            StepPage(title: "Does your bank app show \(app.money(balance))?",
                     detail: "That's where your statement ends. Card payments still on hold, or anything since, can make your bank app show a different amount.") {
                if different {
                    VStack(alignment: .leading, spacing: 16) {
                        AmountBox(label: "What your bank app shows now", text: $amount, identifier: "bankBalance", keyboardDone: false)
                        Problem(text: problem)
                    }
                }
            } actions: {
                if different {
                    Button("Use this balance", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("useBalance")
                    Button("It's the same after all") { different = false; problem = nil }.buttonStyle(QuietButtonStyle())
                } else {
                    Button("Yes, that's right", action: next).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("balanceRight")
                    Button("No, it's different") { different = true }.buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("balanceDifferent")
                }
            }
        }

        private func save() {
            guard let accountId, let money = app.parse(amount) else { problem = "Enter the balance as a number."; return }
            do {
                try app.store.reconcile(accountId: accountId, statementDate: Date(), statementBalance: money,
                                        reason: "Balance in the bank app")
                next()
            } catch { problem = StoreError.from(error).errorDescription }
        }
    }

    /// What's been added, with room for one more before Home
    private struct AccountsStep: View {
        @Environment(AppModel.self) private var app
        let addAnother: () -> Void
        let finish: () -> Void

        var body: some View {
            StepPage(title: "You're ready",
                     detail: "Home shows what's safe to spend. Your pay, bills and a budget make it truer; Home will help you add them.") {
                Divided(items: app.accounts) { AccountRow(account: $0, compact: true) }
                    .padding(.horizontal, 16)
                    .rdPanel(padding: 0)
            } actions: {
                Button("Go to Home", action: finish).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("finish")
                Button("Add another account", action: addAnother).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("addAnother")
            }
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
