//
//  PlanView.swift
//  Nokael Money
//
//  Bills, expected income, debts and savings in one place, so a planned saving
//  and next week's loan payment can be seen together. Scheduled items are
//  never posted money until they're marked paid or matched.
//

import SwiftUI
import NokaelCore

struct PlanView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @State private var paywall: PlusFeature?
    @State private var editingItem: PlannedItemSheet?
    @State private var paying: Occurrence?
    @State private var addingReserve = false
    @State private var addingLoan = false
    @State private var addingGoal = false
    @State private var editingReserve: Reserve?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section { banner.bannerRow() }

                Section {
                    let fc = snapshot.cashForecast(days: 60)
                    if plus.isPlus {
                        NavigationLink { ForecastView() } label: {
                            ListRow(title: "Money ahead",
                                    caption: fc.firstShortfall.map { "Short on " + $0.formatted(.dateTime.day().month(.abbreviated)) }
                                        ?? "Lowest in 60 days: \(fc.lowest.compact)",
                                    symbol: "chart.line.uptrend.xyaxis", color: fc.firstShortfall == nil ? Palette.plan : .red) {
                                EmptyView()
                            }
                        }
                        .accessibilityIdentifier("moneyAhead")
                    } else {
                        // The heads-up is free; the day-by-day detail is Plus
                        Button { paywall = .moneyAhead } label: {
                            ListRow(title: "Money ahead",
                                    caption: fc.firstShortfall == nil ? "Your balance day by day for 60 days"
                                        : "You may run short in the next 60 days. See when.",
                                    symbol: "chart.line.uptrend.xyaxis", color: fc.firstShortfall == nil ? Palette.plan : .red) {
                                PlusBadge()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("moneyAhead")
                    }
                }

                Section {
                    let dueSoon = snapshot.upcomingBills(days: 30)
                    if dueSoon.isEmpty { Text("Nothing due in the next 30 days").foregroundStyle(.secondary) }
                    ForEach(dueSoon) { occ in
                        Button { paying = occ } label: { OccurrenceRow(occurrence: occ, snapshot: snapshot) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Due soon")
                } footer: {
                    Text("Paid one? Tap it to mark it paid.")
                }

                Section {
                    let bills = snapshot.items.filter { $0.direction == .outflow }
                    if bills.isEmpty {
                        EmptyStateView(symbol: "calendar.badge.plus", title: "No bills yet",
                                       message: "Add rent, utilities, subscriptions and loan payments. They're reserved in safe-to-spend until paid.",
                                       actionTitle: "Add a bill") { editingItem = .new(.outflow) }
                    }
                    ForEach(bills) { item in
                        Button { editingItem = .edit(item) } label: { PlannedItemRow(item: item, snapshot: snapshot) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Your bills")
                        Spacer()
                        Button("Add a bill") { editingItem = .new(.outflow) }.font(.caption)
                    }
                } footer: {
                    if !snapshot.items.filter({ $0.direction == .outflow }).isEmpty {
                        Text("Tap a bill to change its amount or date, or to stop it.")
                    }
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
                    HStack {
                        Text("Expected income")
                        Spacer()
                        if !snapshot.items.filter({ $0.direction == .inflow }).isEmpty {
                            Button("Add") { editingItem = .new(.inflow) }.font(.caption)
                        }
                    }
                } footer: {
                    Text("Expected income is a plan. It isn't counted as money you have until you mark it received.")
                }

                debtsSection
                savingsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { editingItem = .new(.outflow) } label: { Label("Bill", systemImage: "calendar.badge.plus") }
                        Button { editingItem = .new(.inflow) } label: { Label("Expected income", systemImage: "arrow.down.circle") }
                        Button { newGoal() } label: { Label("Savings goal", systemImage: "target") }
                        Button { addingReserve = true } label: { Label("Money set aside", systemImage: "lock") }
                        Button { addingLoan = true } label: { Label("Loan or credit card", systemImage: "creditcard") }
                    } label: { Text("New bill or goal").font(.body.weight(.semibold)) }
                    .accessibilityLabel("New bill, expected income or savings goal")
                }
                GlobalAddButton()
            }
            .sheet(item: $editingItem) { PlannedItemEditor(sheet: $0) }
            .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
            .sheet(isPresented: $addingReserve) { ReserveEditor() }
            .sheet(isPresented: $addingLoan) { NewLoanSheet() }
            .sheet(isPresented: $addingGoal) { ReserveEditor(asGoal: true) }
            .paywall($paywall)
            .sheet(item: $editingReserve) { ReserveEditor(editing: $0) }
        }
    }

    /// One goal is free; more need Plus
    private func newGoal() {
        if plus.isPlus || snapshot.goals.isEmpty { addingGoal = true } else { paywall = .goals }
    }

    private var banner: some View {
        let due = snapshot.upcomingBills(days: 30)
        let total = due.map(\.remaining).sum(store.currency)
        let next = due.first
        let caption: String = {
            guard let next, let item = snapshot.item(for: next) else { return "No bills due in the next 30 days" }
            let state = snapshot.state(of: next)
            let when = state == .overdue ? "was due " : "next: "
            return "\(item.name) \(when)\(next.dueDate.formatted(.dateTime.day().month(.abbreviated))) · \(next.remaining.compact)"
        }()
        return SummaryBanner(title: "Bills due in 30 days", amount: total.compact, caption: caption, tint: Palette.plan) {
            BannerFigures(figures: [("Debt", snapshot.totalDebt.compact)]
                          + (snapshot.activeReservesTotal.isPositive ? [("Set aside", snapshot.activeReservesTotal.compact)] : []))
        }
    }

    @ViewBuilder private var debtsSection: some View {
        let debts = snapshot.debts
        Section {
            if debts.isEmpty {
                Text("No cards or loans added").foregroundStyle(.secondary)
            }
            ForEach(debts, id: \.id) { debt in
                let owed = snapshot.owed(debt.id)
                let caption: String = {
                    guard let terms = debt.debtTerms else { return "Add the rate and payment to see a payoff date" }
                    let payoff = snapshot.payoff(for: debt)?.shortText
                    return ["\(terms.monthlyPayment.compact) a month", payoff].compactMap { $0 }.joined(separator: " · ")
                }()
                NavigationLink {
                    AccountDetailView(accountId: debt.id)
                } label: {
                    ListRow(title: debt.name, caption: caption, symbol: debt.icon, color: Color(hex: debt.colorHex)) {
                        AmountPill(text: owed.isPositive ? "\(owed.compact) owed" : "Paid off", style: owed.isPositive ? .neutral : .positive)
                    }
                }
            }
        } header: {
            Text("Debts")
        } footer: {
            Text("Open a card or loan to set its rate and payment, see when it's paid off, and record payments split into interest and principal.")
        }
    }

    @ViewBuilder private var savingsSection: some View {
        Section {
            if snapshot.goals.isEmpty {
                Button { addingGoal = true } label: { Label("Start a savings goal", systemImage: "target") }
                    .accessibilityIdentifier("startGoal")
            }
            ForEach(snapshot.goals) { goal in
                if let progress = snapshot.progress(of: goal) {
                    NavigationLink { GoalDetailView(goalId: goal.id) } label: { GoalRow(goal: goal, progress: progress) }
                }
            }
            ForEach(snapshot.reserves.filter { !$0.isGoal }) { r in
                Button { editingReserve = r } label: {
                    ListRow(title: r.name, caption: "Set aside in \(snapshot.account(r.accountId)?.name ?? "an account")",
                            symbol: "lock.fill", color: Palette.plan) {
                        AmountPill(r.amount)
                    }
                }.buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Savings")
                Spacer()
                if !snapshot.goals.isEmpty { Button("Add") { newGoal() }.font(.caption) }
            }
        } footer: {
            Text("Saved money stays in its account and is kept out of safe-to-spend, so you can't spend it by accident.")
        }
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
                    DatePicker(existing == nil ? "Next due" : "Starts", selection: $start, displayedComponents: .date)
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
                    if direction == .outflow && !remindersOn {
                        Text("Turn on reminders in Settings to be reminded before bills are due.")
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
        start = item.schedule.start
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
                               schedule: Schedule(start: cal.startOfDay(for: start).addingTimeInterval(12 * 3600),
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

    var body: some View {
        let snapshot = store.snapshot
        let item = snapshot.item(for: occurrence)
        let inflow = item?.direction == .inflow
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Due", value: occurrence.dueDate.formatted(date: .long, time: .omitted))
                    LabeledContent(occurrence.isEstimate ? "Estimated" : "Expected", value: occurrence.expected.formatted)
                    if occurrence.paid.isPositive { LabeledContent("Already paid", value: occurrence.paid.formatted) }
                }
                Section(inflow ? "Mark as received" : "Mark as paid") {
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
                }

                let candidates = matchCandidates(snapshot, inflow: inflow)
                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates, id: \.id) { record in
                            Button { match(record) } label: { EntryRow(record: record, snapshot: snapshot) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Already recorded it?")
                    } footer: {
                        Text("Tap the matching transaction to link it instead of recording it twice.")
                    }
                }

                Section {
                    Button("Skip this one") {
                        try? store.skip(occurrenceId: occurrence.id)
                        dismiss()
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(item?.name ?? "Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                amountText = MoneyFormat.editable(occurrence.remaining)
                accountId = item?.accountId ?? snapshot.accounts.first { $0.spendable }?.id
                categoryId = item?.categoryId
                date = min(Date(), max(occurrence.dueDate, snapshot.calendar.startOfDay(for: Date())))
            }
        }
    }

    /// Recent unlinked entries in the same direction, closest amount first
    private func matchCandidates(_ snapshot: FinanceSnapshot, inflow: Bool) -> [EntryRecord] {
        let window = snapshot.calendar.date(byAdding: .day, value: -20, to: occurrence.dueDate) ?? occurrence.dueDate
        let target = occurrence.remaining.minorUnits
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
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
