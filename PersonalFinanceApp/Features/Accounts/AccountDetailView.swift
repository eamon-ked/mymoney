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
    @State private var changingType = false
    @State private var lentSheet: LentSheet.Action?
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
                SummaryBanner(title: account.kind.isLiability ? (balance.isNegative ? "You owe" : "Balance")
                                : account.kind == .lent ? "Owes you" : "Balance",
                              amount: (account.kind.isLiability && balance.isNegative ? balance.magnitude : balance).compact,
                              caption: confirmedCaption(account),
                              tint: balance.isNegative && !account.kind.isLiability ? .red : Color(hex: account.colorHex))
                .bannerRow()
            }

            // Up top, not under the entries: a loan saved as a bank account says so here at a glance
            Section {
                Button { changingType = true } label: {
                    LabeledContent("Type") {
                        HStack(spacing: 4) {
                            Text(AccountStyle.name(for: account.kind))
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("accountType")
            }

            if account.kind.isLiability { DebtSection(debt: account, sheet: $debtSheet) }
            if account.kind == .lent { LentSection(person: account, balance: balance, sheet: $lentSheet) }

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
                Text("Adds what's missing from your bank's statement. Any difference is shown first.")
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
                                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
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
        .sheet(isPresented: $changingType) { ChangeAccountTypeSheet(account: account) }
        .sheet(item: $lentSheet) { LentSheet(person: account, action: $0) }
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
            // A loan in the budget would take everything owed out of Not planned yet,
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
            return "Budget: this loan is in your budget, so everything you owe on it is taken out of Not planned yet. Turn it off unless you mean that. Its monthly payments are planned under its budget category either way."
        case .loan:
            return "Budget: loans stay outside your budget, so what you still owe doesn't eat into Not planned yet. Each monthly payment is planned for you in its budget category (Loan payments unless you pick another) at the full instalment: interest and the part that lowers the loan together."
        case .lent:
            return "Part of my budget: money lent is outside your budget until it comes back. Lending takes it out of Not planned yet; what's paid back puts it in again."
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

/// An account added as the wrong type: a loan saved as a bank account shows what's owed as money
/// to spend. Changing the type puts the amount on the right side, and entries that were recorded
/// here by mistake (a statement imported into the wrong account) can go where they belong.
struct ChangeAccountTypeSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: LedgerAccountRecord

    @State private var kind: AccountKind = .bank
    @State private var moveTo: UUID?
    @State private var error: String?

    private let kinds: [AccountKind] = [.bank, .cash, .savings, .creditCard, .loan, .investment, .lent, .otherAsset]
    private var snapshot: FinanceSnapshot { store.snapshot }
    private var others: [LedgerAccountRecord] {
        snapshot.accounts.filter { $0.id != account.id && $0.kind.isAsset && $0.kind != .lent }
    }
    private var entryCount: Int { store.movableEntries(of: account.id, to: nil).count }
    private var opening: Money? {
        store.openingEntry(for: account.id)?.entry.amount(on: account.id).flatMap { $0.isZero ? nil : $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("This is a", selection: $kind) {
                        ForEach(kinds, id: \.self) { Label(AccountStyle.name(for: $0), systemImage: AccountStyle.icon(for: $0)).tag($0) }
                    }
                    .accessibilityIdentifier("accountTypePicker")
                } footer: {
                    Text(typeFooter)
                }

                if entryCount > 0 {
                    Section {
                        Picker("Move them to", selection: $moveTo) {
                            Text("Keep them here").tag(nil as UUID?)
                            ForEach(others, id: \.id) { Label($0.name, systemImage: $0.icon).tag($0.id as UUID?) }
                        }
                        .accessibilityIdentifier("moveEntriesTo")
                    } header: {
                        Text(entryCount == 1 ? "1 entry is recorded here" : "\(entryCount) entries are recorded here")
                    } footer: {
                        Text("If you imported a statement or added spending here that really came from another account, move it there. Payments between the two accounts stay where they are.")
                    }
                }

                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Account type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("saveAccountType")
                        .disabled(kind == account.kind && moveTo == nil)
                }
            }
            .onAppear { kind = account.kind }
        }
    }

    private var typeFooter: String {
        guard kind != account.kind else { return "Choose what this account really is." }
        if kind.isLiability && !account.kind.isLiability {
            let added = opening.map { "The \($0.magnitude.compact) it was added with becomes what you owe, and it" } ?? "It"
            return "\(added) stops counting as money you can spend. Add the monthly payment on its page afterwards."
        }
        if account.kind.isLiability && !kind.isLiability {
            return "What you owed becomes money you have. Its monthly payment is removed from your bills."
        }
        if kind == .lent {
            return "What's here becomes what they owe you. It stays in your net worth but stops counting as money you can spend."
        }
        return "Balances stay as they are."
    }

    private func save() {
        error = nil
        do {
            try store.changeAccountType(account.id, to: kind, movingEntriesTo: moveTo)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
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

// MARK: - Starting amount

/// Fixes the balance an account was added with. Entries since then stay; today's balance moves by the difference.
struct StartingAmountSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: LedgerAccountRecord

    @State private var amountText = ""
    @State private var error: String?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var isDebt: Bool { account.kind.isLiability }
    private var opening: EntryRecord? { store.openingEntry(for: account.id) }
    private var recorded: Money { opening?.entry.amount(on: account.id) ?? .zero(store.currency) }

    /// As stored: a debt's starting amount is negative
    private var entered: Money? {
        guard let value = MoneyFormat.parse(amountText.isEmpty ? "0" : amountText, currency: store.currency) else { return nil }
        return isDebt ? value.magnitude.negated : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(isDebt ? "Owed when added" : "Balance when added")
                        Spacer()
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .keyboardType(isDebt ? .decimalPad : .numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 130)
                            .accessibilityIdentifier("startingAmount")
                    }
                } footer: {
                    Text(opening.map { "Added on \($0.date.formatted(date: .long, time: .omitted)). " } ?? "")
                         + Text("Everything recorded since stays as it is.")
                }
                if let entered, entered != recorded {
                    let now = snapshot.balance(account.id) - recorded + entered
                    Section {
                        LabeledContent(isDebt ? "You'll owe now" : "Balance now", value: (isDebt ? now.negated : now).compact).bold()
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Starting amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("saveStartingAmount") }
            }
            .onAppear {
                amountText = MoneyFormat.editable(isDebt ? recorded.magnitude : recorded, emptyWhenZero: true)
            }
        }
    }

    private func save() {
        guard let entered else { error = "Enter the amount as a number."; return }
        do {
            try store.correctOpeningBalance(account.id, to: entered)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

/// Someone who owes you money: lend more, record what they pay back, or let the rest go
struct LentSection: View {
    let person: LedgerAccountRecord
    let balance: Money
    @Binding var sheet: LentSheet.Action?

    var body: some View {
        Section {
            Button { sheet = .lend } label: { Label("Lend more", systemImage: "arrow.up.right") }
                .accessibilityIdentifier("lendMore")
            if balance.isPositive {
                Button { sheet = .repaid } label: { Label("They paid some back", systemImage: "arrow.down.left") }
                    .accessibilityIdentifier("paidBack")
                Button { sheet = .forgive } label: { Label("They won't pay it back", systemImage: "hand.raised") }
                    .accessibilityIdentifier("forgive")
            }
        } footer: {
            Text("Money lent isn't spending: it leaves your accounts but stays yours until it's paid back. If it won't be, it counts as spent on \(person.name).")
        }
    }
}

struct LentSheet: View {
    enum Action: String, Identifiable { case lend, repaid, forgive; var id: String { rawValue } }

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: LedgerAccountRecord
    let action: Action

    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = Date()
    @State private var error: String?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var owed: Money { snapshot.balance(person.id) }
    private var accounts: [LedgerAccountRecord] {
        snapshot.accounts.filter { !$0.archived && $0.kind != .lent && (action == .repaid ? $0.kind.isBalanceSheet : $0.kind.isAsset) }
    }

    private var title: String {
        switch action {
        case .lend: return "Lend to \(person.name)"
        case .repaid: return "Paid back"
        case .forgive: return "Won't be paid back"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("0", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("lentAmount")
                    }
                    if action != .forgive {
                        Picker(action == .lend ? "From" : "Into", selection: $accountId) {
                            ForEach(accounts, id: \.id) { Label($0.name, systemImage: $0.icon).tag($0.id as UUID?) }
                        }
                    }
                    DatePicker("On", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text(footer)
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("saveLent") }
            }
            .onAppear {
                if action != .lend, owed.isPositive { amountText = MoneyFormat.editable(owed) }
                let last = store.settings.lastUsedAccountId
                accountId = accounts.first { $0.id == last }?.id ?? accounts.first { $0.spendable }?.id ?? accounts.first?.id
            }
        }
    }

    private var footer: String {
        switch action {
        case .lend: return "\(person.name) will owe you this. It isn't counted as spending."
        case .repaid: return "\(person.name) owes you \(owed.compact)."
        case .forgive: return "It stops counting as owed and is counted as spent, under \(store.peopleCategory.name)."
        }
    }

    private func save() {
        error = nil
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency), amount.isPositive else {
            error = "Enter an amount greater than zero."; return
        }
        do {
            switch action {
            case .lend:
                guard let accountId else { error = "Choose where the money came from."; return }
                try store.lend(amount, to: person.id, from: accountId, date: date)
            case .repaid:
                guard let accountId else { error = "Choose where the money went."; return }
                try store.receiveRepayment(amount, from: person.id, into: accountId, date: date)
            case .forgive:
                try store.forgive(amount, owedBy: person.id, date: date)
            }
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
