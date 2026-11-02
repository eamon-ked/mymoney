//
//  RedesignAccounts.swift
//  Nokael Money
//
//  An account's page, in three shapes: money you hold, a card or loan you
//  owe, and a person: money lent to them or borrowed from them. Adding accounts, cards and loans; paying
//  a card or loan with the interest split off; and the account's tools:
//  checking against a statement, changing its type, fixing what it started
//  with, and its settings.
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct AccountPage: View {
        let account: Account
        @Environment(AppModel.self) private var app
        @State private var section = "Transactions"
        @State private var name = ""
        @State private var confirmArchive = false

        var body: some View {
            let record = app.record(account.id)
            VStack(alignment: .leading, spacing: 0) {
                if account.kind == .creditCard {
                    CreditCardFace(balance: app.amount(account.balance), holder: app.isEnhanced ? "" : app.holder,
                                   number: app.hidesAccountNames || account.number.isEmpty ? nil : account.number)
                        .padding(.bottom, 20)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        IconBox(symbol: Redesign.kindSymbol(account.kind), small: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(app.accountLabel(account.id)).rdText(.detailStrong)
                            Text(app.reference(of: account) + (account.archived ? " · Archived" : "")).rdText(.caption).tracking(1).foregroundStyle(Theme.muted)
                        }
                    }
                    if app.owedNotSet(account.id) {
                        Button { app.open(.finishLoan(account.id)) } label: {
                            Text("Add what's owed").rdText(.balance).foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.plain).padding(.top, 24)
                        Text("Amount owed not set yet")
                            .rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
                    } else {
                        app.amount(account.shown).rdText(.balance).padding(.top, 24)
                        Text(account.caption)
                            .rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                    if let record { Text(checkedLine(record)).rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 2) }
                    if !account.isLiability && account.kind != .lent && record?.spendable == true {
                        HStack(alignment: .top) {
                            figure(app.money(account.balance), "Total balance")
                            figure(app.money(min(app.safe, account.balance)), "Safe to spend")
                        }
                        .padding(.top, 24)
                    }
                    Redesign.hairline.padding(.top, 24)
                    HStack {
                        if account.isLiability {
                            action("Payment", "arrow.up.right", id: "payDebt") { app.open(.payDebt(account.id, occurrence: nil)) }
                                .disabled(account.balance <= 0)
                            action("Terms", "percent", id: "editDebt") { app.open(.debtTerms(account.id)) }
                        } else if account.kind == .lent && account.youOwe {
                            action("Pay back", "arrow.up.right", id: "payBack") { app.open(.lend(account.id, .payBack)) }
                            action("Borrow more", "arrow.down.left", id: "borrowMore") { app.open(.lend(account.id, .borrow)) }
                        } else if account.kind == .lent {
                            action(account.balance > 0 ? "Lend more" : "Lend", "arrow.up.right", id: "lendMore") { app.open(.lend(account.id, .lend)) }
                            if account.balance > 0 {
                                action("Paid back", "arrow.down.left", id: "paidBack") { app.open(.lend(account.id, .repaid)) }
                            } else {
                                action("Borrow", "arrow.down.left", id: "borrowMore") { app.open(.lend(account.id, .borrow)) }
                            }
                        } else {
                            action("Transfer", "arrow.up.arrow.down", id: "transfer") { app.open(.entry(.transfer)) }
                            action("Check", "checkmark.seal", id: "reconcile") { app.open(.reconcile(account.id)) }
                        }
                        Menu { moreMenu(record) } label: { actionLabel("More", "ellipsis") }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("More")
                    }
                    .padding(.top, 16)
                }
                .rdPanel(padding: 20)

                if account.isLiability, let record { DebtSection(debt: record) }
                if account.kind == .lent && account.balance > 0 {
                    Button("They won't pay it back") { app.open(.lend(account.id, .forgive)) }
                        .buttonStyle(QuietButtonStyle()).padding(.top, 16)
                        .accessibilityIdentifier("forgive")
                }

                HStack(spacing: 0) {
                    ForEach(["Transactions", "Details"], id: \.self) { s in
                        Button { section = s } label: {
                            Text(s).rdText(.captionStrong)
                                .foregroundStyle(section == s ? Theme.primary : Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(alignment: .bottom) { Rectangle().fill(section == s ? Theme.primary : .clear).frame(height: 1.5) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
                .padding(.top, 24)
                .padding(.bottom, 8)

                if section == "Transactions" {
                    transactions
                } else if let record {
                    details(record)
                }
            }
            .confirmationDialog("Archive \(app.accountLabel(account.id))?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive account", role: .destructive) { setArchived(true) }
            } message: { Text("It leaves your lists and totals. Its history stays, and you can restore it from Accounts.") }
        }

        private func checkedLine(_ r: LedgerAccountRecord) -> String {
            if let d = r.lastReconciledAt { return "Checked against a statement \(d.formatted(.relative(presentation: .named)))" }
            if let d = app.snapshot.lastConfirmed[r.id] { return "Last entry \(d.formatted(.relative(presentation: .named)))" }
            return "No entries yet"
        }

        @ViewBuilder private var transactions: some View {
            let running = app.snapshot.ledger.runningBalance(of: account.id).reversed()
            let after = Dictionary(running.map { ($0.entry.id, $0.balance) }, uniquingKeysWith: { a, _ in a })
            let items = app.transactions(touching: account.id)
            if items.isEmpty { EmptyNote(text: "No transactions in this account yet.") }
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(150).enumerated()), id: \.element.id) { i, t in
                    VStack(alignment: .trailing, spacing: 0) {
                        TransactionRow(t: t)
                        if let balance = after[t.id] {
                            Text(private: "Balance after \(app.money(account.isLiability ? balance.negated : balance))")
                                .rdText(.caption).foregroundStyle(Theme.muted).padding(.bottom, 10).padding(.trailing, 4)
                        }
                    }
                    if i < min(items.count, 150) - 1 { Redesign.hairline }
                }
            }
        }

        private func details(_ r: LedgerAccountRecord) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Field(label: "Name") {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(rename)
                        .onAppear { name = r.name }
                }
                DetailCard {
                    DetailRow(label: "Type", value: Redesign.kindName(r.kind))
                    DetailRow(label: "Number", value: app.hidesAccountNames ? "Hidden" : account.number.isEmpty ? "Not given" : "•••• \(account.number)")
                    if let bank = r.institution, !bank.isEmpty { DetailRow(label: "Bank", value: app.hidesAccountNames ? "Hidden" : bank) }
                    DetailRow(label: "Currency", value: r.currency)
                }
                if r.kind == .lent { PayBackBy(person: r) }
                ToggleRow(title: "Counts in net worth", isOn: setting(r, \.includeInNetWorth))
                if r.kind.isAsset && r.kind != .lent {
                    ToggleRow(title: "Money I can spend", detail: "Counts towards safe to spend.", isOn: setting(r, \.spendable))
                }
                if r.kind != .loan || r.onBudget {
                    ToggleRow(title: "Part of my budget",
                              detail: r.kind == .creditCard ? "Spending on the card counts in your budget." : "Money here can be given a job in Budget.",
                              isOn: setting(r, \.onBudget))
                }
            }
        }

        private func setting(_ r: LedgerAccountRecord, _ key: ReferenceWritableKeyPath<LedgerAccountRecord, Bool>) -> Binding<Bool> {
            Binding(get: { r[keyPath: key] }, set: { value in
                app.attempt(closing: false) { try app.store.updateAccount(r) { $0[keyPath: key] = value } }
                    .map { app.toast = Toast(message: $0, isError: true) }
            })
        }

        private func rename() {
            guard let r = app.record(account.id) else { return }
            let new = name.trimmingCharacters(in: .whitespaces)
            guard !new.isEmpty, new != r.name else { return }
            app.attempt("Renamed.", closing: false) { try app.store.updateAccount(r) { $0.name = new } }
                .map { app.toast = Toast(message: $0, isError: true) }
        }

        private func setArchived(_ archived: Bool) {
            guard let r = app.record(account.id) else { return }
            app.attempt(archived ? "Account archived." : "Account restored.") { try app.store.updateAccount(r) { $0.archived = archived } }
                .map { app.toast = Toast(message: $0, isError: true) }
        }

        @ViewBuilder private func moreMenu(_ r: LedgerAccountRecord?) -> some View {
            if account.kind.holdsMoney || account.isLiability {
                Button("Check against a statement") { app.open(.reconcile(account.id)) }
                Button("Import a statement (CSV)") { app.open(.importStatement(account.id)) }
                    .accessibilityIdentifier("importStatement")
            }
            Button("Change type") { app.open(.accountType(account.id)) }
            if app.store.openingEntry(for: account.id) != nil {
                Button("Fix starting amount") { app.open(.startingAmount(account.id)) }
            }
            Button("Rename and settings") { section = "Details" }
            if account.archived {
                Button("Restore account") { setArchived(false) }
            } else {
                Button("Archive account", role: .destructive) { confirmArchive = true }
            }
        }

        private func figure(_ value: String, _ label: String) -> some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(private: value).rdText(.stat)
                Text(label).rdText(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func action(_ label: String, _ symbol: String, id: String, _ run: @escaping () -> Void) -> some View {
            Button(action: run) { actionLabel(label, symbol) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(id)
        }

        private func actionLabel(_ label: String, _ symbol: String) -> some View {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 15))
                    .frame(width: 38, height: 38).foregroundStyle(Theme.primary).background(Theme.secondary, in: Circle())
                Text(label).rdText(.caption).foregroundStyle(Theme.foreground)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A card's or loan's terms, payoff and what paying extra would save
    struct DebtSection: View {
        let debt: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var extraText = ""

        var body: some View {
            let s = app.snapshot
            let item = s.paymentItem(for: debt.id)
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "Terms", action: debt.debtTerms == nil ? "Add" : "Edit") { app.open(.debtTerms(debt.id)) }
                    .padding(.top, 24)
                if let terms = debt.debtTerms {
                    DetailCard {
                        DetailRow(label: "Interest", value: "\(NSDecimalNumber(decimal: terms.annualRatePercent).stringValue)% a year")
                        DetailRow(label: "Monthly payment", value: app.money(terms.monthlyPayment))
                        DetailRow(label: "Due on", value: terms.dueDay.map { "Day \($0)" } ?? "Not set")
                        DetailRow(label: "Paid from", value: item.map { app.accountLabel($0.accountId) } ?? "Not in your bills")
                        DetailRow(label: "Next payment", value: app.fullDay(s.nextPaymentDate(for: debt)))
                    }
                    if let payoff = s.payoff(for: debt) {
                        SectionHeading(title: "Payoff").padding(.top, 24)
                        DetailCard { payoffRows(payoff) }
                        planner(terms)
                    }
                } else {
                    Button { app.open(.debtTerms(debt.id)) } label: {
                        Redesign.explainer("Add the interest rate and monthly payment to see when it's paid off, and to have the payment kept aside each month.")
                    }
                    .buttonStyle(.plain)
                }
                Redesign.footnote(debt.kind == .creditCard
                    ? "Available credit is money you can borrow, not cash you own. This balance is excluded from safe to spend."
                    : "This is money you owe, not available cash. Unpaid repayments are already included in your upcoming commitments.")
                    .padding(.top, 16).padding(.horizontal, 4)
            }
        }

        @ViewBuilder private func payoffRows(_ payoff: Payoff) -> some View {
            switch payoff {
            case .alreadyPaidOff: DetailRow(label: "Status", value: "Paid off")
            case .paidOff(let months, let last, let interest, let final):
                DetailRow(label: "Debt-free", value: last.formatted(.dateTime.month(.wide).year()))
                DetailRow(label: "Payments left", value: "\(months)")
                DetailRow(label: "Interest still to pay", value: app.money(interest))
                DetailRow(label: "Last payment", value: app.money(final))
            case .never(let interest):
                Redesign.footnote("The payment doesn't cover the \(app.money(interest)) of interest added each month, so what you owe never falls. Pay more to bring it down.")
                    .padding(.vertical, 14)
            case .beyondHorizon:
                Redesign.footnote("At this payment it takes more than 50 years to pay off.").padding(.vertical, 14)
            }
        }

        @ViewBuilder private func planner(_ terms: DebtTerms) -> some View {
            if app.isPlus {
                Field(label: "Pay extra each month") {
                    TextField("0", text: $extraText).keyboardType(.decimalPad).accessibilityIdentifier("extraPayment")
                }
                .padding(.top, 16)
                if let extra = app.parse(extraText), extra.isPositive,
                   case .paidOff(let m0, _, let i0, _)? = app.snapshot.payoff(for: debt),
                   case .paidOff(let m1, _, let i1, _)? = app.snapshot.payoff(for: debt, extra: extra) {
                    Text(private: "Paid off \(m0 - m1) month\(m0 - m1 == 1 ? "" : "s") sooner, with \(app.money(i0 - i1)) less interest.")
                        .rdText(.detail).foregroundStyle(Theme.primary).padding(.top, 8)
                }
            } else {
                Button { app.open(.paywall(.payoffPlanner)) } label: {
                    HStack { Text("See what paying extra saves"); PlusTag(); Spacer(); Image(systemName: "chevron.right") }
                        .rdText(.detail).foregroundStyle(Theme.primary).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Adding accounts, cards and loans

extension Redesign {
    struct AddAccountForm: View {
        let startsWithLoan: Bool
        var startKind: AccountKind?
        @Environment(AppModel.self) private var app
        @State private var kind: AccountKind = .bank
        @State private var name = ""
        @State private var balance = ""
        @State private var institution = ""
        @State private var payment = ""
        @State private var rate = ""
        @State private var dueDay: Int?
        @State private var fundingId: UUID?
        @State private var categoryId: UUID?
        @State private var iOwe = false
        @State private var problem: String?

        private let kinds: [AccountKind] = [.bank, .cash, .savings, .creditCard, .loan, .investment, .lent, .otherAsset]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Type") {
                    Choice(value: $kind, options: kinds) { Redesign.kindName($0) }
                }
                if kind == .lent {
                    Pills(options: ["They owe me", "I owe them"], selection: Binding(get: { iOwe ? "I owe them" : "They owe me" },
                                                                                   set: { iOwe = $0 == "I owe them" }))
                }
                Field(label: kind == .lent ? "Their name" : "Name") {
                    TextField(kind == .loan ? "e.g. Car loan" : kind == .creditCard ? "e.g. Cashback card" : kind == .cash ? "e.g. Wallet"
                              : kind == .lent ? "e.g. Sam" : "e.g. Everyday account", text: $name)
                        .accessibilityIdentifier(kind.isLiability ? "loanName" : "accountName")
                }
                AmountBox(label: kind.isLiability ? "Owed today in \(app.currency)" : kind == .lent ? (iOwe ? "You owe them, in \(app.currency)" : "They owe you, in \(app.currency)")
                          : "Current balance in \(app.currency)", text: $balance, identifier: kind.isLiability ? "loanOwed" : "openingBalance")
                if kind != .cash && kind != .lent {
                    Field(label: kind.isLiability ? "Bank or lender, with the last four digits (optional)" : "Bank, with the last four digits (optional)") {
                        TextField("e.g. City Bank 4821", text: $institution)
                    }
                }
                if kind.isLiability {
                    Field(label: kind == .creditCard ? "You pay each month (optional)" : "Monthly instalment (optional)") {
                        TextField("0", text: $payment).keyboardType(.decimalPad).accessibilityIdentifier("loanPayment")
                    }
                    Field(label: "Paid on") {
                        Choice(value: $dueDay, options: [nil] + (1...31).map { Optional($0) }) { $0.map { "Day \($0) of the month" } ?? "Not sure" }
                    }
                    if dueDay != nil {
                        AccountChoice(label: "Paid from", selection: $fundingId, accounts: app.moneyAccounts)
                    }
                    Field(label: "Interest rate, % a year (optional)") {
                        TextField("e.g. 4.5", text: $rate).keyboardType(.decimalPad)
                    }
                    if kind == .loan {
                        LoanCategoryChoice(selection: $categoryId)
                    }
                }
                Text(explanation).rdText(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
                Problem(text: problem)
                Button(kind.isLiability ? "Add \(kind == .loan ? "loan" : "card")" : "Add account", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier(kind.isLiability ? "saveLoan" : "addAccount")
            }
            .onAppear {
                if startsWithLoan { kind = .loan } else if let startKind { kind = startKind }
                fundingId = app.moneyAccounts.first { $0.id == app.store.settings.lastUsedAccountId }?.id ?? app.moneyAccounts.first?.id
            }
        }

        private var explanation: String {
            switch kind {
            case .loan: "Not the original loan: what's left to pay. A loan is money you owe, never counted as cash. With a payment day, the payment joins your bills and is kept aside in safe to spend."
            case .creditCard: "The balance from your banking app or statement. Card spending counts as spending; paying the card is a transfer, not new spending."
            case .lent: "A friend or family member: what they owe you, or what you owe them. It counts in your net worth, not in safe to spend."
            case .savings, .investment, .otherAsset: "Counts in your net worth. Savings aren't safe to spend unless you choose that on the account."
            default: "This balance is added to your total cash and safe to spend."
            }
        }

        private func save() {
            problem = nil
            let title = name.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { problem = kind == .lent ? "Add their name." : "Give the account a name."; return }
            guard let owed = balance.isEmpty ? Money.zero(app.currency) : app.parse(balance), !owed.isNegative else {
                problem = kind.isLiability ? "Enter what you owe, or 0." : "Enter the current balance, or 0."; return
            }
            let monthly = payment.isEmpty ? nil : app.parse(payment)
            if !payment.isEmpty && monthly?.isPositive != true { problem = "Enter the monthly payment as a number."; return }
            guard let bps = DebtTerms.rateBps(from: rate.isEmpty ? "0" : rate) else {
                problem = "Enter the yearly rate as a percentage, e.g. 4.5, or leave it empty."; return
            }
            let kind = kind
            problem = app.attempt(kind.isLiability ? "\(kind == .loan ? "Loan" : "Card") added. It isn't counted as cash."
                                  : kind == .lent ? "Added to People." : "Account added.") {
                let r = try app.store.addAccount(name: title, kind: kind, balance: kind == .lent && iOwe ? owed.negated : owed, openingDate: Date(),
                                                 institution: institution.isEmpty ? nil : institution)
                if kind == .loan, categoryId != nil { try app.store.setLoanCategory(categoryId, for: r.id) }
                if kind.isLiability, let monthly {
                    try app.store.saveDebtTerms(DebtTerms(annualRateBps: bps, monthlyPayment: monthly, dueDay: dueDay),
                                                for: r.id, paidFrom: dueDay == nil ? nil : fundingId)
                }
            }
        }
    }

    /// Where a loan's payments count in Budget and Reports
    struct LoanCategoryChoice: View {
        @Binding var selection: UUID?
        @Environment(AppModel.self) private var app

        var body: some View {
            let s = app.snapshot
            let system = Set([FinanceSnapshot.systemCategory("loanPayments", name: "", in: s.accountRecords)?.id,
                              FinanceSnapshot.systemCategory("interest", name: "", in: s.accountRecords)?.id].compactMap { $0 })
            let choices = s.expenseCategories.filter { !system.contains($0.id) && !$0.archived }
            Field(label: "Counts in budget as") {
                Choice(value: $selection, options: [nil] + choices.map { Optional($0.id) }) { id in
                    id.flatMap { id in choices.first { $0.id == id }?.name } ?? "Loan payments"
                }
            }
            .accessibilityIdentifier("loanCategory")
        }
    }
}

// MARK: - Paying a card or loan

extension Redesign {
    /// A payment to a card or loan, split into what comes off the balance, interest and fees.
    /// Also edits a recorded payment, and records an expense again as one.
    struct PayDebtForm: View {
        let debt: LedgerAccountRecord
        var occurrenceId: UUID?
        var editing: EntryRecord?
        var replacing: EntryRecord?
        @Environment(AppModel.self) private var app

        @State private var key = UUID()
        @State private var amount = ""
        @State private var fundingId: UUID?
        @State private var date = Date()
        @State private var fromStatement = false
        @State private var interestText = ""
        @State private var feesText = ""
        @State private var countsAsBill = false
        @State private var problem: String?
        @State private var loaded = false

        private var s: FinanceSnapshot { app.snapshot }
        private var occurrence: Occurrence? { s.occurrences.first { $0.id == occurrenceId } }
        private var editedParts: LedgerStore.DebtPaymentParts? { editing.flatMap { app.store.debtPaymentParts($0) } }
        /// What was owed before this payment: today's amount, plus what the payment being edited took off
        private var owed: Money { s.owed(debt.id) + (editedParts?.principal ?? .zero(app.currency)) }
        private var money: Money? { app.parse(amount) }

        /// This card's or loan's unpaid monthly bill closest to today, when the form wasn't opened from one
        private var suggestedBill: Occurrence? {
            guard occurrence == nil, editing == nil, replacing == nil, let item = s.paymentItem(for: debt.id) else { return nil }
            return s.occurrences
                .filter { $0.itemId == item.id && !$0.skipped && $0.remaining.isPositive }
                .filter { abs(s.calendar.dateComponents([.day], from: $0.dueDate, to: s.today).day ?? 999) <= 25 }
                .min { abs($0.dueDate.timeIntervalSince(s.today)) < abs($1.dueDate.timeIntervalSince(s.today)) }
        }

        private var split: PaymentSplit? {
            guard let money, money.isPositive else { return nil }
            let zero = Money.zero(app.currency)
            if fromStatement || editing != nil {
                guard let interest = interestText.isEmpty ? zero : app.parse(interestText),
                      let fees = feesText.isEmpty ? zero : app.parse(feesText) else { return nil }
                return DebtCalculator.split(payment: money, owed: owed, annualRateBps: 0, interest: interest, fees: fees)
            }
            return DebtCalculator.split(payment: money, owed: owed, annualRateBps: debt.debtRateBps ?? 0)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                AmountBox(label: "Payment in \(app.currency)", text: $amount, owed: editing == nil ? owed.decimal : nil,
                          autofocus: replacing == nil, identifier: "debtPaymentAmount")
                if let occurrence {
                    Text("Due \(app.fullDay(occurrence.dueDate))").rdText(.caption).foregroundStyle(Theme.muted)
                }
                AccountChoice(label: "Paid from", selection: $fundingId, accounts: app.moneyAccounts)
                Field(label: "Payment date") { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }

                if editing == nil {
                    ToggleRow(title: "Use the amounts on my statement", isOn: $fromStatement)
                }
                if fromStatement || editing != nil {
                    Field(label: "Interest charged") { TextField("0", text: $interestText).keyboardType(.decimalPad) }
                    Field(label: "Fees charged") { TextField("0", text: $feesText).keyboardType(.decimalPad) }
                }
                if let split {
                    DetailCard {
                        DetailRow(label: fromStatement || editing != nil || debt.debtRateBps == nil ? "Interest" : "Interest (estimated)", value: app.money(split.interest))
                        if split.fees.isPositive { DetailRow(label: "Fees", value: app.money(split.fees)) }
                        DetailRow(label: "Lowers what you owe by", value: app.money(split.principal))
                        if editing == nil { DetailRow(label: "You'll owe after", value: app.money(owed - split.principal)) }
                    }
                    if split.overpaid.isPositive {
                        Problem(text: "That's \(app.money(split.overpaid)) more than you owe. Lower the payment.")
                    }
                }
                Redesign.footnote(debt.debtRateBps == nil && !fromStatement
                    ? "No interest rate is set, so the whole payment lowers what you owe. Add the rate under Terms, or use your statement's amounts."
                    : "The estimate is one month of interest at the rate you gave. Your lender's figure can differ a little; use your statement's amounts to match it exactly.")
                if let bill = suggestedBill {
                    ToggleRow(title: "Counts as the \(bill.dueDate.formatted(.dateTime.month(.wide))) payment",
                              detail: "\(app.money(bill.remaining)) was due \(app.day(bill.dueDate)). Turn on if this payment is it, so it isn't held back again.",
                              isOn: $countsAsBill)
                }
                Redesign.footnote("This lowers both your cash and what you owe. It's not new spending, apart from any interest and fees. No bank payment is sent.")
                Problem(text: problem)
                Button(editing == nil && replacing == nil ? "Record payment" : "Save", action: record)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("recordDebtPayment")
                if let occurrence {
                    Button("Skip this one") {
                        problem = app.attempt("Skipped. It's no longer held back.") { try app.store.skip(occurrenceId: occurrence.id) }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .onAppear(perform: load)
        }

        private func load() {
            guard !loaded else { return }
            loaded = true
            if let editing, let parts = editedParts {
                amount = MoneyFormat.editable(parts.total)
                fundingId = parts.funding.id
                date = editing.date
                interestText = MoneyFormat.editable(parts.interest, emptyWhenZero: true)
                feesText = MoneyFormat.editable(parts.fees, emptyWhenZero: true)
                return
            }
            if let replacing, let paid = replacing.entry.lines.first(where: { app.record($0.accountId)?.kind.isAsset == true }) {
                amount = MoneyFormat.editable(paid.amount.magnitude)
                fundingId = paid.accountId
                date = replacing.date
                return
            }
            let item = s.paymentItem(for: debt.id)
            if let suggested = occurrence?.remaining ?? debt.debtTerms?.monthlyPayment {
                // Never suggest more than clears the debt with this month's interest
                let clears = owed + DebtCalculator.monthlyInterest(owed: owed, annualRateBps: debt.debtRateBps ?? 0)
                amount = MoneyFormat.editable(Money.min(suggested, clears), emptyWhenZero: true)
            }
            fundingId = item?.accountId ?? app.store.settings.lastUsedAccountId ?? app.moneyAccounts.first?.id
            if let occurrence { date = min(Date(), max(occurrence.dueDate, s.today)) }
        }

        private func record() {
            problem = nil
            guard let money, money.isPositive else { problem = "Enter the payment."; return }
            guard let fundingId else { problem = "Choose the account you paid from."; return }
            guard let split else { problem = "Enter interest and fees as numbers."; return }
            guard split.overpaid.isZero else { problem = "That's more than you owe. Lower the payment."; return }
            var id: UUID?
            if let editing {
                problem = app.attempt("Payment updated.") {
                    try app.store.editDebtPayment(editing.id, from: fundingId, amount: money, interest: split.interest, fees: split.fees, date: date)
                }
            } else if let replacing {
                problem = app.attempt("Recorded as a payment to \(app.accountLabel(debt.id)).") {
                    try app.store.recordAsDebtPayment(replacing.id, debt: debt.id, from: fundingId, amount: money,
                                                      interest: split.interest, fees: split.fees, date: date)
                }
            } else {
                problem = app.attempt("Payment recorded. Your cash and what you owe are updated.",
                                      undo: { [store = app.store] in if let id { try store.void(id) } }) {
                    id = try app.store.payDebt(debt.id, from: fundingId, amount: money, interest: split.interest, fees: split.fees,
                                               date: date, key: key, occurrenceId: occurrenceId ?? (countsAsBill ? suggestedBill?.id : nil))
                }
            }
        }
    }

    struct DebtTermsForm: View {
        let debt: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var owedText = ""
        @State private var rate = ""
        @State private var payment = ""
        @State private var dueDay: Int?
        @State private var addBill = true
        @State private var fundingId: UUID?
        @State private var categoryId: UUID?
        @State private var problem: String?

        private var opening: EntryRecord? { app.store.openingEntry(for: debt.id) }
        private var recordedOwed: Money { (opening?.entry.amount(on: debt.id) ?? .zero(app.currency)).magnitude }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Owed when added") {
                    TextField("0", text: $owedText).keyboardType(.decimalPad).accessibilityIdentifier("owedWhenAdded")
                }
                Redesign.footnote("If this was typed wrong, fix it here. Payments since \(opening.map { app.day($0.date) } ?? "then") stay as they are.")
                Field(label: "Interest rate, % a year") { TextField("e.g. 4.5", text: $rate).keyboardType(.decimalPad).accessibilityIdentifier("debtRate") }
                Field(label: "Monthly payment") { TextField("0", text: $payment).keyboardType(.decimalPad).accessibilityIdentifier("debtPayment") }
                Field(label: "Due on") {
                    Choice(value: $dueDay, options: [nil] + (1...31).map { Optional($0) }) { $0.map { "Day \($0)" } ?? "Not set" }
                }
                ToggleRow(title: "Add to my bills",
                          detail: addBill ? "The payment shows in Bills each month and is kept aside in safe to spend until paid." : "The payment won't be kept aside.",
                          isOn: $addBill)
                if addBill { AccountChoice(label: "Paid from", selection: $fundingId, accounts: app.moneyAccounts) }
                if debt.kind == .loan { LoanCategoryChoice(selection: $categoryId) }
                Problem(text: problem)
                Button("Save", action: { save() }).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveTerms")
                if debt.debtTerms != nil {
                    Button("Remove rate and payment") { save(clearing: true) }.buttonStyle(QuietButtonStyle())
                }
            }
            .onAppear {
                let item = app.snapshot.paymentItem(for: debt.id)
                if let terms = debt.debtTerms {
                    rate = NSDecimalNumber(decimal: terms.annualRatePercent).stringValue
                    payment = MoneyFormat.editable(terms.monthlyPayment)
                    dueDay = terms.dueDay
                    addBill = item != nil
                }
                fundingId = item?.accountId ?? app.store.settings.lastUsedAccountId ?? app.moneyAccounts.first?.id
                categoryId = debt.debtCategoryId
                owedText = MoneyFormat.editable(recordedOwed, emptyWhenZero: true)
            }
        }

        private func save(clearing: Bool = false) {
            problem = nil
            guard let owed = app.parse(owedText.isEmpty ? "0" : owedText) else { problem = "Enter what was owed as a number."; return }
            let untouched = debt.debtTerms == nil && rate.isEmpty && payment.isEmpty && !clearing
            var terms: DebtTerms?
            if !clearing && !untouched {
                guard let bps = DebtTerms.rateBps(from: rate.isEmpty ? "0" : rate) else { problem = "Enter the yearly rate as a percentage, e.g. 4.5."; return }
                guard let monthly = app.parse(payment), monthly.isPositive else { problem = "Enter the monthly payment."; return }
                if addBill && dueDay == nil { problem = "Choose the due day so the payment can be added to your bills."; return }
                if addBill && fundingId == nil { problem = "Choose the account you pay from."; return }
                terms = DebtTerms(annualRateBps: bps, monthlyPayment: monthly, dueDay: dueDay)
            }
            problem = app.attempt("Saved.") {
                if owed.magnitude != recordedOwed { try app.store.correctOpeningBalance(debt.id, to: owed.magnitude.negated) }
                if !untouched { try app.store.saveDebtTerms(terms, for: debt.id, paidFrom: addBill ? fundingId : nil) }
                if debt.kind == .loan, categoryId != debt.debtCategoryId { try app.store.setLoanCategory(categoryId, for: debt.id) }
            }
        }
    }
}

// MARK: - Account tools

extension Redesign {
    struct ReconcileForm: View {
        let account: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var date = Date()
        @State private var balance = ""
        @State private var reason = ""
        @State private var problem: String?

        var body: some View {
            let liability = account.kind.isLiability
            let entered = app.parse(balance).map { liability ? $0.negated : $0 }
            let check = entered.map { Reconciler.check(ledger: app.snapshot.ledger, accountId: account.id, statementDate: date, statementBalance: $0) }
            VStack(alignment: .leading, spacing: 16) {
                Text("Type the closing balance from your statement or banking app. If it differs, we'll correct the difference.")
                    .rdText(.body).foregroundStyle(Theme.muted)
                AmountBox(label: liability ? "Owed on the statement, in \(app.currency)" : "Statement balance in \(app.currency)", text: $balance)
                Field(label: "Statement date") { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }
                if let check {
                    DetailCard {
                        DetailRow(label: "Recorded here", value: app.money(liability ? check.calculated.negated : check.calculated))
                        DetailRow(label: "On the statement", value: app.money(liability ? check.statement.negated : check.statement))
                        DetailRow(label: "Difference", value: app.money(check.difference.magnitude))
                    }
                    if check.matches {
                        Label("They match.", systemImage: "checkmark.seal").rdText(.detail).foregroundStyle(Theme.primary)
                    } else {
                        Field(label: "Why is it different? (needed to correct it)") { TextField("e.g. Bank fee I missed", text: $reason) }
                    }
                }
                Problem(text: problem)
                Button(check?.matches == false ? "Correct and confirm" : "Confirm", action: confirm)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(check == nil)
            }
        }

        private func confirm() {
            guard let value = app.parse(balance) else { problem = "Enter the statement balance."; return }
            let statement = account.kind.isLiability ? value.negated : value
            problem = app.attempt("Checked against your statement.") {
                try app.store.reconcile(accountId: account.id, statementDate: date, statementBalance: statement,
                                        reason: reason.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reason)
            }
        }
    }

    struct AccountTypeForm: View {
        let account: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var kind: AccountKind = .bank
        @State private var moveTo: UUID?
        @State private var problem: String?

        private let kinds: [AccountKind] = [.bank, .cash, .savings, .creditCard, .loan, .investment, .lent, .otherAsset]

        var body: some View {
            let count = app.store.movableEntries(of: account.id, to: nil).count
            let others = app.accounts.filter { $0.id != account.id && $0.kind.isAsset && $0.kind != .lent }
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "This is a") { Choice(value: $kind, options: kinds) { Redesign.kindName($0) } }
                    .accessibilityIdentifier("accountTypePicker")
                Redesign.footnote(footer)
                if count > 0 {
                    Field(label: count == 1 ? "1 entry is recorded here. Move it to" : "\(count) entries are recorded here. Move them to") {
                        Choice(value: $moveTo, options: [nil] + others.map { Optional($0.id) }) { $0 == nil ? "Keep them here" : app.accountLabel($0) }
                    }
                    .accessibilityIdentifier("moveEntriesTo")
                    Redesign.footnote("If you imported a statement or added spending here that really came from another account, move it there. Payments between the two accounts stay where they are.")
                }
                Problem(text: problem)
                Button("Save") {
                    problem = app.attempt("Account type changed.") {
                        try app.store.changeAccountType(account.id, to: kind, movingEntriesTo: moveTo)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(kind == account.kind && moveTo == nil)
                .accessibilityIdentifier("saveAccountType")
            }
            .onAppear { kind = account.kind }
        }

        private var footer: String {
            guard kind != account.kind else { return "Choose what this account really is." }
            if kind.isLiability && !account.kind.isLiability {
                return "What it was added with becomes what you owe, and it stops counting as money you can spend. Add the monthly payment on its page afterwards."
            }
            if account.kind.isLiability && !kind.isLiability { return "What you owed becomes money you have. Its monthly payment is removed from your bills." }
            if kind == .lent { return "What's here becomes what they owe you. It stays in your net worth but stops counting as money you can spend." }
            return "Balances stay as they are."
        }
    }

    struct StartingAmountForm: View {
        let account: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var amount = ""
        @State private var problem: String?

        var body: some View {
            let liability = account.kind.isLiability
            let opening = app.store.openingEntry(for: account.id)?.entry.amount(on: account.id) ?? .zero(app.currency)
            let entered = app.parse(amount).map { liability ? $0.negated : $0 }
            VStack(alignment: .leading, spacing: 16) {
                Text("What \(app.accountLabel(account.id)) \(liability ? "owed" : "held") when you added it. Fix it if it was typed wrong; everything since stays as it is.")
                    .rdText(.body).foregroundStyle(Theme.muted)
                AmountBox(label: "Starting amount in \(app.currency)", text: $amount, identifier: "startingAmount")
                if let entered {
                    let now = app.snapshot.balance(account.id) - opening + entered
                    DetailCard { DetailRow(label: liability ? "You'll owe now" : "Balance now", value: app.money(liability ? now.negated : now)) }
                }
                Problem(text: problem)
                Button("Save") {
                    guard let entered else { problem = "Enter the amount."; return }
                    problem = app.attempt("Starting amount fixed.") { try app.store.correctOpeningBalance(account.id, to: entered) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("saveStartingAmount")
            }
            .onAppear {
                let opening = app.store.openingEntry(for: account.id)?.entry.amount(on: account.id) ?? .zero(app.currency)
                amount = MoneyFormat.editable(opening.magnitude, emptyWhenZero: true)
            }
        }
    }

    /// A loan started from a statement: its payment and day are known, what's left isn't yet
    struct FinishLoanForm: View {
        let loan: LedgerAccountRecord
        @Environment(AppModel.self) private var app
        @State private var name = ""
        @State private var owed = ""
        @State private var rate = ""
        @State private var problem: String?

        var body: some View {
            let item = app.snapshot.paymentItem(for: loan.id)
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Name") {
                    TextField(loan.name, text: $name).accessibilityIdentifier("loanName")
                }
                AmountBox(label: "Still owed today in \(app.currency)", text: $owed, identifier: "loanOwed")
                Field(label: "Interest rate, % a year (optional)") {
                    TextField("e.g. 4.5", text: $rate).keyboardType(.decimalPad)
                }
                if let terms = loan.debtTerms {
                    DetailCard {
                        DetailRow(label: "Monthly payment", value: app.money(terms.monthlyPayment))
                        DetailRow(label: "Due on", value: terms.dueDay.map { "Day \($0)" } ?? "Not set")
                        if let item { DetailRow(label: "Paid from", value: app.accountLabel(item.accountId)) }
                    }
                }
                Text("From your loan statement or banking app: what's left to pay, not the original loan. Payments already recorded stay as they are.")
                    .rdText(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
                Problem(text: problem)
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("finishLoan")
            }
        }

        private func save() {
            guard let amount = app.parse(owed), amount.isPositive else { problem = "Enter what you still owe."; return }
            guard rate.isEmpty || DebtTerms.rateBps(from: rate) != nil else {
                problem = "Enter the yearly rate as a percentage, e.g. 4.5, or leave it empty."; return
            }
            let bps = rate.isEmpty ? nil : DebtTerms.rateBps(from: rate)
            problem = app.attempt("Loan saved. It isn't counted as cash.") {
                try app.store.finishLoan(loan.id, name: name, owed: amount, annualRateBps: bps)
            }
        }
    }

    /// Money with a person, either way: lending, being paid back, borrowing, paying back, or letting it go.
    /// With no person given (from What happened? or +), it asks who, and a new name opens their account.
    struct LendForm: View {
        let person: LedgerAccountRecord?
        let action: LendAction
        @Environment(AppModel.self) private var app
        @State private var personId: UUID?
        @State private var newName = ""
        @State private var amount = ""
        @State private var accountId: UUID?
        @State private var date = Date()
        @State private var hasDueDate = false
        @State private var dueDate = Date()
        @State private var problem: String?

        private var chosen: LedgerAccountRecord? { person ?? app.record(personId) }
        /// Who can be picked: anyone for new money, only those who owe for a repayment
        private var people: [Account] {
            app.lent.filter { action == .repaid ? $0.balance > 0 : action == .payBack ? $0.youOwe : true }
        }
        private var accounts: [Account] {
            // Money going out can come off a card; money coming in lands in an account you hold
            action.isOut ? app.accounts.filter { ($0.kind.holdsMoney || $0.kind == .creditCard) && !$0.archived } : app.moneyAccounts
        }

        var body: some View {
            let balance = chosen.map { app.snapshot.balance($0.id) }
            let owed = action == .payBack ? balance?.negated : balance
            VStack(alignment: .leading, spacing: 16) {
                if person == nil {
                    Field(label: action.isOut && action == .lend ? "Who did you lend to?" : action == .borrow ? "Who lent it to you?" : "Who?") {
                        Choice(value: $personId, options: [nil] + people.map { Optional($0.id) }) { id in
                            id.flatMap { app.account($0) }.map { app.accountLabel($0.id) } ?? "Someone new"
                        }
                    }
                    if personId == nil {
                        Field(label: "Their name") {
                            TextField("e.g. Sam", text: $newName).accessibilityIdentifier("personName")
                        }
                    }
                }
                AmountBox(label: "Amount in \(app.currency)", text: $amount,
                          owed: [.repaid, .payBack, .forgive].contains(action) ? owed?.decimal : nil, identifier: "lentAmount")
                if action != .forgive {
                    AccountChoice(label: action.isOut ? "From" : "Into", selection: $accountId, accounts: accounts)
                }
                Field(label: "Date") { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }
                if action == .lend || action == .borrow {
                    Toggle(isOn: $hasDueDate.animation(.snappy)) {
                        Text(action == .lend ? "They'll pay it back by a date" : "I'll pay it back by a date").rdText(.detail)
                    }
                    .tint(Theme.primary)
                    if hasDueDate {
                        DatePicker("Pay back by", selection: $dueDate, in: Date()..., displayedComponents: .date).rdText(.detail)
                    }
                }
                Redesign.footnote(footnote)
                Problem(text: problem)
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveLent")
            }
            .onAppear {
                accountId = accounts.first { $0.id == app.store.settings.lastUsedAccountId }?.id ?? accounts.first?.id
                if person == nil { personId = people.first?.id }
                if let due = person?.owedBackBy, due >= app.today { hasDueDate = true; dueDate = due }
                if action == .forgive, let owed { amount = MoneyFormat.editable(owed) }
            }
        }

        private var footnote: String {
            let who = chosen.map { app.accountLabel($0.id) } ?? "they"
            switch action {
            case .lend: return "Moves money from your account to what \(who) owes you. It isn't spending, and it's left out of safe to spend until it's paid back."
            case .repaid: return "Moves what they paid back into your account. It isn't income."
            case .borrow: return "The money lands in your account and becomes what you owe \(who). It isn't income, and it's left out of safe to spend."
            case .payBack: return "Moves money from your account to settle what you owe. It isn't spending."
            case .forgive: return "What they still owe becomes spending, under \(app.store.peopleCategory.name)."
            }
        }

        private func save() {
            guard let value = app.parse(amount), value.isPositive else { problem = "Enter the amount."; return }
            let name = newName.trimmingCharacters(in: .whitespaces)
            if chosen == nil && name.isEmpty { problem = "Add their name."; return }
            problem = app.attempt("Saved.") {
                let p = try chosen ?? app.store.lentAccount(named: name)
                switch action {
                case .lend, .payBack, .repaid, .borrow:
                    guard let accountId else { throw StoreError.invalid("Choose the account.") }
                    switch action {
                    case .lend: try app.store.lend(value, to: p.id, from: accountId, date: date)
                    case .payBack: try app.store.payBack(value, to: p.id, from: accountId, date: date)
                    case .repaid: try app.store.receiveRepayment(value, from: p.id, into: accountId, date: date)
                    default: try app.store.borrow(value, from: p.id, into: accountId, date: date)
                    }
                case .forgive:
                    try app.store.forgive(value, owedBy: p.id, date: date)
                }
                if action == .lend || action == .borrow { try app.store.setOwedBackBy(hasDueDate ? dueDate : nil, for: p.id) }
                // Settled in full: there's nothing left to be reminded about
                if app.store.snapshot.balance(p.id).isZero { try app.store.setOwedBackBy(nil, for: p.id) }
            }
        }
    }

    /// When a person said they'd pay back, or you said you would; nudges on Home once it passes
    struct PayBackBy: View {
        let person: LedgerAccountRecord
        @Environment(AppModel.self) private var app

        var body: some View {
            let on = Binding(get: { person.owedBackBy != nil }, set: { set($0 ? (person.owedBackBy ?? week) : nil) })
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: on.animation(.snappy)) { Text("Pay back by a date").rdText(.detail) }.tint(Theme.primary)
                if let due = person.owedBackBy {
                    DatePicker("Pay back by", selection: Binding(get: { due }, set: { set($0) }), displayedComponents: .date)
                        .rdText(.detail)
                }
            }
            .rdPanel(padding: 14)
        }

        private var week: Date { app.calendar.date(byAdding: .day, value: 7, to: app.today) ?? app.today }

        private func set(_ date: Date?) {
            app.attempt(closing: false) { try app.store.setOwedBackBy(date, for: person.id) }
                .map { app.toast = Toast(message: $0, isError: true) }
        }
    }
}
