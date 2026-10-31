//
//  RedesignSheets.swift
//  Nokael Money
//
//  The sheet that opens over the tabs and what each case shows, the form
//  parts every sheet uses, the safe-to-spend breakdown and "What happened?".
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct SheetScreen: View {
        let sheet: Sheet
        @Environment(AppModel.self) private var app

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if app.path.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { app.close() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Go back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.close() } label: { Image(systemName: "xmark").foregroundStyle(Theme.muted) }
                        .accessibilityLabel("Close")
                }
            }
        }

        private var title: String {
            switch sheet {
            case .breakdown: "Safe to spend"
            case .whatHappened: "What happened?"
            case .review: "Check automatic entries"
            case .schedules: "Regular bills and income"
            case .entry(.expense): "Add expense"
            case .entry(.income): "Add income"
            case .entry(.transfer): "Transfer money"
            case .entry(.adjustment): "Fix a balance"
            case .entry(.bill): "Add bill"
            case .entry(.expectedIncome): "Expected income"
            case .editEntry: "Edit transaction"
            case .editBill: "Edit"
            case .account(let id): app.accountLabel(id)
            case .category(let id): app.hidesDetails ? "Category" : app.category(id)?.name ?? "Category"
            case .bill(let id): app.bill(id).map { app.name(of: $0) } ?? "Bill details"
            case .link: "Link a payment"
            case .billLink: "Is this the payment?"
            case .transaction: "Transaction details"
            case .payDebt(let id, _): "Pay \(app.accountLabel(id))"
            case .editDebtPayment: "Edit payment"
            case .entryAsDebtPayment: "Card or loan payment"
            case .debtTerms: "Rate and payment"
            case .reconcile: "Check against a statement"
            case .accountType: "Change type"
            case .startingAmount: "Starting amount"
            case .lend(_, .lend): "Lend more"
            case .lend(_, .repaid): "They paid some back"
            case .lend(_, .forgive): "They won't pay it back"
            case .importStatement: "Import a statement"
            case .newAccount(let loan): loan ? "Add a loan or card" : "Add account"
            case .newCategory: "New budget category"
            case .editCategory: "Edit category"
            case .moveMoney: "Move money"
            case .loansInCategory: "Loans in this category"
            case .goal(let id): app.hidesDetails ? "Goal" : app.snapshot.reserves.first { $0.id == id }?.name ?? "Goal"
            case .reserve(let id, let goal): id == nil ? (goal ? "New savings goal" : "Set money aside") : goal ? "Edit goal" : "Money set aside"
            case .goalMoney(_, let adding): adding ? "Add money" : "Take money out"
            case .payday: "Payday"
            case .help: "Help & support"
            case .intelligence: "Apple Intelligence"
            case .ask: "Ask about your money"
            case .paywall: "Nokael Plus"
            }
        }

        @ViewBuilder private var content: some View {
            switch sheet {
            case .breakdown: Breakdown()
            case .whatHappened: WhatHappened()
            case .review: ReviewList()
            case .schedules: Schedules()
            case .entry(.bill): BillForm(direction: .outflow, editing: nil)
            case .entry(.expectedIncome): BillForm(direction: .inflow, editing: nil)
            case .entry(let kind): EntryFormView(kind: kind)
            case .editEntry(let id): if let r = app.entry(id) { EntryFormView(editing: r) }
            case .editBill(let id): if let item = app.item(id) { BillForm(direction: item.direction, editing: item) }
            case .account(let id): if let a = app.account(id) { AccountPage(account: a) }
            case .bill(let id): if let b = app.bill(id) { BillPage(bill: b) }
            case .link(let id): if let b = app.bill(id) { LinkPayment(bill: b) }
            case .billLink(let id): BillLinkPage(occurrenceId: id)
            case .category(let id): if let c = app.category(id) { CategoryPage(category: c) }
            case .transaction(let id): if let t = app.transaction(id) { TransactionPage(t: t) }
            case .payDebt(let id, let occ): if let debt = app.record(id) { PayDebtForm(debt: debt, occurrenceId: occ) }
            case .editDebtPayment(let id):
                if let r = app.entry(id), let parts = app.store.debtPaymentParts(r) { PayDebtForm(debt: parts.debt, editing: r) }
            case .entryAsDebtPayment(let id): if let r = app.entry(id) { DebtChoice(replacing: r) }
            case .debtTerms(let id): if let debt = app.record(id) { DebtTermsForm(debt: debt) }
            case .reconcile(let id): if let a = app.record(id) { ReconcileForm(account: a) }
            case .accountType(let id): if let a = app.record(id) { AccountTypeForm(account: a) }
            case .startingAmount(let id): if let a = app.record(id) { StartingAmountForm(account: a) }
            case .lend(let id, let action): if let a = app.record(id) { LendForm(person: a, action: action) }
            case .importStatement(let id): ImportStatement(accountId: id)
            case .newAccount(let loan): AddAccountForm(startsWithLoan: loan)
            case .newCategory: CategoryForm(editing: nil)
            case .editCategory(let id): CategoryForm(editing: app.record(id))
            case .moveMoney(let id): MoveMoneyForm(destination: id)
            case .loansInCategory(let id): LoansInCategory(categoryId: id)
            case .goal(let id): if let g = app.snapshot.reserves.first(where: { $0.id == id }) { GoalPage(goal: g) }
            case .reserve(let id, let goal): ReserveForm(editing: app.snapshot.reserves.first { $0.id == id }, asGoal: goal)
            case .goalMoney(let id, let adding): if let g = app.snapshot.reserves.first(where: { $0.id == id }) { GoalMoneyForm(goal: g, adding: adding) }
            case .payday: PaydayForm()
            case .help: HelpPage()
            case .intelligence: IntelligencePage()
            case .ask: AskPage()
            case .paywall(let feature): PaywallPage(feature: feature)
            }
        }
    }
}

// MARK: - Form parts

extension Redesign {
    /// The amount box at the top of every form. In Privacy Mode the digits typed show as dots until the person
    /// taps Show; that reveal belongs to this form alone and is gone once the form closes.
    struct AmountBox: View {
        let label: String
        @Binding var text: String
        /// What's owed, shown beneath as "… outstanding"
        var owed: Decimal?
        var autofocus = true
        var identifier = "amountField"
        @Environment(AppModel.self) private var app
        @FocusState private var focused: Bool
        @State private var revealed = false

        private var concealed: Bool { app.hidesAmounts && !revealed }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label).rdText(.detail).foregroundStyle(Theme.muted)
                    Spacer()
                    if app.hidesAmounts {
                        Button { revealed.toggle() } label: {
                            Image(systemName: revealed ? "eye" : "eye.slash").font(.system(size: 14))
                                .frame(width: 44, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel(revealed ? "Hide amount" : "Show amount")
                    }
                }
                // A secure field while concealed, as with a password's Show button; the typed text is the same either way
                Group {
                    if concealed { SecureField("0.00", text: $text) } else { TextField("0.00", text: $text) }
                }
                .rdText(.display)
                .keyboardType(.decimalPad)
                .focused($focused)
                .accessibilityIdentifier(identifier)
                .toolbar {
                    // The number pad has no return key; this puts the form's buttons back in reach
                    if focused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }.fontWeight(.semibold)
                        }
                    }
                }
                .onChange(of: concealed) { focused = true }
                if let owed {
                    Text(private: "\(app.money(owed, revealed: revealed)) outstanding").rdText(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear { if autofocus { focused = true } }
        }
    }

    /// A labelled field in the form style: caption above, rounded box below
    struct Field<Content: View>: View {
        let label: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).rdText(.detail)
                content
                    .rdText(.body)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
            }
        }
    }

    /// A menu of options inside a Field; `shown` says how each reads
    struct Choice<Value: Hashable>: View {
        @Binding var value: Value
        let options: [Value]
        let shown: (Value) -> String

        var body: some View {
            Menu {
                Picker("", selection: $value) { ForEach(options, id: \.self) { Text(shown($0)).tag($0) } }
            } label: {
                HStack { Text(shown(value)).lineLimit(1); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                    .foregroundStyle(Theme.foreground)
                    .contentShape(Rectangle())
            }
        }
    }

    /// An account picker over the accounts given, read through Privacy Mode
    struct AccountChoice: View {
        @Environment(AppModel.self) private var app
        let label: String
        @Binding var selection: UUID?
        let accounts: [Account]

        var body: some View {
            Field(label: label) {
                Choice(value: $selection, options: accounts.map { Optional($0.id) }) { id in
                    id == nil ? "Choose" : app.accountLabel(id)
                }
            }
            .accessibilityLabel("\(label), \(selection == nil ? "Choose" : app.accountLabel(selection))")
        }
    }

    /// A category picker, most used first
    struct CategoryChoice: View {
        @Environment(AppModel.self) private var app
        let label: String
        @Binding var selection: UUID?
        let categories: [LedgerAccountRecord]
        var allowsNone = false

        var body: some View {
            Field(label: label) {
                Choice(value: $selection, options: (allowsNone ? [nil] : []) + categories.map { Optional($0.id) }) { name($0) }
            }
            .accessibilityLabel("\(label), \(name(selection))")
        }

        private func name(_ id: UUID?) -> String {
            guard let id else { return allowsNone ? "None" : "Choose" }
            return app.hidesDetails ? "Category" : categories.first { $0.id == id }?.name ?? app.record(id)?.name ?? "Choose"
        }
    }

    struct ToggleRow: View {
        let title: String
        var detail: String?
        @Binding var isOn: Bool

        var body: some View {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).rdText(.body)
                    if let detail {
                        Text(private: detail).rdText(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Theme.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 54)
            .rdPanel(padding: 0)
        }
    }

    struct Problem: View {
        let text: String?
        var body: some View {
            if let text {
                Label(text, systemImage: "exclamationmark.circle").rdText(.detail).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Detail rows on a card, as on the bill and account pages
    struct DetailCard<Content: View>: View {
        @ViewBuilder let content: Content
        var body: some View {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border.opacity(0.6)))
        }
    }

    /// A note in a quiet outlined box, for what a form will and won't do
    @MainActor static func explainer(_ text: String) -> some View {
        Text(private: text).rdText(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
    }

    static let frequencies: [Frequency] = [.weekly(every: 1), .weekly(every: 2), .monthly(every: 1), .quarterly, .annually]
}

// MARK: - Safe to spend

extension Redesign {
    struct Breakdown: View {
        @Environment(AppModel.self) private var app
        @State private var period = "Until payday"
        @State private var pickedDate = Date()
        @State private var bufferText = ""

        private var end: Date {
            let s = app.snapshot
            switch period {
            case "7 days": return s.endOfDay(s.calendar.date(byAdding: .day, value: 7, to: s.today) ?? s.today)
            case "Month end":
                let start = BudgetMonth.start(of: s.monthKey, calendar: s.calendar) ?? s.today
                return s.endOfDay(s.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? s.today)
            case "A date": return s.endOfDay(pickedDate)
            default: return s.defaultPeriodEnd
            }
        }

        var body: some View {
            let result = app.snapshot.safeToSpend(through: end)
            let safe = max(0, result.amount?.decimal ?? 0)
            let short = max(0, -(result.amount?.decimal ?? 0))
            Text("A clearer picture of what you can comfortably spend, after your upcoming commitments.")
                .rdText(.body).foregroundStyle(Theme.muted).lineSpacing(3)
            Pills(options: ["Until payday", "7 days", "Month end", "A date"], selection: $period).padding(.top, 16)
            if period == "A date" {
                Field(label: "Through") {
                    DatePicker("", selection: $pickedDate, in: app.today..., displayedComponents: .date).labelsHidden()
                }
                .padding(.top, 12)
            }
            VStack(spacing: 8) {
                Text("Safe to spend").rdText(.detail).foregroundStyle(Theme.primary)
                if result.amount == nil { Text("—").rdText(.display) } else {
                    app.amount(safe).rdText(.display).minimumScaleFactor(0.6).lineLimit(1)
                }
                Text("through \(app.fullDay(result.periodEnd))").rdText(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 20)
            status(result).padding(.top, 12).padding(.bottom, 20)

            VStack(spacing: 0) {
                ForEach(result.spendable) { item in
                    DetailRow(label: app.accountLabel(item.sourceIds.first), value: app.money(item.amount))
                    Redesign.hairline
                }
                DetailRow(label: "Total cash", value: app.money(result.spendableTotal))
                Redesign.hairline
                DetailRow(label: "Less unpaid commitments", value: app.money(result.obligationsTotal))
                lines(result.obligations)
                if !result.reserves.isEmpty {
                    Redesign.hairline
                    DetailRow(label: "Less money set aside", value: app.money(result.reservesTotal))
                    lines(result.reserves)
                }
                if !result.categoryReservations.isEmpty {
                    Redesign.hairline
                    DetailRow(label: "Less budget kept for essentials", value: app.money(result.categoryReservationsTotal))
                    lines(result.categoryReservations)
                }
                if result.buffer.isPositive {
                    Redesign.hairline
                    DetailRow(label: "Less your safety buffer", value: app.money(result.buffer))
                }
                Redesign.hairline
                DetailRow(label: "Amount still to cover", value: app.money(short))
            }

            Field(label: "Safety buffer (kept back every time)") {
                TextField("0", text: $bufferText).keyboardType(.decimalPad)
                    .onSubmit(saveBuffer)
            }
            .padding(.top, 20)
            .onChange(of: bufferText) { saveBuffer() }

            Button { app.open(.reserve(nil, goal: false)) } label: { Label("Set money aside", systemImage: "lock") }
                .buttonStyle(QuietButtonStyle()).padding(.top, 16)

            projection.padding(.top, 20)

            Redesign.footnote("Safe to spend never falls below zero. Loan balances aren't cash. Your budget is a plan, so we don't subtract it again on top of these bills.")
                .padding(.vertical, 20)
            Button { app.go(.bills) } label: { HStack { Text("Review upcoming bills"); Image(systemName: "arrow.right") } }
                .buttonStyle(PrimaryButtonStyle())
                .onAppear { bufferText = app.editable(app.store.settings.buffer.decimal) }
        }

        private func lines(_ items: [BreakdownItem]) -> some View {
            ForEach(items) { item in
                HStack { Text(app.hidesDetails ? "Commitment" : item.label); Spacer(); Text(private: app.money(item.amount)) }
                    .rdText(.caption).monospacedDigit().foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 7)
            }
        }

        @ViewBuilder private func status(_ result: SafeToSpend) -> some View {
            let words: [String] = result.statuses.compactMap {
                switch $0 {
                case .reliable: nil
                case .estimated: "Includes estimated bills."
                case .incompleteSetup: "Add an account you spend from to see this."
                case .stale(let names): app.hidesAccountNames ? "Some balances haven't been checked lately." : "Not checked lately: \(names.joined(separator: ", "))."
                case .shortfall: "Your commitments are more than your spendable money."
                }
            }
            if words.isEmpty {
                Label("Every balance is up to date.", systemImage: "checkmark.seal").rdText(.caption).foregroundStyle(Theme.primary)
            } else {
                Label(words.joined(separator: " "), systemImage: "info.circle").rdText(.caption).foregroundStyle(Theme.muted)
            }
        }

        @ViewBuilder private var projection: some View {
            let s = app.snapshot
            if s.items.contains(where: { $0.direction == .inflow }) {
                let p = s.safeToSpendCalculator().project(today: s.today, to: end)
                VStack(alignment: .leading, spacing: 8) {
                    Text("If expected income arrives").rdText(.detailStrong)
                    HStack {
                        Text("By \(app.fullDay(p.date))").rdText(.caption).foregroundStyle(Theme.muted)
                        Spacer()
                        app.amount(max(0, p.amount.decimal)).rdText(.amount)
                    }
                    ForEach(p.expectedIncome) { item in
                        HStack { Text("+ " + (app.hidesDetails ? "Income" : item.label)); Spacer(); Text(private: app.money(item.amount)) }
                            .rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    Redesign.footnote(p.assumptions.joined(separator: ". ") + ".")
                }
                .rdPanel()
            }
        }

        private func saveBuffer() {
            let value = bufferText.isEmpty ? Money.zero(app.currency) : app.parse(bufferText)
            guard let value, !value.isNegative, value.minorUnits != app.store.settings.bufferMinor else { return }
            try? app.store.updateSettings { $0.bufferMinor = value.minorUnits }
        }
    }
}

// MARK: - What happened?

extension Redesign {
    /// The + button's More…: every kind of event in plain words, each opening the one form for it
    struct WhatHappened: View {
        @Environment(AppModel.self) private var app
        @State private var showDebts = false
        @State private var showBills = false

        var body: some View {
            let s = app.snapshot
            let salary = PaydayPlan.salaryItem(s)
            let debts = s.debts
            let end = s.calendar.date(byAdding: .day, value: 31, to: s.today) ?? s.today
            let bills = app.bills.filter { $0.isOpen && $0.due <= end }.prefix(6)
            VStack(spacing: 10) {
                if let salary {
                    choice("I got my \(app.hidesDetails ? "salary" : salary.name.lowercased())", "Record pay, plan the month and fill goals",
                           "arrow.down.left", id: "add-I got my salary") { app.open(.payday) }
                }
                choice("I spent money", "A purchase, a meal, a bill paid by card", "basket", warm: true, id: "add-I spent money") {
                    app.open(.entry(.expense))
                }
                choice("I received money", "Salary, a refund, money from someone", "arrow.down.left", id: "add-I received money") {
                    app.open(.entry(.income))
                }
                choice("I paid a bill", "Rent, phone, electricity…", "doc.text", id: "add-I paid a bill") {
                    if bills.isEmpty { app.open(.entry(.expense)) } else { withAnimation(.snappy) { showBills.toggle() } }
                }
                if showBills {
                    VStack(spacing: 0) { Divided(items: Array(bills)) { BillRow(bill: $0, compact: true) } }.rdPanel(padding: 14)
                }
                choice("I paid a loan or credit card", "Splits off the interest for you", "creditcard", id: "add-I paid a loan or credit card") {
                    if debts.isEmpty { app.open(.newAccount(loan: true)) }
                    else if debts.count == 1 { app.open(.payDebt(debts[0].id, occurrence: nil)) }
                    else { withAnimation(.snappy) { showDebts.toggle() } }
                }
                if showDebts {
                    VStack(spacing: 0) {
                        Divided(items: debts.map { app.account($0.id) }.compactMap { $0 }) { a in
                            Button { app.open(.payDebt(a.id, occurrence: nil)) } label: {
                                HStack {
                                    Text(app.accountLabel(a.id)).rdText(.cardTitle)
                                    Spacer()
                                    Text(private: "owe \(app.money(a.balance))").rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                .frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .rdPanel(padding: 14)
                }
                choice("I moved money between my accounts", "Nothing spent, nothing earned", "arrow.up.arrow.down",
                       id: "add-I moved money between my accounts") { app.open(.entry(.transfer)) }
                choice("I have a loan or credit card", "Add what you owe and the monthly payment", "building.columns",
                       id: "add-I have a loan or credit card") { app.open(.newAccount(loan: true)) }
                choice("A balance is wrong", "Set an account to what your bank shows", "slider.horizontal.3",
                       id: "add-A balance is wrong") { app.open(.entry(.adjustment)) }
                Button { app.open(.help) } label: {
                    Label("Not sure? Ask the guide", systemImage: "questionmark.circle")
                        .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 6)
            }
        }

        private func choice(_ title: String, _ sub: String, _ symbol: String, warm: Bool = false, id: String,
                            action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: 16) {
                    IconBox(symbol: symbol, tone: warm ? .warm : .green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).rdText(.cardTitle).multilineTextAlignment(.leading)
                        Text(sub).rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 56)
                .rdPanel()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
    }
}
