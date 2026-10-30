//
//  BillsView.swift
//  Nokael Money
//
//  Every bill and expected payment, opened from Home's Coming up. Scheduled
//  items are never posted money until they're marked paid or matched.
//

import SwiftUI
import NokaelCore

struct BillsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editingItem: PlannedItemSheet?
    @State private var paying: Occurrence?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        List {
            let dueSoon = snapshot.upcomingBills(days: 30)
            if !dueSoon.isEmpty {
                Section("Due in 30 days") {
                    ForEach(dueSoon) { occ in
                        Button { paying = occ } label: { OccurrenceRow(occurrence: occ, snapshot: snapshot) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Section {
                let bills = snapshot.items.filter { $0.direction == .outflow }
                if bills.isEmpty {
                    EmptyStateView(symbol: "calendar.badge.plus", title: "No bills yet",
                                   message: "Add rent, utilities and subscriptions. They're kept out of Safe to spend until paid.",
                                   actionTitle: "Add a bill") { editingItem = .new(.outflow) }
                }
                ForEach(bills) { item in
                    Button { editingItem = .edit(item) } label: { PlannedItemRow(item: item, snapshot: snapshot) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Your bills")
            }

            Section {
                let income = snapshot.items.filter { $0.direction == .inflow }
                if income.isEmpty {
                    Button { editingItem = .new(.inflow) } label: { Label("Add expected income", systemImage: "plus") }
                }
                ForEach(income) { item in
                    Button { editingItem = .edit(item) } label: { PlannedItemRow(item: item, snapshot: snapshot) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Expected income")
            } footer: {
                Text("Not counted as money you have until you mark it received.")
            }
        }
        .listStyle(.insetGrouped)
        .canvas()
        .navigationTitle("Bills")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editingItem = .new(.outflow) } label: { Label("Bill", systemImage: "calendar.badge.plus") }
                    Button { editingItem = .new(.inflow) } label: { Label("Expected income", systemImage: "arrow.down.circle") }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("New bill or expected income")
                .accessibilityIdentifier("newBill")
            }
        }
        .sheet(item: $editingItem) { PlannedItemEditor(sheet: $0) }
        .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
    }
}

enum PlannedItemSheet: Identifiable {
    case new(Direction)
    case edit(PlannedItem)

    var id: String {
        switch self {
        case .new(let d): return "new-\(d.rawValue)"
        case .edit(let item): return item.id.uuidString
        }
    }
}

struct PlannedItemRow: View {
    let item: PlannedItem
    let snapshot: FinanceSnapshot

    var body: some View {
        let next = snapshot.occurrences.first { $0.itemId == item.id && !$0.remaining.isZero && !$0.skipped }
        // A bill looks like what it pays: the card or loan, else its category
        let look = (item.debtId ?? item.categoryId).flatMap { snapshot.account($0) }.flatMap { $0.icon.isEmpty ? nil : $0 }
        ListRow(title: item.name,
                caption: [item.schedule.frequency.label,
                          next.map { "next " + $0.dueDate.formatted(.dateTime.day().month(.abbreviated)) },
                          item.isEstimate ? "estimate" : nil].compactMap { $0 }.joined(separator: " · "),
                symbol: item.direction == .inflow ? "arrow.down.circle.fill" : look?.icon ?? "calendar",
                color: item.direction == .inflow ? .green : look.map { Color(hex: $0.colorHex) } ?? Palette.plan) {
            AmountPill(text: (item.direction == .inflow ? "+" : "") + item.amount.compact,
                       style: item.direction == .inflow ? .positive : .neutral)
        }
    }
}

// MARK: - Editor

struct PlannedItemEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sheet: PlannedItemSheet

    @State private var name = ""
    @State private var amountText = ""
    @State private var isEstimate = false
    @State private var start = Date()
    /// The next due date as loaded, so saving without touching it keeps the schedule as it was
    @State private var loadedStart: Date?
    @State private var frequency: Frequency = .monthly(every: 1)
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var reminderDays = 2
    @State private var error: String?
    @State private var confirmStop = false
    @AppStorage(BillReminders.enabledKey) private var remindersOn = false

    private var direction: Direction {
        switch sheet {
        case .new(let d): return d
        case .edit(let item): return item.direction
        }
    }

    private var existing: PlannedItem? {
        if case .edit(let item) = sheet { return item }
        return nil
    }

    var body: some View {
        let snapshot = store.snapshot
        NavigationStack {
            Form {
                Section {
                    TextField(direction == .inflow ? "Name (e.g. Salary)" : "Name (e.g. Rent)", text: $name)
                        .accessibilityIdentifier("billName")
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("billAmount")
                    }
                    Toggle("Amount varies (estimate)", isOn: $isEstimate)
                }
                Section {
                    if existing == nil {
                        DatePicker("Next due", selection: $start, displayedComponents: .date)
                    } else {
                        DatePicker("Next due", selection: $start, in: store.calendar.startOfDay(for: Date())..., displayedComponents: .date)
                            .accessibilityIdentifier("billNextDue")
                    }
                    FrequencyPicker(frequency: $frequency)
                    Toggle("Ends", isOn: $hasEnd)
                    if hasEnd { DatePicker("Last one", selection: $end, in: start..., displayedComponents: .date) }
                    if direction == .outflow {
                        Picker("Remind me", selection: $reminderDays) {
                            ForEach(BillReminders.choices, id: \.days) { Text($0.label).tag($0.days) }
                        }
                        .disabled(!remindersOn)
                    }
                } header: {
                    Text("When")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if existing != nil {
                            Text("Repeats from this date. Unpaid ones from today move with it; paid ones stay as they were.")
                        }
                        if direction == .outflow && !remindersOn {
                            Text("Turn on reminders in Settings to be reminded before bills are due.")
                        }
                    }
                }
                Section {
                    AccountPicker(title: direction == .inflow ? "Paid into" : "Paid from", accounts: snapshot.accounts, selection: $accountId)
                    Picker("Category", selection: $categoryId) {
                        Text("Choose…").tag(nil as UUID?)
                        ForEach(direction == .inflow ? snapshot.incomeCategories : snapshot.expenseCategories, id: \.id) {
                            Text($0.name).tag($0.id as UUID?)
                        }
                    }
                } footer: {
                    Text(direction == .inflow
                         ? "Expected income isn't counted as money you have until you mark it received."
                         : "Unpaid bills are reserved in safe-to-spend until you mark them paid. Changing this only affects future, unpaid ones.")
                }
                if let error { Section { FieldError(message: error) } }
                if existing != nil {
                    Section {
                        Button(direction == .inflow ? "Stop expecting this" : "Stop this bill", role: .destructive) { confirmStop = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? (direction == .inflow ? "Expected income" : "New bill") : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("saveBill") }
            }
            .confirmationDialog("Stop \(name)?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop", role: .destructive) {
                    if let existing { try? store.archivePlannedItem(existing.id) }
                    dismiss()
                }
            } message: {
                Text("Future unpaid ones are removed. Payments already made stay in your history.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let item = existing else {
            accountId = store.snapshot.accounts.first { $0.spendable }?.id
            return
        }
        name = item.name
        amountText = MoneyFormat.editable(item.amount)
        isEstimate = item.isEstimate
        // Show when it's next due, not when the bill was first set up
        let next = store.snapshot.occurrences
            .filter { $0.itemId == item.id && !$0.skipped && !$0.remaining.isZero && $0.dueDate >= store.calendar.startOfDay(for: Date()) }
            .map(\.dueDate).min()
        start = next ?? item.schedule.start
        loadedStart = start
        frequency = item.schedule.frequency
        hasEnd = item.schedule.end != nil
        end = item.schedule.end ?? Date()
        accountId = item.accountId
        categoryId = item.categoryId
        reminderDays = store.snapshot.reminderDays(for: item.id)
    }

    private func save() {
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency) else { error = "Enter an amount."; return }
        let cal = store.calendar
        let item = PlannedItem(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces),
                               direction: direction, amount: amount, isEstimate: isEstimate,
                               schedule: Schedule(start: start == loadedStart ? existing!.schedule.start
                                                         : cal.startOfDay(for: start).addingTimeInterval(12 * 3600),
                                                  frequency: frequency, end: hasEnd ? store.snapshot.endOfDay(end) : nil),
                               accountId: accountId, categoryId: categoryId, debtId: existing?.debtId)
        do {
            try store.savePlannedItem(item, reminderDays: direction == .outflow ? reminderDays : nil)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

// MARK: - Paying

struct PayOccurrenceSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let occurrence: Occurrence

    @State private var key = UUID()
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var date = Date()
    @State private var error: String?
    @State private var editing: PlannedItemSheet?
    @State private var viewing: EntryRecord?
    @State private var unlinking: EntryRecord?

    var body: some View {
        let snapshot = store.snapshot
        // Follow the bill as payments are linked and unlinked while the sheet is open
        let live = snapshot.occurrences.first { $0.id == occurrence.id } ?? occurrence
        let item = snapshot.item(for: live)
        let inflow = item?.direction == .inflow
        let payments = live.paidEntryIds.compactMap { id in snapshot.entryRecords.first { $0.id == id } }
        let candidates = matchCandidates(snapshot, live: live, inflow: inflow)
        let strong = candidates.filter { isStrongMatch($0, snapshot: snapshot, live: live) }
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(live.remaining.isZero && live.paid.isPositive ? live.paid.formatted : live.remaining.formatted)
                            .font(.largeTitle.bold()).monospacedDigit()
                        Label(statusText(live, inflow: inflow), systemImage: statusSymbol(live))
                            .font(.headline).foregroundStyle(statusColor(live))
                    }
                    .padding(.vertical, 4)
                    LabeledContent(inflow ? "Expected" : "Due", value: live.dueDate.formatted(date: .long, time: .omitted))
                    LabeledContent(live.isEstimate ? "Estimated" : "Amount", value: live.expected.formatted)
                    if let account = snapshot.account(item?.accountId) {
                        LabeledContent(inflow ? "Into" : "From", value: account.name)
                    }
                }

                if !payments.isEmpty {
                    Section {
                        ForEach(payments, id: \.id) { record in
                            Button { viewing = record } label: { EntryRow(record: record, snapshot: snapshot) }
                                .buttonStyle(.plain)
                                .swipeActions { Button("Unlink") { unlinking = record }.tint(.orange) }
                        }
                    } header: {
                        Text(payments.count == 1 ? "Payment" : "Payments")
                    } footer: {
                        Text("Swipe a payment to unlink it if it wasn't for this bill. The transaction stays in Activity and your balance doesn't change; the bill reopens.")
                    }
                }

                if live.skipped {
                    Section {
                        Button("Undo skip") { try? store.unskip(occurrenceId: live.id) }
                    } footer: {
                        Text("Skipped bills aren't held back from Safe to spend or counted in Budget.")
                    }
                } else if live.remaining.isPositive {
                    if !strong.isEmpty {
                        Section {
                            ForEach(strong, id: \.id) { record in
                                Button { match(record) } label: { EntryRow(record: record, snapshot: snapshot) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Is this it?")
                        } footer: {
                            Text("Already recorded. Tap it to link it to this bill; nothing is recorded twice and your balance doesn't change.")
                        }
                    }

                    Section {
                        HStack {
                            Text(store.currency).foregroundStyle(.secondary)
                            TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                        }
                        AccountPicker(title: inflow ? "Into" : "From", accounts: snapshot.accounts, selection: $accountId)
                        Picker("Category", selection: $categoryId) {
                            Text("Choose…").tag(nil as UUID?)
                            ForEach(inflow ? snapshot.incomeCategories : snapshot.expenseCategories, id: \.id) {
                                Text($0.name).tag($0.id as UUID?)
                            }
                        }
                        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        Button(inflow ? "Record income" : "Record payment", action: pay)
                            .bold()
                    } header: {
                        Text(strong.isEmpty ? (inflow ? "Record income" : "Record payment") : "Or record a new payment")
                    } footer: {
                        Text(inflow ? "Adds the money to the account and marks this as received."
                             : "Records one payment from the account and marks this bill paid. Pay less than the full amount and the rest stays due.")
                    }

                    let others = candidates.filter { c in !strong.contains { $0.id == c.id } }
                    if !others.isEmpty {
                        Section {
                            ForEach(others, id: \.id) { record in
                                Button { match(record) } label: { EntryRow(record: record, snapshot: snapshot) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Already recorded it?")
                        } footer: {
                            Text("Tap the matching transaction to link it instead of recording it twice.")
                        }
                    }
                }

                Section {
                    if let item {
                        Button(inflow ? "Change when it's expected" : "Change when it's due") { editing = .edit(item) }
                    }
                    if !live.skipped && live.paid.isZero {
                        // Stays open on Skipped, so it can be undone straight away
                        Button("Skip this one") { try? store.skip(occurrenceId: live.id) }
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(item?.name ?? "Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing, onDismiss: {
                // Moved to another day: this one no longer exists as shown
                if !store.snapshot.occurrences.contains(where: { $0.id == occurrence.id && $0.dueDate == occurrence.dueDate }) { dismiss() }
            }) { PlannedItemEditor(sheet: $0) }
            .sheet(item: $viewing) { EntryDetailView(record: $0) }
            .confirmationDialog("Unlink this payment?", isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }),
                                titleVisibility: .visible, presenting: unlinking) { record in
                Button("Unlink", role: .destructive) {
                    do { try store.unlink(entryId: record.id) } catch { self.error = StoreError.from(error).errorDescription }
                }
            } message: { _ in
                Text("The bill reopens. The transaction stays in Activity and your balance doesn't change.")
            }
            .onAppear {
                amountText = MoneyFormat.editable(occurrence.remaining)
                accountId = item?.accountId ?? snapshot.accounts.first { $0.spendable }?.id
                categoryId = item?.categoryId
                date = min(Date(), max(occurrence.dueDate, snapshot.calendar.startOfDay(for: Date())))
            }
        }
    }

    /// One canonical state, worked out from the amount and the payments linked to it
    private func statusText(_ o: Occurrence, inflow: Bool) -> String {
        let state = store.snapshot.state(of: o)
        switch state {
        case .skipped: return "Skipped"
        case .paid: return inflow ? "Received" : "Paid"
        case .partiallyPaid: return "Part \(inflow ? "received" : "paid"): \(o.paid.formatted) of \(o.expected.formatted), \(o.remaining.formatted) left"
        case .overdue: return inflow ? "Not received yet · was expected \(o.dueDate.formatted(.dateTime.day().month(.abbreviated)))"
                                     : "Not paid yet · overdue"
        case .dueToday: return inflow ? "Expected today" : "Due today · payment not recorded"
        case .scheduled: return inflow ? "Not received yet" : "Not paid yet"
        }
    }

    private func statusSymbol(_ o: Occurrence) -> String {
        switch store.snapshot.state(of: o) {
        case .paid: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .partiallyPaid: return "circle.lefthalf.filled"
        case .overdue: return "exclamationmark.circle.fill"
        default: return "circle"
        }
    }

    private func statusColor(_ o: Occurrence) -> Color {
        switch store.snapshot.state(of: o) {
        case .paid: return .green
        case .overdue: return .red
        case .dueToday, .partiallyPaid: return .orange
        default: return .secondary
        }
    }

    /// A recorded payment the bill matcher thinks is this bill
    private func isStrongMatch(_ record: EntryRecord, snapshot: FinanceSnapshot, live: Occurrence) -> Bool {
        guard !record.dismissedOccurrenceIds.contains(live.id) else { return false }
        let infos = Dictionary(snapshot.accountRecords.map { ($0.id, $0.info) }, uniquingKeysWith: { a, _ in a })
        guard let payment = BillPayment(record.entry, accounts: infos) else { return false }
        return snapshot.billCandidates(for: payment).contains { $0.occurrence.id == live.id }
    }

    /// Recent unlinked entries in the same direction, closest amount first
    private func matchCandidates(_ snapshot: FinanceSnapshot, live: Occurrence, inflow: Bool) -> [EntryRecord] {
        let window = snapshot.calendar.date(byAdding: .day, value: -20, to: live.dueDate) ?? live.dueDate
        let target = live.remaining.minorUnits
        return snapshot.entries()
            .filter { $0.occurrenceId == nil && $0.date >= window && $0.kind == (inflow ? .income : .expense) }
            .sorted { abs(amount($0) - target) < abs(amount($1) - target) }
            .prefix(4).map { $0 }
    }

    private func amount(_ record: EntryRecord) -> Int64 {
        record.lines.filter { $0.minorUnits > 0 }.map(\.minorUnits).reduce(0, +)
    }

    private func pay() {
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency) else { error = "Enter an amount."; return }
        guard let accountId else { error = "Choose an account."; return }
        do {
            try store.pay(occurrenceId: occurrence.id, amount: amount, accountId: accountId, categoryId: categoryId,
                          date: date, key: key)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }

    private func match(_ record: EntryRecord) {
        do {
            try store.match(occurrenceId: occurrence.id, entryId: record.id)
            if store.snapshot.occurrences.first(where: { $0.id == occurrence.id })?.remaining.isZero ?? true { dismiss() }
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
