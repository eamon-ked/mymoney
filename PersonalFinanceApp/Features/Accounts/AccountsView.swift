//
//  AccountsView.swift
//  Nokael Money
//
//  Where the money is held: cash and banks, cards, loans, investments and
//  other assets, each with its own subtotal. Net worth is labelled as such,
//  never as "available".
//

import SwiftUI
import NokaelCore

enum AccountSection: String, CaseIterable, Identifiable {
    case cash = "Cash & banks", cards = "Credit cards", loans = "Loans", investments = "Investments", lent = "Lent to people", other = "Other assets"
    var id: String { rawValue }

    func contains(_ kind: AccountKind) -> Bool {
        switch self {
        case .cash: return [.cash, .bank, .savings].contains(kind)
        case .cards: return kind == .creditCard
        case .loans: return kind == .loan
        case .investments: return kind == .investment
        case .lent: return kind == .lent
        case .other: return kind == .otherAsset
        }
    }
}

struct AccountsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var addingAccount = false
    @State private var addingLoan = false
    /// Started as a bank account, but it's a loan or card: open that form once this one closes
    @State private var switchToLoan = false
    @State private var explanation: Explanation?
    @State private var showArchived = false

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let worth = snapshot.netWorth
                    // Just the number: what's owned and owed is already in the list below.
                    // Never red: a big loan makes it negative and that's normal, not an alarm.
                    SummaryBanner(title: "Net worth", amount: worth.total.whole, tint: Palette.accounts,
                                  action: { explanation = netWorthExplanation(worth) })
                    .bannerRow()
                }

                if !snapshot.hasAccounts {
                    Section {
                        EmptyStateView(symbol: "building.columns", title: "No accounts yet",
                                       message: "Add your bank accounts, cash, cards and loans to see where your money is.",
                                       actionTitle: "Add account") { addingAccount = true }
                    }
                }

                ForEach(AccountSection.allCases) { section in
                    let accounts = snapshot.accounts.filter { section.contains($0.kind) }
                    if !accounts.isEmpty {
                        Section {
                            ForEach(accounts, id: \.id) { account in
                                NavigationLink(value: account.id) { AccountRow(account: account, snapshot: snapshot) }
                            }
                        } header: {
                            HStack {
                                Text(section.rawValue)
                                Spacer()
                                // A total only adds something when there's more than one row to add up
                                if accounts.count > 1 {
                                    let total = accounts.map { snapshot.balance($0.id) }.sum(store.currency)
                                    // Debt is an amount owed, never a minus sign
                                    Text(section.contains(.creditCard) || section.contains(.loan)
                                         ? "\(total.negated.compact) owed" : total.compact)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { addingAccount = true } label: {
                        Label("Add bank account", systemImage: "building.columns")
                    }
                    Button { addingLoan = true } label: {
                        Label("Add loan or credit card", systemImage: "creditcard")
                    }
                    .accessibilityIdentifier("addLoan")
                }

                if !snapshot.archivedAccounts.isEmpty {
                    Section {
                        DisclosureGroup("Archived (\(snapshot.archivedAccounts.count))", isExpanded: $showArchived) {
                            ForEach(snapshot.archivedAccounts, id: \.id) { account in
                                NavigationLink(value: account.id) { AccountRow(account: account, snapshot: snapshot) }
                            }
                        }
                    } footer: {
                        Text("Archived accounts keep their history but aren't counted anywhere.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .canvas()
            .navigationTitle("Accounts")
            // Nothing else lives in the top bar here, so the title takes that row instead of leaving it empty
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: UUID.self) { AccountDetailView(accountId: $0) }
            .toolbar {
                // Always in reach, however long the list of accounts and loans gets
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { addingAccount = true } label: { Label("Bank account, cash or savings", systemImage: "building.columns") }
                        Button { addingLoan = true } label: { Label("Loan or credit card", systemImage: "creditcard") }
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Add account or loan")
                    .accessibilityIdentifier("addAccountMenu")
                }
            }
            .sheet(isPresented: $addingAccount, onDismiss: {
                if switchToLoan { switchToLoan = false; addingLoan = true }
            }) { NewAccountSheet(onLoan: { switchToLoan = true }) }
            .sheet(isPresented: $addingLoan) { NewLoanSheet() }
            .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
        }
    }

    private func netWorthExplanation(_ worth: NetWorth) -> Explanation {
        let included = snapshot.accounts.filter { $0.includeInNetWorth }
        let owned = included.filter { $0.kind.isAsset }.map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id)) }
        let owed = included.filter { $0.kind.isLiability }.map { BreakdownItem(label: $0.name, amount: snapshot.balance($0.id).negated) }
        var notes = ["Transfers between your accounts never change net worth."]
        let excluded = snapshot.accounts.filter { !$0.includeInNetWorth }
        if !excluded.isEmpty { notes.append("Not included: " + excluded.map(\.name).joined(separator: ", ") + ".") }
        return Explanation(title: "Net worth", total: worth.total,
                           definition: "Everything in your included accounts, minus everything you owe on cards and loans.",
                           sections: [("What you own", owned, ""), ("What you owe", owed, "−")], notes: notes)
    }
}

struct AccountRow: View {
    let account: LedgerAccountRecord
    let snapshot: FinanceSnapshot

    var body: some View {
        ListRow(title: account.name, caption: caption, symbol: account.icon.isEmpty ? AccountStyle.icon(for: account.kind) : account.icon,
                color: Color(hex: account.colorHex)) {
            if account.kind.isLiability {
                AmountPill(owed: snapshot.balance(account.id))
            } else {
                AmountPill(snapshot.balance(account.id))
            }
        }
    }

    private var caption: String {
        // A card or loan with terms says what it costs a month and when it's done
        if account.kind.isLiability, let terms = account.debtTerms {
            return ["\(terms.monthlyPayment.compact) a month", snapshot.payoff(for: account)?.shortText].compactMap { $0 }.joined(separator: " · ")
        }
        // "Emirates NBD Current" already says the bank; don't say it again underneath
        let bank = account.institution.flatMap { name in
            name.isEmpty || account.name.localizedCaseInsensitiveContains(name) ? nil : name
        }
        var parts = [bank, AccountStyle.name(for: account.kind)].compactMap { $0 }
        if let last = account.lastReconciledAt {
            parts.append("Checked " + last.formatted(.relative(presentation: .named)))
        }
        if !account.includeInNetWorth { parts.append("Not in net worth") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - New account

struct NewAccountSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onCreated: (LedgerAccountRecord) -> Void = { _ in }
    /// Loans and cards have their own form, with what's owed and the monthly payment
    var onLoan: (() -> Void)? = nil

    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var institution = ""
    @State private var balanceText = ""
    @State private var balanceDate = Date()
    @State private var error: String?

    // Money you have only: a loan picked from here would miss its payment and what's owed
    private let kinds: [AccountKind] = [.bank, .cash, .savings, .investment, .lent, .otherAsset]
    private var isDebt: Bool { kind.isLiability }

    var body: some View {
        NavigationStack {
            Form {
                AccountFormFields(name: $name, kind: $kind, institution: $institution, balanceText: $balanceText,
                                  balanceDate: $balanceDate, kinds: kinds, currency: store.currency)
                if let onLoan {
                    Section {
                        Button { onLoan(); dismiss() } label: {
                            Label("Adding a loan or credit card?", systemImage: "creditcard")
                        }
                        .accessibilityIdentifier("switchToLoan")
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save) }
            }
        }
    }

    private func save() {
        let entered = balanceText.isEmpty ? Money.zero(store.currency) : MoneyFormat.parse(balanceText, currency: store.currency)
        guard let entered else { error = "Enter the balance as a number."; return }
        // What you owe is stored as a negative balance
        let opening = isDebt ? entered.magnitude.negated : entered
        do {
            let record = try store.createAccount(name: name, kind: kind, opening: opening, openingDate: balanceDate,
                                                 institution: institution.isEmpty ? nil : institution,
                                                 colorHex: AccountColors.next(for: kind))
            onCreated(record)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

struct AccountFormFields: View {
    @Binding var name: String
    @Binding var kind: AccountKind
    @Binding var institution: String
    @Binding var balanceText: String
    @Binding var balanceDate: Date
    let kinds: [AccountKind]
    let currency: String

    var body: some View {
        Section {
            TextField("Name (e.g. Emirates NBD current)", text: $name)
                .accessibilityIdentifier("accountName")
            Picker("Type", selection: $kind) {
                ForEach(kinds, id: \.self) { Label(AccountStyle.name(for: $0), systemImage: AccountStyle.icon(for: $0)).tag($0) }
            }
            TextField("Bank or provider (optional)", text: $institution)
        }
        Section {
            HStack {
                Text(currency).foregroundStyle(.secondary)
                TextField("0", text: $balanceText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("openingBalance")
            }
            DatePicker("On", selection: $balanceDate, in: ...Date(), displayedComponents: .date)
        } header: {
            Text(kind.isLiability ? "Amount you owe" : kind == .lent ? "Amount they owe you" : "Balance")
        } footer: {
            Text(kind.isLiability
                 ? "Enter what you owe today. Spending on it adds to this; payments reduce it."
                 : kind == .lent
                 ? "One for each person. What they owe you counts in your net worth, but not as money you can spend."
                 : "What the account holds on this date, from your banking app or statement.")
        }
    }
}

enum AccountColors {
    static func next(for kind: AccountKind) -> String {
        switch kind {
        case .bank: return "#3A7BD5"
        case .cash: return "#2BA84A"
        case .savings: return "#0E9AA7"
        case .creditCard: return "#E4572E"
        case .loan: return "#8E44AD"
        case .investment: return "#5B6CFF"
        case .lent: return "#FF9500"
        default: return "#8E8E93"
        }
    }
}
