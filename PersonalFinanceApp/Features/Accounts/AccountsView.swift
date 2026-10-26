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
    case cash = "Cash & banks", cards = "Credit cards", loans = "Loans", investments = "Investments", other = "Other assets"
    var id: String { rawValue }

    func contains(_ kind: AccountKind) -> Bool {
        switch self {
        case .cash: return [.cash, .bank, .savings].contains(kind)
        case .cards: return kind == .creditCard
        case .loans: return kind == .loan
        case .investments: return kind == .investment
        case .other: return kind == .otherAsset
        }
    }
}

struct AccountsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var addingAccount = false
    @State private var explanation: Explanation?
    @State private var showArchived = false

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let worth = snapshot.netWorth
                    SummaryBanner(title: "Net worth", amount: worth.total.compact,
                                  caption: worth.total.isNegative ? "You owe more than you own right now" : "What you own minus what you owe",
                                  tint: worth.total.isNegative ? .red : Palette.accounts,
                                  action: { explanation = netWorthExplanation(worth) }) {
                        BannerFigures(figures: [("Own", worth.assets.compact), ("Owe", worth.liabilities.compact)])
                    }
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
                                Text(accounts.map { snapshot.balance($0.id) }.sum(store.currency).compact).monospacedDigit()
                            }
                        } footer: {
                            if section == .cash {
                                Text("Tap an account to see its history or import a statement.")
                            } else if section == .cards || section == .loans {
                                Text("Tap one to record a payment.")
                            }
                        }
                    }
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
            .navigationTitle("Accounts")
            .navigationDestination(for: UUID.self) { AccountDetailView(accountId: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { addingAccount = true } label: { Text("New account").font(.body.weight(.semibold)) }
                }
                GlobalAddButton()
            }
            .sheet(isPresented: $addingAccount) { NewAccountSheet() }
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
            AmountPill(snapshot.balance(account.id))
        }
    }

    private var caption: String {
        var parts = [account.institution, AccountStyle.name(for: account.kind)].compactMap { $0 }.filter { !$0.isEmpty }
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

    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var institution = ""
    @State private var balanceText = ""
    @State private var balanceDate = Date()
    @State private var error: String?

    private let kinds: [AccountKind] = [.bank, .cash, .savings, .creditCard, .loan, .investment, .otherAsset]
    private var isDebt: Bool { kind.isLiability }

    var body: some View {
        NavigationStack {
            Form {
                AccountFormFields(name: $name, kind: $kind, institution: $institution, balanceText: $balanceText,
                                  balanceDate: $balanceDate, kinds: kinds, currency: store.currency)
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
            Text(kind.isLiability ? "Amount you owe" : "Balance")
        } footer: {
            Text(kind.isLiability
                 ? "Enter what you owe today. Spending on it adds to this; payments reduce it."
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
        default: return "#8E8E93"
        }
    }
}
