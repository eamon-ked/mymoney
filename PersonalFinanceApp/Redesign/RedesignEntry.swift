//
//  RedesignEntry.swift
//  Nokael Money
//
//  Adding and editing an expense, income, transfer or balance correction,
//  the transaction page, and checking entries saved automatically.
//

import SwiftUI
import NokaelCore

extension Redesign {
    /// The one form for adding or editing an entry. Editing fills it with what was recorded and saves a
    /// replacement, so the change shows in the entry's history.
    struct EntryFormView: View {
        @Environment(AppModel.self) private var app
        @State private var kind: FormKind
        let editing: EntryRecord?

        @State private var key = UUID()
        @State private var amount = ""
        @State private var memo = ""
        @State private var notes = ""
        @State private var reason = ""
        @State private var date = Date()
        @State private var accountId: UUID?
        @State private var toAccountId: UUID?
        @State private var categoryId: UUID?
        @State private var repeats = false
        @State private var frequency: Frequency = .monthly(every: 1)
        @State private var paysBill = false
        @State private var problem: String?
        @State private var saving = false
        @State private var loaded = false
        @State private var categoryTouched = false
        @State private var sentence = ""
        @State private var reading = false
        @State private var readNote: String?
        @State private var splitting = false
        @State private var shares: [ShareRow] = []

        /// Someone's part of a split bill: a person already in People, or a new name
        struct ShareRow: Identifiable {
            let id = UUID()
            var personId: UUID?
            var name = ""
            var amount = ""
        }

        init(kind: FormKind) {
            _kind = State(initialValue: kind)
            editing = nil
        }

        init(editing record: EntryRecord, splitting: Bool = false) {
            _splitting = State(initialValue: splitting)
            let kind: FormKind = switch record.kind {
            case .income: .income
            case .transfer: .transfer
            case .adjustment, .reconciliation: .adjustment
            default: .expense
            }
            _kind = State(initialValue: kind)
            editing = record
        }

        private var addKind: AddKind {
            switch kind {
            case .income: .income
            case .transfer: .transfer
            case .adjustment: .adjustment
            default: .expense
            }
        }

        private var money: Money? { app.parse(amount) }
        private var fromAccounts: [Account] { app.accounts.filter { $0.kind != .lent } }
        /// An expense can also be one a friend paid for you
        private var payers: [Account] { kind == .expense ? fromAccounts + app.lent : fromAccounts }
        private var friendPaid: Bool { kind == .expense && app.account(accountId)?.kind == .lent }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if editing == nil && kind != .adjustment {
                    Pills(options: ["Expense", "Income", "Transfer"], selection: Binding(
                        get: { kind == .income ? "Income" : kind == .transfer ? "Transfer" : "Expense" },
                        set: { kind = $0 == "Income" ? .income : $0 == "Transfer" ? .transfer : .expense; categoryId = nil; defaultCategory() }))
                }
                if editing == nil && kind != .adjustment { describe }
                AmountBox(label: kind == .adjustment ? "What the account really holds, in \(app.currency)" : "Amount in \(app.currency)",
                          text: $amount)
                if kind != .transfer && kind != .adjustment {
                    Field(label: kind == .income ? "Where did it come from?" : "What was it for?") {
                        TextField(kind == .income ? "e.g. Monthly salary" : "e.g. Coffee with a friend", text: $memo)
                            .accessibilityIdentifier("memoField")
                            .onChange(of: memo) { suggestFromHistory() }
                    }
                }
                if kind == .income, editing == nil, let salary = PaydayPlan.salaryItem(app.snapshot) {
                    Button { app.open(.payday) } label: {
                        Label("Is this your \(app.hidesDetails ? "salary" : salary.name.lowercased())? Use Payday", systemImage: "arrow.down.left")
                            .rdText(.captionStrong).foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("useSavedSalary")
                }
                AccountChoice(label: kind == .transfer ? "From account" : kind == .income ? "Paid into" : kind == .adjustment ? "Account" : "Paid from",
                              selection: $accountId, accounts: payers)
                if friendPaid {
                    Redesign.explainer("\(app.accountLabel(accountId)) paid. It counts as your spending, and you'll owe them this amount.")
                }
                if kind == .expense && !friendPaid { split }
                if kind == .transfer {
                    AccountChoice(label: "To account", selection: $toAccountId, accounts: app.accounts.filter { $0.id != accountId })
                    Redesign.explainer("Money moves between your own accounts. Total cash and safe to spend stay the same. Paying a card or a loan, or money lent and paid back, counts here too. This is a record only, not a bank transfer.")
                } else if kind == .adjustment {
                    if let id = accountId, let target = money {
                        let current = app.snapshot.balance(id)
                        DetailCard {
                            DetailRow(label: "Currently recorded", value: app.money(current))
                            DetailRow(label: "Change", value: (target.minorUnits >= current.minorUnits ? "+" : "−") + " " + app.money((target - current).magnitude))
                        }
                    }
                    Field(label: "Reason (needed)") { TextField("e.g. Bank fee I missed", text: $reason) }
                    Redesign.explainer("For corrections only. To check against a bank statement, open the account and choose Check against a statement.")
                } else {
                    CategoryChoice(label: "Category", selection: Binding(get: { categoryId }, set: { categoryId = $0; categoryTouched = true }),
                                   categories: kind == .income ? app.snapshot.incomeCategories.filter { !$0.archived } : app.expenseChoices())
                }
                Field(label: kind == .adjustment ? "As of" : "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                }
                billToggle
                if kind != .adjustment {
                    Field(label: "Note (optional)") { TextField("A little context, if you'd like", text: $notes) }
                }
                if editing == nil && (kind == .expense || kind == .income) {
                    ToggleRow(title: "Repeats", detail: repeats ? "Added to your regular \(kind == .income ? "income" : "bills") from the next date." : nil,
                              isOn: $repeats)
                        .accessibilityIdentifier("Repeats")
                    if repeats {
                        Field(label: "How often") { Choice(value: $frequency, options: Redesign.frequencies) { $0.label } }
                    }
                }
                Problem(text: problem)
                Button(action: submit) {
                    Text(saving ? "Saving…" : editing != nil ? "Save changes" : kind == .transfer ? "Record transfer" : kind == .adjustment ? "Correct balance" : "Save transaction")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving)
                .accessibilityIdentifier("saveEntry")
                if let editing {
                    Button(role: .destructive) { delete(editing) } label: { Text("Delete transaction").foregroundStyle(Theme.destructive) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .onAppear(perform: load)
        }

        // MARK: Describe it

        @ViewBuilder private var describe: some View {
            if AppleIntelligence.isReady {
                // Free includes a few uses a month; the note stays to say how many are left
                if app.isPlus || FreeAllowance.describe.left > 0 || readNote != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            IntelligenceMark(size: 22)
                            TextField("Describe it: lunch 45 yesterday", text: $sentence, axis: .vertical)
                                .lineLimit(1...3).rdText(.body).submitLabel(.done)
                                .onSubmit { Task { await read() } }
                                .accessibilityIdentifier("describeField")
                            if reading { ProgressView() } else {
                                Button { Task { await read() } } label: { Image(systemName: "arrow.right.circle") }
                                    .disabled(sentence.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .accessibilityLabel("Fill in from description")
                            }
                        }
                        if let readNote { Text(readNote).rdText(.caption).foregroundStyle(Theme.muted) }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
                } else {
                    Button { app.open(.paywall(.appleIntelligence)) } label: {
                        HStack(spacing: 8) {
                            IntelligenceMark(size: 22)
                            Text("Describe it in a sentence").rdText(.detail)
                            PlusTag()
                            Spacer()
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private func read() async {
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !reading else { return }
            // A salary is already set up: use it rather than a guessed amount
            if PaydayPlan.mentionsSalary(text), PaydayPlan.salaryItem(app.snapshot) != nil {
                app.open(.payday)
                return
            }
            if !app.isPlus && FreeAllowance.describe.left == 0 { app.open(.paywall(.appleIntelligence)); return }
            #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else { return }
            reading = true
            readNote = nil
            defer { reading = false }
            do {
                var draft = try await MoneyAI.draft(from: text, categories: app.snapshot.expenseCategories.map(\.name),
                                                    income: app.snapshot.incomeCategories.map(\.name),
                                                    accounts: fromAccounts.map(\.name), today: Date())
                // Only an amount that was actually said; the model sometimes invents one
                if !text.contains(where: \.isNumber) { draft.amount = nil }
                fill(draft)
                readNote = "Filled in below. Check it, then save."
                if !app.isPlus {
                    FreeAllowance.describe.spend()
                    readNote = "Filled in below. Check it, then save. " + FreeAllowance.describe.leftText("use") + "."
                }
            } catch {
                readNote = AppleIntelligence.message(for: error)
            }
            #endif
        }

        private func fill(_ draft: DraftEntry) {
            kind = draft.kind == .income ? .income : draft.kind == .transfer ? .transfer : .expense
            func named(_ name: String?, in list: [(UUID, String)]) -> UUID? {
                guard let name = name?.lowercased(), !name.isEmpty else { return nil }
                return list.first { $0.1.lowercased() == name }?.0
            }
            if let value = draft.amount { amount = MoneyFormat.editable(Money(value, currency: app.currency)) }
            let categories = (kind == .income ? app.snapshot.incomeCategories : app.snapshot.expenseCategories).map { ($0.id, $0.name) }
            if let id = named(draft.category, in: categories) { categoryId = id; categoryTouched = true }
            if !draft.memo.isEmpty { memo = draft.memo }
            let accounts = fromAccounts.map { ($0.id, $0.name) }
            if let id = named(draft.account, in: accounts) { accountId = id }
            if kind == .transfer, let id = named(draft.toAccount, in: accounts.filter { $0.0 != accountId }) { toAccountId = id }
            date = app.calendar.date(byAdding: .day, value: -draft.daysAgo, to: Date()) ?? Date()
        }

        // MARK: Bills

        /// The unpaid bill this money could be, from what's filled in so far
        private var candidate: (occurrence: Occurrence, item: PlannedItem, isPartial: Bool)? {
            guard kind == .expense || kind == .transfer, editing?.occurrenceId == nil,
                  let money, money.isPositive, let accountId else { return nil }
            let to = app.record(toAccountId)
            if kind == .transfer && to?.kind.isLiability != true { return nil }
            let payment = BillPayment(date: date, amount: money, fromAccountId: accountId,
                                      categoryId: kind == .expense ? categoryId : nil,
                                      debtId: kind == .transfer ? to?.id : nil, memo: memo)
            let dismissed = Set(editing?.dismissedOccurrenceIds ?? [])
            return app.snapshot.billCandidates(for: payment).first { !dismissed.contains($0.occurrence.id) }
        }

        @ViewBuilder private var billToggle: some View {
            if let bill = candidate {
                ToggleRow(title: bill.isPartial ? "Part of \(app.hidesDetails ? "a bill" : bill.item.name)" : "This pays \(app.hidesDetails ? "a bill" : bill.item.name)",
                          detail: "\(app.money(bill.occurrence.remaining)) due \(app.day(bill.occurrence.dueDate)). Turn on if it's the bill, so it isn't counted twice.",
                          isOn: $paysBill)
                    .accessibilityIdentifier("paysBill")
            }
        }

        // MARK: Splitting

        /// Part of a bill others will pay back: their shares become what they owe you; only your share is spending
        @ViewBuilder private var split: some View {
            ToggleRow(title: "Split with others", detail: splitting ? nil : "Others will pay you back their part.",
                      isOn: Binding(get: { splitting }, set: { on in
                          withAnimation(.snappy) {
                              splitting = on
                              if on && shares.isEmpty { shares = [ShareRow(personId: app.lent.first?.id)] }
                          }
                      }))
                .accessibilityIdentifier("splitToggle")
            if splitting {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($shares) { $row in
                        HStack(alignment: .bottom, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Choice(value: $row.personId, options: app.lent.map { Optional($0.id) } + [nil]) { id in
                                    id.map { app.accountLabel($0) } ?? "Someone new"
                                }
                                if row.personId == nil {
                                    TextField("Their name", text: $row.name).accessibilityIdentifier("shareName")
                                }
                            }
                            TextField("0", text: $row.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 96).accessibilityIdentifier("shareAmount")
                            Button { withAnimation(.snappy) { shares.removeAll { $0.id == row.id }; if shares.isEmpty { splitting = false } } } label: {
                                Image(systemName: "minus.circle").foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain).accessibilityLabel("Remove")
                        }
                        Redesign.hairline
                    }
                    HStack {
                        Button("Add person") { withAnimation(.snappy) { shares.append(ShareRow()) } }
                            .accessibilityIdentifier("addShare")
                        Spacer()
                        Button("Split evenly", action: splitEvenly).accessibilityIdentifier("splitEvenly")
                    }
                    .rdText(.captionStrong).foregroundStyle(Theme.primary).buttonStyle(.plain)
                    if let mine = myShare {
                        Text(private: "Your share \(app.money(mine)). Only this counts as spending.")
                            .rdText(.caption).foregroundStyle(mine.isPositive ? Theme.muted : Theme.destructive)
                    }
                }
                .rdPanel(padding: 14)
            }
        }

        private var myShare: Money? {
            guard let total = money else { return nil }
            return total - shares.compactMap { app.parse($0.amount) }.sum(total.currency)
        }

        /// The total shared between you and everyone listed; any odd cent stays with you
        private func splitEvenly() {
            guard let total = money, total.isPositive, !shares.isEmpty else { problem = "Enter the amount first."; return }
            let each = total.minorUnits / Int64(shares.count + 1)
            for i in shares.indices { shares[i].amount = MoneyFormat.editable(Money(minorUnits: each, currency: total.currency)) }
        }

        /// People's shares, opening an account for anyone new; throws a message for the form
        private func resolvedShares() throws -> [(personId: UUID, amount: Money)] {
            guard kind == .expense, splitting, !friendPaid else { return [] }
            return try shares.compactMap { row in
                guard !row.amount.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                guard let value = app.parse(row.amount), value.isPositive else { throw StoreError.invalid("Enter each person's share as a number.") }
                if let id = row.personId { return (id, value) }
                let name = row.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { throw StoreError.invalid("Add a name for each person.") }
                return (try app.store.lentAccount(named: name).id, value)
            }
        }

        // MARK: Loading and suggestions

        private func load() {
            guard !loaded else { return }
            loaded = true
            if let editing {
                let entry = editing.entry
                let s = app.snapshot
                if kind == .adjustment {
                    let line = entry.lines.first { s.account($0.accountId)?.kind.isBalanceSheet == true }
                    accountId = line?.accountId
                    amount = accountId.map { MoneyFormat.editable(s.balance($0)) } ?? ""
                    reason = editing.notes
                } else {
                    amount = MoneyFormat.editable(entry.lines.filter { $0.amount.isPositive }.map(\.amount).sum(app.currency))
                    let sheet = entry.lines.filter { s.account($0.accountId)?.kind.isBalanceSheet == true }
                    categoryId = entry.lines.first { s.account($0.accountId)?.kind.isCategory == true }?.accountId
                    if kind == .transfer {
                        accountId = sheet.first { $0.amount.isNegative }?.accountId
                        toAccountId = sheet.first { $0.amount.isPositive }?.accountId
                    } else {
                        // A split bill: your account paid, and people's lines are what they owe back
                        let people = sheet.filter { s.account($0.accountId)?.kind == .lent && $0.amount.isPositive }
                        accountId = sheet.first { !people.map(\.accountId).contains($0.accountId) }?.accountId
                        if kind == .expense && !people.isEmpty {
                            shares = people.map { ShareRow(personId: $0.accountId, amount: MoneyFormat.editable($0.amount)) }
                            splitting = true
                        }
                        if splitting && shares.isEmpty { shares = [ShareRow(personId: app.lent.first?.id)] }
                    }
                }
                memo = editing.memo
                notes = editing.notes
                date = editing.date
                categoryTouched = true
            } else {
                let last = app.store.settings.lastUsedAccountId
                accountId = fromAccounts.first { $0.id == last }?.id ?? fromAccounts.first { $0.kind == .bank || $0.kind == .cash }?.id
                    ?? fromAccounts.first?.id
                if let draft = app.draft {
                    app.draft = nil
                    fill(draft)
                }
                defaultCategory()
                #if DEBUG
                // Test helper: -describe "Lunch 45 at Shake Shack yesterday"
                if let text = UserDefaults.standard.string(forKey: "describe") {
                    sentence = text
                    Task { await read() }
                }
                #endif
            }
        }

        /// Income starts on the first income category; spending waits to be chosen or suggested
        private func defaultCategory() {
            if kind == .income, categoryId == nil { categoryId = app.snapshot.incomeCategories.first { !$0.archived }?.id }
        }

        /// Same description as before → same category as last time
        private func suggestFromHistory() {
            guard editing == nil, !categoryTouched else { return }
            let needle = memo.trimmingCharacters(in: .whitespaces).lowercased()
            guard needle.count >= 3 else { return }
            let wanted: AccountKind = kind == .income ? .income : .expense
            let s = app.snapshot
            guard let match = s.entryRecords.first(where: { $0.status == .posted && $0.memo.lowercased().hasPrefix(needle) }),
                  let line = match.lines.first(where: { s.account($0.accountId)?.kind == wanted }) else { return }
            categoryId = line.accountId
        }

        // MARK: Saving

        private func submit() {
            problem = nil
            var form = EntryForm(kind: addKind, amount: money, accountId: accountId, toAccountId: toAccountId, categoryId: categoryId,
                                 memo: memo, notes: kind == .adjustment ? "" : notes, date: date, reason: reason,
                                 repeats: editing == nil && repeats, frequency: frequency,
                                 occurrenceId: paysBill ? candidate?.occurrence.id : (editing?.occurrenceId), key: key)
            do { _ = try form.checkedAmount() } catch { problem = error.localizedDescription; return }
            if splitting && !friendPaid, let mine = myShare, !mine.isPositive {
                problem = "Others' shares must add up to less than the total. To lend all of it, use I lent someone money."; return
            }
            guard !saving else { return }
            do { form.shares = try resolvedShares() } catch { problem = error.localizedDescription; return }
            saving = true
            problem = app.save(form, replacing: editing?.id)
            if problem != nil { saving = false }
        }

        private func delete(_ record: EntryRecord) {
            problem = app.attempt("Transaction deleted.") { try app.store.void(record.id) }
        }
    }
}

// MARK: - Transaction page

extension Redesign {
    struct TransactionPage: View {
        let t: Transaction
        @Environment(AppModel.self) private var app
        @State private var problem: String?
        @State private var askingName = false
        @State private var personName = ""
        @State private var confirmDelete = false

        var body: some View {
            let record = app.entry(t.id)
            HStack(spacing: 12) {
                IconBox(app.icon(of: t))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name(of: t)).rdText(.cardTitle).strikethrough(t.voided)
                    Text(t.voided ? "Deleted" : t.typeName + (t.source.map { " · from \($0)" } ?? "")).rdText(.detail).foregroundStyle(Theme.muted)
                }
            }
            Text(private: (t.flow == .in ? "+" : t.flow == .out ? "−" : "") + app.money(t.amount))
                .rdText(.display)
                .foregroundStyle(t.flow == .in ? Theme.primary : Theme.foreground)
                .strikethrough(t.voided)
                .padding(.vertical, 28)

            if let record, let parts = app.store.debtPaymentParts(record) {
                DetailCard {
                    DetailRow(label: "Date", value: app.fullDay(t.date))
                    DetailRow(label: "From", value: app.accountLabel(parts.funding.id))
                    DetailRow(label: "Came off \(app.accountLabel(parts.debt.id))", value: app.money(parts.principal))
                    DetailRow(label: "Interest", value: app.money(parts.interest))
                    if parts.fees.isPositive { DetailRow(label: "Fees", value: app.money(parts.fees)) }
                    DetailRow(label: "You owe now", value: app.money(app.snapshot.owed(parts.debt.id)))
                }
            } else {
                DetailCard {
                    DetailRow(label: "Date", value: app.fullDay(t.date))
                    let paidByFriend = app.account(t.accountId)?.kind == .lent && t.kind == .expense
                    DetailRow(label: t.kind == .transfer ? "From" : paidByFriend ? "Paid by" : "Account", value: app.accountLabel(t.accountId))
                    if t.kind == .transfer { DetailRow(label: "To", value: app.accountLabel(t.destinationId)) }
                    else { DetailRow(label: "Category", value: app.category(of: t)) }
                    if let record, t.kind == .expense {
                        // A split bill: your share is the spending, the rest is owed back
                        let lines = record.entry.lines
                        let people = lines.filter { app.record($0.accountId)?.kind == .lent && $0.amount.isPositive }
                        if !people.isEmpty, let mine = lines.first(where: { app.record($0.accountId)?.kind == .expense }) {
                            DetailRow(label: "Your share", value: app.money(mine.amount))
                            ForEach(people, id: \.accountId) { line in
                                DetailRow(label: "\(app.accountLabel(line.accountId)) owes", value: app.money(line.amount))
                            }
                        }
                    }
                }
            }
            if t.kind == .transfer {
                Redesign.footnote("Between your own accounts. Not counted as income or spending.").padding(.top, 16)
            }

            if let record, record.needsReview, !t.voided { review(record) }

            if let occ = t.occurrenceId, let bill = app.bill(occ) {
                Button { app.open(.bill(bill.id)) } label: {
                    HStack {
                        Label("Pays \(app.name(of: bill))", systemImage: "link")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .rdText(.detail).foregroundStyle(Theme.primary)
                    .padding(16)
                    .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                Button("Unlink from \(app.name(of: bill))") {
                    problem = app.attempt("Unlinked. The bill counts as unpaid again.", closing: false) { try app.store.unlink(entryId: t.id) }
                }
                .rdText(.detail).foregroundStyle(Theme.primary).frame(minHeight: 44)
            }

            Text("Note").rdText(.detail).foregroundStyle(Theme.muted).padding(.top, 24).padding(.bottom, 4)
            Text(app.note(of: t)).rdText(.body).padding(.bottom, 24)

            if let record, !t.voided {
                VStack(spacing: 12) {
                    if [.expense, .income, .transfer, .adjustment, .reconciliation, .debtPayment, .openingBalance].contains(record.kind) {
                        Button("Edit details") { edit(record) }.buttonStyle(PrimaryButtonStyle())
                            .accessibilityLabel("Edit")
                    }
                    more(record)
                    Button { confirmDelete = true } label: { Text("Delete").foregroundStyle(Theme.destructive) }
                        .buttonStyle(QuietButtonStyle())
                        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                problem = app.attempt("Transaction deleted.") { try app.store.void(record.id) }
                            }
                        } message: { Text("Your balances go back to how they were before it. It stays in the history as deleted.") }
                }
            }
            Problem(text: problem).padding(.top, 12)
            if let record { history(record) }
        }

        private func edit(_ record: EntryRecord) {
            switch record.kind {
            case .debtPayment: app.open(.editDebtPayment(record.id))
            case .openingBalance:
                if let id = record.lines.first(where: { app.record($0.accountId)?.kind.isBalanceSheet == true })?.accountId {
                    app.open(.startingAmount(id))
                }
            default: app.open(.editEntry(record.id))
            }
        }

        private func review(_ record: EntryRecord) -> some View {
            let account = record.lines.compactMap { app.record($0.accountId) }.first { $0.kind.isBalanceSheet }
            return VStack(alignment: .leading, spacing: 10) {
                Text("Check this entry").rdText(.detailStrong)
                Redesign.footnote("Saved automatically\(t.source.map { " from \($0)" } ?? ""). If the category or account is wrong, tap Edit details.")
                Button { problem = app.attempt("Marked as checked.") { try app.store.markReviewed(record.id) } } label: {
                    Label("Looks right", systemImage: "checkmark.circle")
                }
                .buttonStyle(QuietButtonStyle())
                if let hint = record.cardHint, let account, app.store.linkedAccount(forCard: hint) != account.id {
                    let card = hint.count == 4 && hint.allSatisfy(\.isNumber) ? "card ending \(hint)" : hint
                    Button {
                        problem = app.attempt("Done. \(card.capitalized) will go to \(app.accountLabel(account.id)).") {
                            try app.store.linkCard(hint, to: account.id)
                            try app.store.markReviewed(record.id)
                        }
                    } label: { Text("Always use \(app.accountLabel(account.id)) for \(card)").multilineTextAlignment(.center) }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .rdPanel()
            .padding(.top, 16)
        }

        /// What else an entry could really have been
        @ViewBuilder private func more(_ record: EntryRecord) -> some View {
            let s = app.snapshot
            let throughOwn = record.lines.contains { app.record($0.accountId).map { $0.kind.isBalanceSheet && $0.kind != .lent } ?? false }
            let people = s.accounts.filter { $0.kind == .lent && !$0.archived }
            let couldPayDebt = record.kind == .expense && !s.debts.isEmpty
                && record.lines.contains { app.record($0.accountId)?.kind.isAsset == true }
            let couldLend = throughOwn && (record.kind == .expense || record.kind == .income)
            let couldSplit = throughOwn && record.kind == .expense
            if couldPayDebt || couldLend {
                Menu {
                    if couldSplit {
                        Button("Split it with others") { app.open(.splitEntry(record.id)) }
                    }
                    if couldPayDebt {
                        Button("This was a loan or card payment") { app.open(.entryAsDebtPayment(record.id)) }
                    }
                    if couldLend {
                        Section(record.kind == .expense ? "I lent all of it to" : "It came from a person") {
                            ForEach(people) { p in
                                Button(app.accountLabel(p.id)) {
                                    problem = app.attempt(record.kind == .expense ? "Recorded as money lent." : "Recorded as money from \(app.accountLabel(p.id)).") {
                                        try app.store.recordAsLending(record.id, person: p.id)
                                    }
                                }
                            }
                            Button("Someone new…") { askingName = true }
                        }
                    }
                } label: {
                    Text("It was something else").frame(maxWidth: .infinity, minHeight: 46)
                        .rdText(.label).foregroundStyle(Theme.primary)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border.opacity(0.6)))
                }
                .accessibilityIdentifier(couldPayDebt ? "wasDebtPayment" : "wasLending")
                .alert(record.kind == .expense ? "Who did you lend it to?" : "Who was it from?", isPresented: $askingName) {
                    TextField("Name", text: $personName).accessibilityIdentifier("personName")
                    Button("Cancel", role: .cancel) { personName = "" }
                    Button("Save") {
                        let name = personName.trimmingCharacters(in: .whitespaces)
                        personName = ""
                        guard !name.isEmpty else { return }
                        problem = app.attempt(record.kind == .expense ? "Recorded as money lent to \(name)." : "Recorded as money from \(name).") {
                            let person = try app.store.lentAccount(named: name)
                            try app.store.recordAsLending(record.id, person: person.id)
                        }
                    }
                }
            }
        }

        private func history(_ record: EntryRecord) -> some View {
            let ids = Set([record.id] + [record.replacesId].compactMap { $0 })
            let trail = app.store.auditTrail.filter { ids.contains($0.subjectId) }
            return VStack(alignment: .leading, spacing: 8) {
                Text("History").rdText(.detailStrong)
                ForEach(trail, id: \.id) { a in
                    HStack(alignment: .top) {
                        Text(private: app.hidesDetails ? a.action : a.summary).rdText(.caption)
                        Spacer()
                        Text(a.date.formatted(date: .abbreviated, time: .shortened)).rdText(.caption).foregroundStyle(Theme.muted)
                    }
                }
                HStack {
                    Text("Added").rdText(.caption)
                    Spacer()
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).rdText(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 28)
        }
    }

    /// Automatic entries still to check, from Home's "Needs you"
    struct ReviewList: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            let waiting = app.transactions.filter(\.needsReview)
            Text("Saved from Apple Pay, a bank message or Siri. Open one to fix it, or confirm they all look right.")
                .rdText(.body).foregroundStyle(Theme.muted).padding(.bottom, 16)
            if waiting.isEmpty {
                EmptyNote(text: "All checked. Nothing waiting.")
            } else {
                Divided(items: waiting) { TransactionRow(t: $0) }
                Button("Everything looks right") {
                    app.attempt("All marked as checked.") { try app.store.markAllReviewed() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 20)
            }
        }
    }

    /// Picks the card or loan an expense really paid, then opens the payment form for it
    struct DebtChoice: View {
        let replacing: EntryRecord
        @Environment(AppModel.self) private var app
        @State private var debtId: UUID?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose the card or loan it paid. It's recorded again as a payment, with the interest split off, and the expense is replaced.")
                    .rdText(.body).foregroundStyle(Theme.muted)
                AccountChoice(label: "Paid", selection: $debtId, accounts: app.cards + app.loans)
                if let debtId, let debt = app.record(debtId) {
                    PayDebtForm(debt: debt, replacing: replacing).id(debtId)
                }
            }
            .onAppear { if debtId == nil { debtId = (app.cards + app.loans).first?.id } }
        }
    }
}
