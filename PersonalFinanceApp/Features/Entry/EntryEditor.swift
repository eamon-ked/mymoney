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
    @Environment(PlusStore.self) private var plus
    @State private var paywall: PlusFeature?
    @Environment(\.dismiss) private var dismiss

    @State var kind: AddKind
    /// Set when editing an existing entry
    var editing: EntryRecord? = nil
    /// Fields already worked out elsewhere, e.g. by the guide from "I got my salary, 20,000"
    var prefill: DraftEntry? = nil

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
    /// "This pays Rent": off until the person ticks it
    @State private var paysBill = false
    @State private var didLoad = false
    @State private var categoryTouched = false
    // Apple Intelligence: a sentence read into the fields, and category guesses
    @State private var sentence = ""
    @State private var reading = false
    @State private var readNote: String?
    @State private var pendingDraft: DraftEntry?
    @State private var categorySuggested = false
    /// "Salary" was said: hand over to Payday, which uses the salary saved in Plan
    @State private var payday: PaydayRequest?
    @FocusState private var amountFocused: Bool

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var currency: String { store.currency }
    private var amount: Money? { MoneyFormat.parse(amountText, currency: currency) }

    var body: some View {
        if let payday {
            PaydaySheet(said: payday.said)
        } else {
            editor
        }
    }

    private var editor: some View {
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

                if editing == nil && kind != .adjustment && AppleIntelligence.isReady {
                    if plus.isPlus {
                        describeSection
                    } else {
                        Section {
                            Button { paywall = .appleIntelligence } label: {
                                HStack {
                                    AIBadge(text: "Describe it in a sentence")
                                    Spacer()
                                    PlusBadge()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if kind == .income && editing == nil && prefill == nil, let salary = PaydayPlan.salaryItem(snapshot) {
                    Section {
                        Button { payday = PaydayRequest(said: nil) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "banknote.fill").font(.title3).foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Is this your \(salary.name.lowercased())?").font(.body.weight(.semibold))
                                    Text("Use the \(salary.amount.compact) saved in your plan, into \(snapshot.account(salary.accountId)?.name ?? "your account")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("useSavedSalary")
                    }
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
                    // Any reason it didn't save, here where it's seen above the keyboard
                    FieldError(message: amountError ?? error)
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
                            TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                            if editing == nil && kind != .transfer {
                                Toggle("Repeats", isOn: $repeats)
                                if repeats {
                                    FrequencyPicker(frequency: $frequency)
                                    Text("Future ones are added to Plan as expected, not as money already \(kind == .income ? "received" : "spent").")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
            .paywall($paywall)
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
            .onChange(of: kind) { _, _ in
                categoryId = nil
                paysBill = false
                error = nil
                if let draft = pendingDraft { pendingDraft = nil; fill(from: draft) }
            }
            .task(id: memo) { await suggestCategory() }
        }
    }

    // MARK: - Fields per kind

    private var spendingAccounts: [LedgerAccountRecord] { snapshot.accounts }

    @ViewBuilder private var expenseFields: some View {
        Section("Spent on") {
            CategoryGrid(categories: snapshot.expenseCategories, usage: categoryUsage, selection: $categoryId, touched: $categoryTouched)
            if categorySuggested && !categoryTouched { AIBadge(text: "Category suggested by Apple Intelligence") }
        }
        Section {
            AccountPicker(title: "Paid from", accounts: spendingAccounts.filter { $0.kind != .lent }, selection: $accountId)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Description (e.g. Carrefour)", text: $memo)
                .accessibilityIdentifier("memoField")
        }
        billSection
    }

    @ViewBuilder private var incomeFields: some View {
        Section("Received as") {
            CategoryGrid(categories: snapshot.incomeCategories, usage: categoryUsage, selection: $categoryId, touched: $categoryTouched)
            if categorySuggested && !categoryTouched { AIBadge(text: "Category suggested by Apple Intelligence") }
        }
        Section {
            AccountPicker(title: "Paid into", accounts: spendingAccounts.filter { $0.kind != .lent }, selection: $accountId)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Description (e.g. October salary)", text: $memo)
        }
    }

    private var transferFooter: String {
        if let to = snapshot.account(toAccountId), to.kind == .lent {
            return "Lent to \(to.name): they'll owe you this. It isn't spending."
        }
        if let from = snapshot.account(accountId), from.kind == .lent {
            return "Paid back by \(from.name): it lowers what they owe you. It isn't income."
        }
        if snapshot.account(toAccountId)?.kind.isLiability == true {
            return "Pays down what you owe. It isn't spending: the purchases were counted when you made them."
        }
        return "Moves money between your own accounts. It isn't income or spending."
    }

    @ViewBuilder private var transferFields: some View {
        Section {
            AccountPicker(title: "From", accounts: spendingAccounts, selection: $accountId)
            AccountPicker(title: "To", accounts: spendingAccounts.filter { $0.id != accountId }, selection: $toAccountId)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Description (optional)", text: $memo)
        } footer: {
            Text(transferFooter)
        }
        billSection
    }

    /// The unpaid bill this money could be, from what's filled in so far
    private var billCandidate: (occurrence: Occurrence, item: PlannedItem, isPartial: Bool)? {
        guard kind == .expense || kind == .transfer, editing?.occurrenceId == nil,
              let amount, amount.isPositive, let accountId else { return nil }
        let to = snapshot.account(toAccountId)
        if kind == .transfer && to?.kind.isLiability != true { return nil }
        let payment = BillPayment(date: date, amount: amount, fromAccountId: accountId,
                                  categoryId: kind == .expense ? categoryId : nil,
                                  debtId: kind == .transfer ? to?.id : nil, memo: memo)
        let dismissed = Set(editing?.dismissedOccurrenceIds ?? [])
        return snapshot.billCandidates(for: payment).first { !dismissed.contains($0.occurrence.id) }
    }

    /// Asks, never assumes: linking marks the bill paid so it isn't held back or counted twice
    @ViewBuilder private var billSection: some View {
        if let bill = billCandidate {
            Section {
                Toggle(isOn: $paysBill) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.isPartial ? "Part of \(bill.item.name)" : "This pays \(bill.item.name)")
                        Text("\(bill.occurrence.remaining.formatted) due \(bill.occurrence.dueDate.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("paysBill")
            } footer: {
                Text(paysBill
                     ? (bill.isPartial
                        ? "\(bill.item.name) will show part paid, with \(((bill.occurrence.remaining - (amount ?? bill.occurrence.remaining))).formatted) left."
                        : "\(bill.item.name) will show paid, and won't be held back from Safe to spend again.")
                     : "Turn this on if it's the bill, so it isn't counted twice.")
            }
        }
    }

    /// How often each category was used lately, for putting the usual ones first
    private var categoryUsage: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for record in snapshot.entryRecords.prefix(200) where record.status == .posted {
            for line in record.lines where snapshot.account(line.accountId)?.kind.isCategory == true {
                counts[line.accountId, default: 0] += 1
            }
        }
        return counts
    }

    @ViewBuilder private var adjustmentFields: some View {
        Section {
            AccountPicker(title: "Account", accounts: spendingAccounts, selection: $accountId)
            if let id = accountId, let target = amount {
                let current = snapshot.balance(id)
                LabeledContent("Currently recorded", value: current.compact)
                LabeledContent("Change", value: (target - current).signed)
            }
            TextField("Reason (required)", text: $reason)
            DatePicker("As of", selection: $date, displayedComponents: .date)
        } footer: {
            Text("For corrections only. To check against a bank statement, use Check against a statement on the account instead.")
        }
    }

    @ViewBuilder private var describeSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("e.g. Lunch 45 at Shake Shack yesterday", text: $sentence, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit { Task { await readSentence() } }
                    .accessibilityIdentifier("describeField")
                if reading {
                    ProgressView()
                } else {
                    Button { Task { await readSentence() } } label: { Image(systemName: "sparkles").font(.title3) }
                        .buttonStyle(.borderless)
                        .disabled(sentence.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Fill in from description")
                }
            }
            if let readNote { Text(readNote).font(.caption).foregroundStyle(.secondary) }
        } header: {
            AIBadge(text: "Describe it")
        }
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
            // Focus once the sheet has finished presenting, or the keyboard never comes up
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                amountFocused = true
            }
            #if DEBUG
            // Test helper: -describe "Lunch 45 at Shake Shack yesterday"
            if let text = UserDefaults.standard.string(forKey: "describe") {
                sentence = text
                Task { await readSentence() }
            }
            #endif
            if let prefill { fill(from: prefill) }
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

    // MARK: - Apple Intelligence

    private func readSentence() async {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !reading else { return }
        // A salary is already set up in Plan: use it, never a guessed amount
        if PaydayPlan.mentionsSalary(text) {
            payday = PaydayRequest(said: AlertParser.spoken(text, homeCurrency: currency, date: Date())?.amount)
            return
        }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        reading = true
        readNote = nil
        defer { reading = false }
        do {
            var draft = try await MoneyAI.draft(from: text, categories: snapshot.expenseCategories.map(\.name),
                                                income: snapshot.incomeCategories.map(\.name),
                                                accounts: spendingAccounts.map(\.name), today: Date())
            // Only an amount that was actually said; the model sometimes invents one
            if !text.contains(where: \.isNumber) { draft.amount = nil }
            if draft.kind != kind {
                pendingDraft = draft
                kind = draft.kind
            } else {
                fill(from: draft)
            }
            readNote = "Filled in below. Check it, then tap Save."
        } catch {
            #if DEBUG
            print("MoneyAI.draft failed:", error)
            #endif
            readNote = AppleIntelligence.message(for: error)
        }
        #endif
    }

    private func fill(from draft: DraftEntry) {
        func named(_ name: String?, in list: [LedgerAccountRecord]) -> UUID? {
            guard let name = name?.lowercased(), !name.isEmpty else { return nil }
            return list.first { $0.name.lowercased() == name }?.id
        }
        if let value = draft.amount { amountText = MoneyFormat.editable(Money(value, currency: currency)) }
        let categories = kind == .income ? snapshot.incomeCategories : snapshot.expenseCategories
        if let id = named(draft.category, in: categories) {
            categoryId = id
            categoryTouched = true
            categorySuggested = false
        }
        if !draft.memo.isEmpty { memo = draft.memo }
        if let id = named(draft.account, in: spendingAccounts) ?? mentioned(in: sentence, excluding: draft.toAccount) { accountId = id }
        if kind == .transfer, let id = named(draft.toAccount, in: spendingAccounts.filter { $0.id != accountId }) { toAccountId = id }
        date = Calendar.current.date(byAdding: .day, value: -draft.daysAgo, to: Date()) ?? Date()
        amountFocused = false
    }

    /// An account the sentence names by a distinctive word ("my Mashreq card" → Mashreq Cashback)
    private func mentioned(in text: String, excluding other: String?) -> UUID? {
        let generic: Set<String> = ["card", "bank", "account", "current", "savings", "saving", "cash", "loan", "credit", "debit", "wallet"]
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return spendingAccounts.first { a in
            a.name != other && a.name.lowercased().split { !$0.isLetter && !$0.isNumber }
                .contains { $0.count >= 3 && !generic.contains(String($0)) && words.contains(String($0)) }
        }?.id
    }

    /// When past entries don't say, ask the model which category fits
    private func suggestCategory() async {
        guard editing == nil, !categoryTouched, kind == .expense || kind == .income, AppleIntelligence.isReady, plus.isPlus else { return }
        let text = memo.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3, categoryId == nil || categorySuggested else { return }
        let needle = text.lowercased()
        guard !snapshot.entryRecords.contains(where: { $0.status == .posted && $0.memo.lowercased().hasPrefix(needle) }) else { return }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        let wanted: AccountKind = kind == .income ? .income : .expense
        let categories = wanted == .income ? snapshot.incomeCategories : snapshot.expenseCategories
        var examples: [(String, String)] = []
        var seen = Set<String>()
        for record in snapshot.entryRecords where record.status == .posted && !seen.contains(record.memo.lowercased()) {
            guard let line = record.lines.first(where: { snapshot.account($0.accountId)?.kind == wanted }),
                  let name = snapshot.account(line.accountId)?.name, name != record.memo else { continue }
            seen.insert(record.memo.lowercased())
            examples.append((record.memo, name))
            if examples.count >= 12 { break }
        }
        guard let name = try? await MoneyAI.category(for: text, options: categories.map(\.name), examples: examples),
              !Task.isCancelled, !categoryTouched,
              let match = categories.first(where: { $0.name == name }) else { return }
        categoryId = match.id
        categorySuggested = true
        #endif
    }

    // MARK: - Saving

    /// Everything typed so far, as the store records it
    private var form: EntryForm {
        EntryForm(kind: kind, amount: amount, accountId: accountId, toAccountId: toAccountId, categoryId: categoryId,
                  memo: memo, notes: notes, date: date, reason: reason, repeats: editing == nil && repeats,
                  frequency: frequency, occurrenceId: paysBill ? billCandidate?.occurrence.id : nil, key: key)
    }

    private func save() {
        error = nil
        amountError = nil
        do { _ = try form.checkedAmount() } catch { amountError = error.localizedDescription; return }
        guard !saving else { return }
        saving = true
        do {
            try store.save(form, replacing: editing?.id)
            // Stays disabled: the sheet is closing and the key already saved it once
            dismiss()
        } catch {
            saving = false
            self.error = StoreError.from(error).errorDescription
            // The keyboard would hide the message and the choice it asks for
            amountFocused = false
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

/// The usual categories as large buttons that wrap, with every category behind "All categories"
struct CategoryGrid: View {
    let categories: [LedgerAccountRecord]
    var usage: [UUID: Int] = [:]
    @Binding var selection: UUID?
    @Binding var touched: Bool

    private static let shown = 8

    /// Most used first; the chosen one is always visible
    private var visible: [LedgerAccountRecord] {
        let ranked = categories.enumerated()
            .sorted { (usage[$0.element.id] ?? 0, -$0.offset) > (usage[$1.element.id] ?? 0, -$1.offset) }
            .map(\.element)
        var top = Array(ranked.prefix(Self.shown))
        if let selection, !top.contains(where: { $0.id == selection }), let chosen = categories.first(where: { $0.id == selection }) {
            top[top.count - 1] = chosen
        }
        return top
    }

    var body: some View {
        if categories.isEmpty {
            Text("No categories yet. Add some in Budget.").foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(visible, id: \.id) { c in
                    let selected = selection == c.id
                    Button {
                        selection = c.id
                        touched = true
                    } label: {
                        Label(c.name, systemImage: c.icon.isEmpty ? "tag.fill" : c.icon)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color(hex: c.colorHex) : Color.gray.opacity(0.15)))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("category-\(c.name)")
                }
            }
            .padding(.vertical, 4)
            if categories.count > Self.shown {
                NavigationLink {
                    CategoryList(categories: categories, selection: $selection, touched: $touched)
                } label: {
                    Text("All categories (\(categories.count))")
                }
            }
        }
    }
}

/// Every category, searchable
struct CategoryList: View {
    let categories: [LedgerAccountRecord]
    @Binding var selection: UUID?
    @Binding var touched: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let shown = search.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
        List(shown, id: \.id) { c in
            Button {
                selection = c.id
                touched = true
                dismiss()
            } label: {
                HStack {
                    ListRow(title: c.name, symbol: c.icon.isEmpty ? "tag.fill" : c.icon, color: Color(hex: c.colorHex)) { EmptyView() }
                    if selection == c.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $search)
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
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
