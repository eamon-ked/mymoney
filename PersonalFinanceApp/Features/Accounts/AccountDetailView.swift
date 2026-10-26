//
//  AccountDetailView.swift
//  Nokael Money
//
//  One account: balance, every entry with the running balance after it,
//  reconciliation against a statement, and the account's settings.
//

import SwiftUI
import NokaelCore

struct AccountDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @State private var paywall: PlusFeature?
    let accountId: UUID
    @State private var reconciling = false
    @State private var importing = false
    @State private var selected: EntryRecord?
    @State private var debtSheet: DebtSheet?
    @State private var error: String?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        if let account = snapshot.account(accountId) {
            content(account)
        } else {
            ContentUnavailableView("Account not found", systemImage: "questionmark.folder")
        }
    }

    private func content(_ account: LedgerAccountRecord) -> some View {
        let balance = snapshot.balance(account.id)
        let rows = snapshot.ledger.runningBalance(of: account.id)
        let records = Dictionary(snapshot.entryRecords.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return List {
            Section {
                SummaryBanner(title: account.kind.isLiability ? (balance.isNegative ? "You owe" : "Balance") : "Balance",
                              amount: (account.kind.isLiability && balance.isNegative ? balance.magnitude : balance).compact,
                              caption: confirmedCaption(account),
                              tint: balance.isNegative && !account.kind.isLiability ? .red : Color(hex: account.colorHex))
                .bannerRow()
            }

            if account.kind.isLiability { DebtSection(debt: account, sheet: $debtSheet) }

            Section {
                Button { if plus.isPlus { importing = true } else { paywall = .statementImport } } label: {
                    HStack {
                        Label("Import a statement (CSV)", systemImage: "square.and.arrow.down")
                        if !plus.isPlus { Spacer(); PlusBadge() }
                    }
                }
                .accessibilityIdentifier("importStatement")
                Button { reconciling = true } label: {
                    Label("Check against a statement", systemImage: "checkmark.seal")
                }
            } footer: {
                Text("Import adds what's missing from your bank's statement file. Checking compares your balance with the statement's; any difference is shown before anything changes.")
            }

            Section("Entries") {
                if rows.isEmpty {
                    Text("No entries yet").foregroundStyle(.secondary)
                }
                ForEach(rows.reversed(), id: \.entry.id) { row in
                    if let record = records[row.entry.id] {
                        Button { selected = record } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                EntryRow(record: record, snapshot: snapshot, accountId: account.id)
                                Text("Balance after: \(row.balance.compact)")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    .padding(.leading, 46)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AccountSettingsSection(account: account, error: $error)
            if let error { Section { FieldError(message: error) } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { GlobalAddButton() }
        .sheet(isPresented: $reconciling) { ReconcileSheet(account: account) }
        .sheet(isPresented: $importing) { ImportStatementView(accountId: account.id) }
        .paywall($paywall)
        .sheet(item: $selected) { EntryDetailView(record: $0) }
        .sheet(item: $debtSheet) { sheet in
            switch sheet {
            case .terms: DebtTermsEditor(debt: account)
            case .pay: PayDebtSheet(debt: account)
            case .plus: PaywallView(feature: .payoffPlanner)
            }
        }
    }

    private func confirmedCaption(_ account: LedgerAccountRecord) -> String {
        guard let date = snapshot.lastConfirmed[account.id] else { return "No entries yet" }
        let days = snapshot.calendar.dateComponents([.day], from: date, to: snapshot.today).day ?? 0
        if days > snapshot.settings.staleAfterDays {
            return "Last updated \(days) days ago. Check it against your bank."
        }
        if let reconciled = account.lastReconciledAt {
            return "Checked against a statement " + reconciled.formatted(.relative(presentation: .named))
        }
        return "Last entry " + date.formatted(.relative(presentation: .named))
    }
}

struct AccountSettingsSection: View {
    @Environment(LedgerStore.self) private var store
    let account: LedgerAccountRecord
    @Binding var error: String?
    @State private var name = ""
    @State private var confirmArchive = false

    var body: some View {
        Section {
            TextField("Name", text: $name)
                .onSubmit { update { $0.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? $0.name : name } }
            Toggle("Counts in net worth", isOn: binding(\.includeInNetWorth))
            if account.kind.isAsset {
                Toggle("Money I can spend", isOn: binding(\.spendable))
            }
            // A loan in the budget would take everything owed out of Available to allocate,
            // so it's only offered to switch back off
            if account.kind != .loan || account.onBudget {
                Toggle("Part of my budget", isOn: binding(\.onBudget))
            }
            Button(account.archived ? "Restore account" : "Archive account", role: account.archived ? nil : .destructive) {
                if account.archived { update { $0.archived = false } } else { confirmArchive = true }
            }
        } header: {
            Text("Settings")
        } footer: {
            Text(footer)
        }
        .onAppear { name = account.name }
        .confirmationDialog("Archive \(account.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) { update { $0.archived = true } }
        } message: {
            Text("Its history is kept, but it stops counting towards balances, net worth and safe-to-spend.")
        }
    }

    private var footer: String {
        var lines = ["Counts in net worth: whether this account is added to what you own or owe."]
        if account.kind.isAsset { lines.append("Money I can spend: whether its money counts towards safe-to-spend.") }
        lines.append(budgetExplanation)
        return lines.joined(separator: "\n\n")
    }

    private var budgetExplanation: String {
        switch account.kind {
        case .loan where account.onBudget:
            return "Budget: this loan is in your budget, so everything you owe on it is taken out of Available to allocate. Turn it off unless you mean that. Monthly payments are still counted under Interest & fees either way."
        case .loan:
            return "Budget: loans stay outside your budget, so what you still owe doesn't eat into Available to allocate. Each monthly payment leaves your bank account and is counted in full under Interest & fees in Budget, interest and the part that lowers the loan together."
        case .creditCard:
            return "Part of my budget: card purchases come out of their budget categories when you make them, so paying the card off later isn't counted twice. Turn it off only if you never plan this card's spending in Budget."
        default:
            return "Part of my budget: the money here can be shared out in Budget. Turn it off for money you don't plan month to month, like long-term savings or investments."
        }
    }

    private func binding(_ path: ReferenceWritableKeyPath<LedgerAccountRecord, Bool>) -> Binding<Bool> {
        Binding(get: { account[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }

    private func update(_ change: (LedgerAccountRecord) -> Void) {
        do { try store.updateAccount(account, change) } catch { self.error = StoreError.from(error).errorDescription }
    }
}

struct ReconcileSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: LedgerAccountRecord

    @State private var statementText = ""
    @State private var statementDate = Date()
    @State private var reason = ""
    @State private var error: String?

    private var statement: Money? {
        guard let m = MoneyFormat.parse(statementText, currency: store.currency) else { return nil }
        return account.kind.isLiability ? m.magnitude.negated : m
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Statement date", selection: $statementDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField(account.kind.isLiability ? "Amount owed on statement" : "Ending balance", text: $statementText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }

                if let statement {
                    let check = Reconciler.check(ledger: store.snapshot.ledger, accountId: account.id,
                                                 statementDate: endOfDay, statementBalance: statement)
                    Section("Result") {
                        LabeledContent("Recorded in Nokael", value: check.calculated.formatted)
                        LabeledContent("Statement", value: check.statement.formatted)
                        LabeledContent("Difference", value: check.difference.signed)
                            .foregroundStyle(check.matches ? .green : .orange)
                        if check.matches {
                            Label("They match.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Text("Look for a missing or mistyped entry among the \(check.unreconciled.count) not yet checked. If you can't find it, record an adjustment with a reason.")
                                .font(.footnote)
                            TextField("Reason for adjustment", text: $reason)
                        }
                    }
                }

                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Check \(account.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", action: confirm).disabled(statement == nil)
                }
            }
        }
    }

    private var endOfDay: Date { store.snapshot.endOfDay(statementDate) }

    private func confirm() {
        guard let statement else { return }
        do {
            try store.reconcile(accountId: account.id, statementDate: endOfDay, statementBalance: statement,
                                reason: reason.isEmpty ? nil : reason)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
