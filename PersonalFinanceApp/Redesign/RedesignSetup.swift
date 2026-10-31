//
//  RedesignSetup.swift
//  Nokael Money
//
//  What comes before the tabs: one question per screen (what's in your main
//  account, when you're paid, which bills come first), ending on what's safe
//  to spend; then the Face ID lock and the welcome tour. Progress is saved
//  after each step; pay and bills can be skipped; nothing is invented.
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct Onboarding: View {
        @Environment(AppModel.self) private var app
        @State private var step = 0
        @State private var forward = true

        /// Welcome, account, pay, bills, done
        private static let last = 4

        var body: some View {
            @Bindable var app = app
            VStack(spacing: 0) {
                if step > 0 && step < Self.last {
                    HStack(spacing: 12) {
                        Button { go(step - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Back")
                        // One segment per question
                        HStack(spacing: 6) {
                            ForEach(1..<Self.last, id: \.self) { i in
                                Capsule().fill(i <= step ? Theme.primary : Theme.border).frame(height: 4)
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Step \(step) of \(Self.last - 1)")
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 8)
                }
                Group {
                    switch step {
                    case 0: WelcomeStep(next: { go(1) })
                    case 1: AccountStep(next: { go(2) })
                    case 2: PayStep(next: { go(3) })
                    case 3: BillsStep(next: { go(4) })
                    default: DoneStep(back: { go(3) }, finish: finish)
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
                // Without an account, setup restarts at the account question
                let saved = min(app.store.settings.onboardingStep, Self.last)
                step = saved > 1 && app.accounts.isEmpty ? 1 : saved
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

    /// A date as a plain row: what it is on the left, the date to tap on the right
    private struct DateRow: View {
        @Environment(AppModel.self) private var app
        let label: String
        @Binding var date: Date

        var body: some View {
            DatePicker(label, selection: $date, in: app.snapshot.today..., displayedComponents: .date)
                .rdText(.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .rdPanel(padding: 0)
        }
    }

    private struct WelcomeStep: View {
        let next: () -> Void
        @State private var restoring = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Image(systemName: "leaf").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.primary)
                Text("Know what's safe to spend.").rdText(.title).fixedSize(horizontal: false, vertical: true)
                Text("Three quick questions and you'll see how much you can spend before payday, with your bills already set aside.")
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

    /// The main account and its balance; the currency is the phone's unless changed here
    private struct AccountStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        @State private var amount = ""
        @State private var cash = false
        @State private var currency = AccountStep.phoneCurrency
        @State private var problem: String?

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
            let added = app.accounts
            StepPage(title: added.isEmpty ? "How much is in your main account?" : "Your main account",
                     detail: added.isEmpty ? "The one you spend from most. Add the rest any time in Accounts." : nil) {
                if added.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Kind", selection: $cash) {
                            Text("Bank account").tag(false)
                            Text("Cash").tag(true)
                        }
                        .pickerStyle(.segmented)
                        AmountBox(label: "Balance today", text: $amount, identifier: "openingBalance", keyboardDone: false)
                        Menu {
                            Picker("Currency", selection: $currency) {
                                ForEach(codes, id: \.self) { Text("\($0) · \(name($0))").tag($0) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("In \(name(currency)) (\(currency))")
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .rdText(.detail)
                            .foregroundStyle(Theme.primary)
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Currency, \(name(currency))")
                        Problem(text: problem)
                    }
                } else {
                    Divided(items: added) { AccountRow(account: $0, compact: true) }
                        .padding(.horizontal, 16)
                        .rdPanel(padding: 0)
                }
            } actions: {
                Button("Continue", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("continue")
            }
            .onAppear { if app.store.settings.onboardingStep > 1 { currency = app.store.settings.currency } }
        }

        private func save() {
            guard app.accounts.isEmpty else { next(); return }
            problem = nil
            // The currency is set first so the balance is read and kept in it
            try? app.store.updateSettings { $0.currency = currency; $0.localeIdentifier = Locale.current.identifier }
            guard let money = app.parse(amount.isEmpty ? "0" : amount), !money.isNegative else {
                problem = "Enter the balance as a number."
                return
            }
            do {
                try app.store.addStarterCategories()
                try app.store.addAccount(name: cash ? "Cash" : "Main account", kind: cash ? .cash : .bank,
                                         balance: money, openingDate: app.snapshot.today)
                next()
            } catch { problem = StoreError.from(error).errorDescription }
        }
    }

    private struct PayStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        @State private var amount = ""
        @State private var frequency: Frequency = .monthly(every: 1)
        @State private var nextDate = PayStep.likelyPayday
        @State private var problem: String?

        /// The end of this month, or of next month when this one is nearly over
        static var likelyPayday: Date {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            func monthEnd(_ offset: Int) -> Date {
                let start = cal.date(from: cal.dateComponents([.year, .month], from: today))!
                return cal.date(byAdding: DateComponents(month: offset + 1, day: -1), to: start)!
            }
            let thisMonth = monthEnd(0)
            return cal.dateComponents([.day], from: today, to: thisMonth).day! >= 3 ? thisMonth : monthEnd(1)
        }

        var body: some View {
            StepPage(title: "When are you paid next?",
                     detail: "So safe to spend lasts until then. Pay isn't counted until it arrives.") {
                VStack(alignment: .leading, spacing: 16) {
                    DateRow(label: "Next payday", date: $nextDate)
                    AmountBox(label: "Usual pay", text: $amount, autofocus: false, keyboardDone: false)
                    Field(label: "How often") { Choice(value: $frequency, options: Redesign.frequencies) { $0.label } }
                    Problem(text: problem)
                }
            } actions: {
                Button("Continue", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("continue")
                Button("I don't have a regular pay", action: next).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("skip")
            }
        }

        private func save() {
            // Already set up on an earlier visit to this step
            if app.snapshot.nextIncomeDate != nil && amount.isEmpty { next(); return }
            guard let money = app.parse(amount), money.isPositive else { problem = "Enter your usual pay, or tap I don't have a regular pay."; return }
            do {
                try app.store.setUpSalary(money, every: frequency, nextPayday: nextDate)
                next()
            } catch { problem = StoreError.from(error).errorDescription }
        }
    }

    private struct BillsStep: View {
        @Environment(AppModel.self) private var app
        let next: () -> Void
        /// The bill being added, if any; its fields are kept separately so typing writes straight to them
        @State private var adding = false
        @State private var name = ""
        @State private var category: String?
        @State private var amount = ""
        @State private var due = Date()
        @State private var problem: String?

        /// A common bill to start from, and the starter category it's filed under
        private struct Kind: Identifiable {
            let name: String
            let symbol: String
            var category: String? = nil
            var id: String { name }
        }

        private static let kinds = [
            Kind(name: "Rent", symbol: "house", category: "Rent or mortgage"),
            Kind(name: "Phone", symbol: "iphone", category: "Phone & internet"),
            Kind(name: "Internet", symbol: "wifi", category: "Phone & internet"),
            Kind(name: "Electricity", symbol: "bolt", category: "Utilities"),
            Kind(name: "Loan payment", symbol: "banknote"),
            Kind(name: "Subscription", symbol: "play.rectangle"),
            Kind(name: "Other", symbol: "plus")
        ]

        var body: some View {
            let payday = app.snapshot.nextIncomeDate
            StepPage(title: payday.map { "Any bills before \(app.day($0))?" } ?? "Any regular bills?",
                     detail: "They're set aside first, so what's left is really yours to spend. Add more any time in Bills.") {
                VStack(alignment: .leading, spacing: 20) {
                    let added = firstOfEach(app.bills)
                    if !added.isEmpty {
                        Divided(items: added) { bill in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bill.name).rdText(.cardTitle).lineLimit(1)
                                    Text("Monthly, next on \(app.day(bill.due))").rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Text(private: app.money(bill.expected)).rdText(.figure)
                            }
                            .frame(minHeight: 62)
                        }
                        .padding(.horizontal, 16).rdPanel(padding: 0)
                    }
                    if adding {
                        editor
                    } else {
                        FlowChips(kinds: Self.kinds) { kind in
                            problem = nil
                            name = kind.name == "Other" ? "" : kind.name
                            category = kind.category
                            amount = ""
                            due = Self.firstOfNextMonth
                            adding = true
                        }
                    }
                }
            } actions: {
                if !adding {
                    Button(app.bills.isEmpty ? "No bills for now" : "Continue", action: next)
                        .buttonStyle(app.bills.isEmpty ? AnyButtonStyle(QuietButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                        .accessibilityIdentifier("continue")
                } else {
                    Button("Add bill", action: add).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addBill")
                    Button("Cancel") { adding = false; problem = nil }.buttonStyle(QuietButtonStyle())
                }
            }
        }

        /// One row per bill: its next due date, not every month ahead
        private func firstOfEach(_ bills: [Bill]) -> [Bill] {
            var seen = Set<UUID>()
            return bills.sorted { $0.due < $1.due }.filter { seen.insert($0.itemId).inserted }
        }

        private static var firstOfNextMonth: Date {
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            return cal.date(byAdding: .month, value: 1, to: start)!
        }

        private var editor: some View {
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Name") {
                    TextField("e.g. Gym", text: $name).accessibilityIdentifier("billName")
                }
                DateRow(label: "Next due", date: $due)
                AmountBox(label: "Amount each month", text: $amount, identifier: "billAmount", keyboardDone: false)
                Problem(text: problem)
            }
        }

        private func add() {
            let title = name.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { problem = "Give the bill a name."; return }
            guard let value = app.parse(amount), value.isPositive else { problem = "Enter an amount greater than zero."; return }
            let s = app.snapshot
            let item = PlannedItem(name: title, direction: .outflow, amount: value,
                                   schedule: Schedule(start: app.calendar.startOfDay(for: due), frequency: .monthly(every: 1)),
                                   accountId: s.accounts.first { $0.spendable }?.id,
                                   categoryId: category.flatMap { name in s.expenseCategories.first { $0.name == name }?.id })
            do {
                try app.store.savePlannedItem(item)
                withAnimation { adding = false }
            } catch { problem = StoreError.from(error).errorDescription }
        }

        /// The common bills as tappable chips, wrapping onto as many lines as they need
        private struct FlowChips: View {
            let kinds: [Kind]
            let pick: (Kind) -> Void

            var body: some View {
                Wrap(spacing: 8) {
                    ForEach(kinds) { kind in
                        Button { pick(kind) } label: {
                            Label(kind.name, systemImage: kind.symbol)
                                .rdText(.label)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.foreground)
                    }
                }
            }
        }
    }

    /// Lays its children out left to right, starting a new line when one is full
    private struct Wrap: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rows = arrange(width: proposal.width ?? .infinity, subviews)
            return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                          height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var y = bounds.minY
            for row in arrange(width: bounds.width, subviews) {
                var x = bounds.minX
                for i in row.items {
                    let size = subviews[i].sizeThatFits(.unspecified)
                    subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
            var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
            var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
            for (i, view) in subviews.enumerated() {
                let size = view.sizeThatFits(.unspecified)
                let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
                if needed > width && !current.items.isEmpty {
                    rows.append(current)
                    current = ([i], size.width, size.height)
                } else {
                    current = (current.items + [i], needed, max(current.height, size.height))
                }
            }
            if !current.items.isEmpty { rows.append(current) }
            return rows
        }
    }

    /// The payoff: what's safe to spend, worked out from the answers
    private struct DoneStep: View {
        @Environment(AppModel.self) private var app
        let back: () -> Void
        let finish: () -> Void

        var body: some View {
            let result = app.snapshot.safeToSpend()
            let amount = result.amount ?? .zero(app.currency)
            let payday = app.snapshot.nextIncomeDate
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                Text(payday.map { "Safe to spend until \(app.day($0))" } ?? "Safe to spend this month")
                    .rdText(.detailStrong).foregroundStyle(Theme.muted)
                Text(private: amount.isNegative ? "Short by \(app.money(amount.magnitude))" : app.money(amount))
                    .rdText(.display)
                    .accessibilityIdentifier("setupSafeToSpend")
                Text(amount.isNegative
                     ? "Your bills before payday need more than you have. Home shows what you can do."
                     : result.obligationsTotal.isPositive
                        ? "Your bills are already set aside. This is the big number on Home, and it updates as you spend."
                        : "This is the big number on Home, and it updates as you spend.")
                    .rdText(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Go to Home", action: finish).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("finish")
                Button("Back", action: back).buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
