//
//  EntryEditor.swift
//  Nokael Money
//
//  Quick add and edit for expenses, income, transfers and balance adjustments.
//  The amount is focused first; account, category and date are prefilled from
//  what the person used last, and everything else sits under More options.
//

import SwiftUI
import NokaelCore

struct EntryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var kind: AddKind
    /// Set when editing an existing entry
    var editing: EntryRecord? = nil

    // One key per editor session: a double tap or retry can't save twice
    @State private var key = UUID()
    @State private var amountText = ""
    @State private var memo = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var accountId: UUID?
    @State private var toAccountId: UUID?
    @State private var categoryId: UUID?
    @State private var reason = ""
    @State private var showMore = false
    @State private var repeats = false
    @State private var frequency: Frequency = .monthly(every: 1)
    @State private var error: String?
    @State private var amountError: String?
    @State private var saving = false
    @State private var didLoad = false
    @State private var categoryTouched = false
    @FocusState private var amountFocused: Bool

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var currency: String { store.currency }
    private var amount: Money? { MoneyFormat.parse(amountText, currency: currency) }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil && kind != .adjustment {
                    Picker("Type", selection: $kind) {
                        ForEach([AddKind.expense, .income, .transfer]) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(currency).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .keyboardType(kind == .adjustment ? .numbersAndPunctuation : .decimalPad)
                            .focused($amountFocused)
                            .accessibilityLabel(kind == .adjustment ? "Correct balance" : "Amount")
                            .accessibilityIdentifier("amountField")
                    }
                    FieldError(message: amountError)
                } header: {
                    Text(kind == .adjustment ? "What the account really holds" : "Amount")
                }

                switch kind {
                case .expense: expenseFields
                case .income: incomeFields
                case .transfer: transferFields
                case .adjustment: adjustmentFields
                }

                if kind != .adjustment {
                    Section {
                        DisclosureGroup("More options", isExpanded: $showMore) {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                            TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                            if editing == nil && kind != .transfer {
                                Toggle("Repeats", isOn: $repeats)
                                if repeats {
                                    FrequencyPicker(frequency: $frequency)
                                    Text("Future ones are added to Plan as expected, not as money already \(kind == .income ? "received" : "spent").")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let error {
                    Section { FieldError(message: error) }
                }

                if let editing {
                    Section {
                        Button("Delete", role: .destructive) { delete(editing) }
                    } footer: {
                        Text("Deleting keeps a record in the change history, and balances update straight away.")
                    }
                }
            }
            .navigationTitle(editing == nil ? kind.title : "Edit \(kind.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(saving)
                        .accessibilityIdentifier("saveEntry")
                }
            }
            .onAppear(perform: load)
            .onChange(of: memo) { _, text in suggestFromHistory(text) }
            .onChange(of: kind) { _, _ in categoryId = nil; error = nil }
        }
    }

    // MARK: - Fields per kind

    private var spendingAccounts: [LedgerAccountRecord] { snapshot.accounts }

    @ViewBuilder private var expenseFields: some View {
        Section("Spent on") {
            CategoryChips(categories: snapshot.expenseCategories, selection: $categoryId, touched: $categoryTouched)
            TextField("Description (e.g. Carrefour)", text: $memo)
                .accessibilityIdentifier("memoField")
        }
        Section {
            AccountPicker(title: "Paid from", accounts: spendingAccounts, selection: $accountId)
            if !showMore { LabeledContent("Date", value: dateLabel) }
        }
    }

    @ViewBuilder private var incomeFields: some View {
        Section("Received as") {
            CategoryChips(categories: snapshot.incomeCategories, selection: $categoryId, touched: $categoryTouched)
            TextField("Description (e.g. October salary)", text: $memo)
        }
        Section {
            AccountPicker(title: "Paid into", accounts: spendingAccounts, selection: $accountId)
            if !showMore { LabeledContent("Date", value: dateLabel) }
        }
    }

    @ViewBuilder private var transferFields: some View {
        Section {
            AccountPicker(title: "From", accounts: spendingAccounts, selection: $accountId)
            AccountPicker(title: "To", accounts: spendingAccounts.filter { $0.id != accountId }, selection: $toAccountId)
            TextField("Description (optional)", text: $memo)
            if !showMore { LabeledContent("Date", value: dateLabel) }
        } footer: {
            Text("Moves money between your own accounts. It isn't income or spending.")
        }
    }

    @ViewBuilder private var adjustmentFields: some View {
        Section {
            AccountPicker(title: "Account", accounts: spendingAccounts, selection: $accountId)
            if let id = accountId, let target = amount {
                let current = snapshot.balance(id)
                LabeledContent("Currently recorded", value: current.formatted)
                LabeledContent("Change", value: (target - current).signed)
            }
            TextField("Reason (required)", text: $reason)
            DatePicker("As of", selection: $date, displayedComponents: .date)
        } footer: {
            Text("For corrections only. To check against a bank statement, use Reconcile on the account instead.")
        }
    }

    private var dateLabel: String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Loading and suggestions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let editing {
            let entry = editing.entry
            amountText = MoneyFormat.editable(entry.lines.filter { $0.amount.isPositive }.map(\.amount).sum(currency))
            memo = editing.memo
            notes = editing.notes
            date = editing.date
            let sheet = entry.lines.filter { snapshot.account($0.accountId)?.kind.isBalanceSheet == true }
            let category = entry.lines.first { snapshot.account($0.accountId)?.kind.isCategory == true }
            categoryId = category?.accountId
            categoryTouched = true
            switch kind {
            case .transfer:
                accountId = sheet.first { $0.amount.isNegative }?.accountId
                toAccountId = sheet.first { $0.amount.isPositive }?.accountId
            default:
                accountId = sheet.first?.accountId
            }
            showMore = !notes.isEmpty
        } else {
            accountId = store.settings.lastUsedAccountId.flatMap { id in spendingAccounts.first { $0.id == id }?.id }
                ?? spendingAccounts.first { $0.kind.defaultSpendable }?.id ?? spendingAccounts.first?.id
            amountFocused = true
        }
    }

    /// Same description as before → same category and account as last time
    private func suggestFromHistory(_ text: String) {
        guard editing == nil, !categoryTouched else { return }
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3 else { return }
        let wanted: AccountKind = kind == .income ? .income : .expense
        guard let match = snapshot.entryRecords.first(where: {
            $0.status == .posted && $0.memo.lowercased().hasPrefix(needle)
        }) else { return }
        if let line = match.lines.first(where: { snapshot.account($0.accountId)?.kind == wanted }) {
            categoryId = line.accountId
        }
    }

    // MARK: - Saving

    private func save() {
        error = nil
        amountError = nil
        guard let amount else { amountError = "Enter an amount."; return }
        if kind != .adjustment && !amount.isPositive { amountError = "Enter an amount greater than zero."; return }
        saving = true
        defer { saving = false }
        do {
            let entry = try buildEntry(amount)
            if let editing {
                try store.replace(editing.id, with: entry, notes: notes)
            } else {
                try store.post(entry, notes: notes)
                if repeats { try saveRepeat(amount) }
            }
            dismiss()
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    private func buildEntry(_ amount: Money) throws -> Entry {
        let title = memo.trimmingCharacters(in: .whitespaces)
        guard let account = snapshot.account(accountId)?.info else {
            throw StoreError.invalid(snapshot.hasAccounts ? "Choose an account." : "Add an account first.")
        }
        switch kind {
        case .expense:
            guard let category = snapshot.account(categoryId)?.info else { throw StoreError.invalid("Choose what it was for.") }
            return try EntryFactory.expense(amount, from: account, category: category, date: date,
                                            memo: title.isEmpty ? category.name : title, key: key)
        case .income:
            guard let category = snapshot.account(categoryId)?.info else { throw StoreError.invalid("Choose the kind of income.") }
            return try EntryFactory.income(amount, to: account, category: category, date: date,
                                           memo: title.isEmpty ? category.name : title, key: key)
        case .transfer:
            guard let to = snapshot.account(toAccountId)?.info else { throw StoreError.invalid("Choose where the money goes.") }
            return try EntryFactory.transfer(amount, from: account, to: to, date: date,
                                             memo: title.isEmpty ? "Transfer to \(to.name)" : title, key: key)
        case .adjustment:
            let delta = amount - snapshot.ledger.balance(of: account.id, asOf: date)
            guard !delta.isZero else { throw StoreError.invalid("That's already the recorded balance.") }
            return try EntryFactory.adjustment(delta, account: account, equity: store.equityAccount.info, date: date,
                                               reason: reason, key: key)
        }
    }

    private func saveRepeat(_ amount: Money) throws {
        guard let next = Calendar.current.date(byAdding: nextStep, to: date) else { return }
        let item = PlannedItem(name: memo.isEmpty ? (snapshot.account(categoryId)?.name ?? kind.title) : memo,
                               direction: kind == .income ? .inflow : .outflow, amount: amount,
                               schedule: Schedule(start: next, frequency: frequency),
                               accountId: accountId, categoryId: categoryId)
        try store.savePlannedItem(item)
    }

    private var nextStep: DateComponents {
        switch frequency {
        case .weekly(let n): return DateComponents(day: 7 * n)
        case .monthly(let n): return DateComponents(month: n)
        case .quarterly: return DateComponents(month: 3)
        case .annually: return DateComponents(year: 1)
        case .everyDays(let n): return DateComponents(day: n)
        }
    }

    private func delete(_ record: EntryRecord) {
        do {
            try store.void(record.id)
            dismiss()
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }
}

// MARK: - Pickers

struct AccountPicker: View {
    let title: String
    let accounts: [LedgerAccountRecord]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Choose…").tag(nil as UUID?)
            ForEach(accounts, id: \.id) { a in
                Label(a.name, systemImage: a.icon).tag(a.id as UUID?)
            }
        }
    }
}

/// Large tappable category choices, with the full list behind "More"
struct CategoryChips: View {
    let categories: [LedgerAccountRecord]
    @Binding var selection: UUID?
    @Binding var touched: Bool

    var body: some View {
        if categories.isEmpty {
            Text("No categories yet. Add some in Budget.").foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.id) { c in
                        let selected = selection == c.id
                        Button {
                            selection = c.id
                            touched = true
                        } label: {
                            Label(c.name, systemImage: c.icon.isEmpty ? "tag.fill" : c.icon)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Color(hex: c.colorHex) : Color.gray.opacity(0.15)))
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("category-\(c.name)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct FrequencyPicker: View {
    @Binding var frequency: Frequency

    private let options: [Frequency] = [.weekly(every: 1), .weekly(every: 2), .monthly(every: 1), .quarterly, .annually]

    var body: some View {
        Picker("How often", selection: $frequency) {
            ForEach(options, id: \.self) { Text($0.label).tag($0) }
        }
    }
}
