//
//  BudgetView.swift
//  Nokael Money
//
//  The monthly spending plan. Allocating reserves spending capacity; it never
//  moves money between accounts. Categories are grouped and can be added,
//  renamed, reordered within groups, and archived.
//

import SwiftUI
import NokaelCore

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @State private var paywall: PlusFeature?
    @State private var showingReports = false
    @State private var month: String?
    @State private var selected: UUID?
    @State private var addingCategory = false
    @State private var explanation: Explanation?
    @State private var error: String?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var currentMonth: String { month ?? snapshot.monthKey }
    private var monthTitle: String {
        BudgetMonth.start(of: currentMonth, calendar: snapshot.calendar)?.formatted(.dateTime.month(.wide).year()) ?? currentMonth
    }

    var body: some View {
        NavigationStack {
            let budget = snapshot.budget
            let available = budget.availableToAllocate(month: currentMonth)
            let progress = budget.allocationProgress(month: currentMonth)
            List {
                Section {
                    SummaryBanner(title: available.isNegative ? "Planned more than you have" : "Not planned yet",
                                  amount: available.compact,
                                  caption: progress.planningFunds.isPositive
                                      ? (available.isNegative ? "Lower a category below to fix it"
                                         : available.isZero ? "Every dirham this month has a job"
                                         : owedCaption ?? "Money with no job yet. Tap a category below to give it some")
                                      : "Add an account with money in it to start planning",
                                  tint: available.isNegative ? .red : Palette.budget,
                                  action: { explanation = availableExplanation(available) }) {
                        VStack(spacing: 4) {
                            ProgressBar(value: progress.fraction, tint: .white)
                            Text("\(Int((progress.fraction * 100).rounded()))% of this month's money planned")
                                .font(.caption2).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 24).padding(.top, 6)
                    }
                    .bannerRow()
                }

                if snapshot.expenseCategories.isEmpty {
                    Section {
                        EmptyStateView(symbol: "chart.pie", title: "No categories yet",
                                       message: "Add categories like Groceries or Transport, then plan how much each gets.",
                                       actionTitle: "Use starter categories") {
                            try? store.addStarterCategories()
                        }
                    }
                } else if progress.allocated.isZero && budget.allocationProgress(month: previousMonth).allocated.isPositive {
                    Section {
                        Button { copyLastMonth() } label: { Label("Copy last month's plan", systemImage: "doc.on.doc") }
                    } footer: {
                        Text("Or start fresh by tapping a category and setting its amount.")
                    }
                }

                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.categories, id: \.id) { category in
                            Button { selected = category.id } label: {
                                BudgetRow(category: category, line: budget.line(category.id, month: currentMonth))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        let remaining = group.categories.map { budget.line($0.id, month: currentMonth).remaining }.sum(store.currency)
                        HStack {
                            Text(group.name); Spacer()
                            if !remaining.isZero { Text("\(remaining.compact) left").monospacedDigit() }
                        }
                    } footer: {
                        if group.name == groups.first?.name {
                            Text("Tap a category to set how much you plan to spend on it this month.")
                        }
                    }
                }

                if let error { Section { FieldError(message: error) } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Budget")
            .paywall($paywall)
            .navigationDestination(isPresented: $showingReports) { ReportsView() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        Button { month = BudgetMonth.adding(-1, to: currentMonth, calendar: snapshot.calendar) } label: {
                            Image(systemName: "chevron.left")
                        }.accessibilityLabel("Previous month")
                        Text(monthTitle).font(.headline)
                        Button { month = BudgetMonth.adding(1, to: currentMonth, calendar: snapshot.calendar) } label: {
                            Image(systemName: "chevron.right")
                        }.accessibilityLabel("Next month")
                    }
                    // Rows scroll under the toolbar, so the switcher keeps its own backing
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { addingCategory = true } label: { Label("New category", systemImage: "folder.badge.plus") }
                        Button { if plus.isPlus { showingReports = true } else { paywall = .reports } } label: {
                            Label(plus.isPlus ? "Reports" : "Reports (Plus)", systemImage: "chart.bar.xaxis")
                        }
                    } label: {
                        Text("More").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("More: new category, reports")
                }
                GlobalAddButton()
            }
            .sheet(item: Binding(get: { selected.map(IdentifiedUUID.init) }, set: { selected = $0?.id })) { item in
                CategoryDetailView(categoryId: item.id, month: currentMonth)
            }
            .sheet(isPresented: $addingCategory) { CategoryEditor() }
            .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
        }
    }

    private var previousMonth: String { BudgetMonth.adding(-1, to: currentMonth, calendar: snapshot.calendar) }

    private var groups: [(name: String, categories: [LedgerAccountRecord])] {
        let order = ["Essentials", "Lifestyle", "Savings", "Other"]
        let grouped = Dictionary(grouping: snapshot.expenseCategories) { $0.group.isEmpty ? "Other" : $0.group }
        return grouped.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            .map { ($0, grouped[$0] ?? []) }
    }

    private func copyLastMonth() {
        do { try store.copyPlan(from: previousMonth, to: currentMonth) } catch { self.error = StoreError.from(error).errorDescription }
    }

    /// Says when card debt is already taken out, so this doesn't look like money missing
    private var owedCaption: String? {
        let owed = snapshot.owedInBudget
        guard !owed.isEmpty else { return nil }
        let names = owed.map { "\($0.amount.compact) owed on \($0.name)" }.joined(separator: ", ")
        return "Money with no job yet, after \(names). Tap a category to plan it"
    }

    private func availableExplanation(_ available: Money) -> Explanation {
        let budget = snapshot.budget
        let end = BudgetMonth.end(of: currentMonth, calendar: snapshot.calendar)?.addingTimeInterval(-1)
        let held = snapshot.accounts.filter(\.onBudget).map {
            BreakdownItem(label: $0.name, amount: snapshot.ledger.balance(of: $0.id, asOf: end))
        }
        let setAside = snapshot.expenseCategories.compactMap { c -> BreakdownItem? in
            let r = budget.line(c.id, month: currentMonth).remaining
            return r.isZero ? nil : BreakdownItem(label: c.name, amount: r)
        }
        let future = snapshot.budget.allocations.filter { $0.month > currentMonth }.map(\.amount).sum(store.currency)
        var sections: [(String, [BreakdownItem], String)] = [("Money in budget accounts", held, ""),
                                                             ("Already planned in categories", setAside, "−")]
        if !future.isZero { sections.append(("Planned for later months", [BreakdownItem(label: "Future months", amount: future)], "−")) }
        return Explanation(title: "Available to allocate", total: available,
                           definition: "Money in your budget accounts that doesn't have a plan yet. Planning money doesn't move it out of any account.",
                           sections: sections,
                           notes: ["You don't have to plan every dirham.", "Spending from a category lowers what's left in it, not this number.",
                                   "Safe to spend on Home is a different number: it holds back only bills due before payday, and treats what's left in categories like Groceries as money you can spend. Budget also takes out everything still owed on cards in your budget, and everything you've planned."])
    }
}

struct IdentifiedUUID: Identifiable { let id: UUID }

struct BudgetRow: View {
    let category: LedgerAccountRecord
    let line: CategoryLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let planned = line.allocated + line.carriedIn
            ListRow(title: category.name, caption: caption(planned: planned),
                    symbol: category.icon, color: Color(hex: category.colorHex)) {
                AmountPill(text: pill(planned: planned),
                           style: line.isOverspent ? .negative
                               : (line.remaining.isPositive || (planned.isPositive && category.name == "Loan payments") ? .positive : .neutral))
            }
            if planned.isPositive {
                ProgressBar(value: Double(line.spent.minorUnits) / Double(planned.minorUnits),
                            tint: line.isOverspent ? .red : Color(hex: category.colorHex))
                    .padding(.leading, 46)
            }
        }
        .padding(.vertical, 2)
    }

    private func caption(planned: Money) -> String {
        if planned.isPositive { return "\(line.spent.compact) spent of \(planned.compact)" }
        return line.spent.isPositive ? "\(line.spent.compact) spent, nothing planned" : "Not planned this month"
    }

    private func pill(planned: Money) -> String {
        if line.isOverspent { return "\(line.remaining.magnitude.compact) over" }
        if !planned.isPositive { return "Plan" }
        if line.remaining.isZero { return category.name == "Loan payments" ? "Paid" : "All spent" }
        return "\(line.remaining.compact) left"
    }
}

// MARK: - Category detail

struct CategoryDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: UUID
    let month: String

    @State private var allocationText = ""
    @State private var moving = false
    @State private var editing = false
    @State private var error: String?
    @State private var selectedEntry: EntryRecord?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            if let category = snapshot.account(categoryId) {
                let line = snapshot.budget.line(categoryId, month: month)
                List {
                    Section {
                        HStack {
                            Text("Planned this month")
                            Spacer()
                            Text(store.currency).foregroundStyle(.secondary)
                            TextField("0", text: $allocationText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .onSubmit(saveAllocation)
                                .accessibilityIdentifier("allocationField")
                        }
                        if !line.carriedIn.isZero {
                            LabeledContent(line.carriedIn.isNegative ? "Overspent last month" : "Carried from last month",
                                           value: line.carriedIn.signed)
                        }
                        LabeledContent("Spent", value: line.spent.compact)
                        LabeledContent {
                            Text(line.remaining.compact).bold().foregroundStyle(line.isOverspent ? .red : .primary)
                        } label: {
                            Text(line.isOverspent ? "Over by" : "Left").bold()
                        }
                        Button { moving = true } label: { Label("Move money from another category", systemImage: "arrow.left.arrow.right") }
                    } footer: {
                        Text(line.isOverspent
                             ? "Overspent by \(line.remaining.magnitude.compact). Move money in from another category to cover it."
                             : "Planning doesn't move money out of your accounts. It only sets how much you mean to spend.")
                    }

                    Section("This month's spending") {
                        let entries = monthEntries
                        if entries.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                        ForEach(entries, id: \.id) { record in
                            Button { selectedEntry = record } label: { EntryRow(record: record, snapshot: snapshot) }
                                .buttonStyle(.plain)
                        }
                    }

                    Section {
                        Button("Rename, group or settings") { editing = true }
                    }

                    if let error { Section { FieldError(message: error) } }
                }
                .navigationTitle(category.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { saveAllocation(); dismiss() } }
                }
                .onAppear { allocationText = MoneyFormat.editable(line.allocated, emptyWhenZero: true) }
                .sheet(isPresented: $moving) {
                    MoveMoneySheet(destinationId: categoryId, month: month) {
                        allocationText = MoneyFormat.editable(snapshot.budget.line(categoryId, month: month).allocated, emptyWhenZero: true)
                    }
                }
                .sheet(isPresented: $editing) { CategoryEditor(editing: category) }
                .sheet(item: $selectedEntry) { EntryDetailView(record: $0) }
            }
        }
    }

    private var monthEntries: [EntryRecord] {
        guard let start = BudgetMonth.start(of: month, calendar: snapshot.calendar),
              let end = BudgetMonth.end(of: month, calendar: snapshot.calendar) else { return [] }
        return snapshot.entries(touching: categoryId).filter { $0.date >= start && $0.date < end }
    }

    private func saveAllocation() {
        guard let amount = MoneyFormat.parse(allocationText.isEmpty ? "0" : allocationText, currency: store.currency) else {
            error = "Enter the planned amount as a number."
            return
        }
        guard !amount.isNegative else { error = "The plan can't be negative."; return }
        do { try store.setAllocation(amount, categoryId: categoryId, month: month) }
        catch { self.error = StoreError.from(error).errorDescription }
    }
}

// MARK: - Move money

struct MoveMoneySheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var sourceId: UUID? = nil
    let destinationId: UUID
    let month: String
    var onMoved: () -> Void = {}

    @State private var toId: UUID?
    @State private var amountText = ""
    @State private var error: String?
    @State private var needsConfirm = false

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var amount: Money? { MoneyFormat.parse(amountText, currency: store.currency) }

    var body: some View {
        NavigationStack {
            let budget = snapshot.budget
            let categories = snapshot.expenseCategories
            let to = toId ?? destinationId
            Form {
                Section {
                    Picker("From", selection: $sourceId) {
                        Text("Choose…").tag(nil as UUID?)
                        ForEach(categories.filter { $0.id != to }, id: \.id) { c in
                            Text("\(c.name) · \(budget.line(c.id, month: month).remaining.compact) left").tag(c.id as UUID?)
                        }
                    }
                    Picker("To", selection: Binding(get: { to }, set: { toId = $0 })) {
                        ForEach(categories, id: \.id) { c in Text(c.name).tag(c.id) }
                    }
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    }
                    let destLine = budget.line(to, month: month)
                    if destLine.isOverspent {
                        Button("Cover the overspending (\(destLine.remaining.magnitude.compact))") {
                            amountText = MoneyFormat.editable(destLine.remaining.magnitude)
                        }
                    }
                }

                if let sourceId, let amount, amount.isPositive {
                    let from = budget.line(sourceId, month: month)
                    let dest = budget.line(to, month: month)
                    Section("After the move") {
                        PreviewRow(name: snapshot.account(sourceId)?.name ?? "", before: from.remaining, after: from.remaining - amount)
                        PreviewRow(name: snapshot.account(to)?.name ?? "", before: dest.remaining, after: dest.remaining + amount)
                    }
                    if amount > from.remaining {
                        Section {
                            Label("This leaves \(snapshot.account(sourceId)?.name ?? "the source") overspent by \((amount - from.remaining).compact).",
                                  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Toggle("Move it anyway", isOn: $needsConfirm)
                        }
                    }
                }

                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Move money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Move", action: move) }
            }
        }
    }

    private func move() {
        guard let sourceId else { error = "Choose where the money comes from."; return }
        guard let amount, amount.isPositive else { error = "Enter an amount greater than zero."; return }
        do {
            try store.moveAllocation(amount, from: sourceId, to: toId ?? destinationId, month: month, allowOverdraw: needsConfirm)
            onMoved()
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

struct PreviewRow: View {
    let name: String
    let before: Money
    let after: Money

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(before.compact).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(after.compact).bold().monospacedDigit().foregroundStyle(after.isNegative ? .red : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(before.compact) becomes \(after.compact)")
    }
}

// MARK: - Category editor

struct CategoryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editing: LedgerAccountRecord? = nil

    @State private var name = ""
    @State private var isIncome = false
    @State private var group = "Essentials"
    @State private var policy: RolloverPolicy = .rollover
    @State private var reserve = false
    @State private var icon = "tag.fill"
    @State private var colorHex = "#3A7BD5"
    @State private var error: String?

    private let groups = ["Essentials", "Lifestyle", "Savings", "Other"]
    private let icons = ["tag.fill", "cart.fill", "house.fill", "car.fill", "bolt.fill", "fork.knife", "film.fill",
                         "bag.fill", "heart.fill", "airplane", "gift.fill", "graduationcap.fill", "pawprint.fill", "dumbbell.fill"]
    private let colors = ["#3A7BD5", "#2BA84A", "#F2A33A", "#E4572E", "#AF52DE", "#FF2D55", "#0E9AA7", "#8E8E93"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).accessibilityIdentifier("categoryName")
                    if editing == nil {
                        Picker("For", selection: $isIncome) {
                            Text("Spending").tag(false)
                            Text("Income").tag(true)
                        }.pickerStyle(.segmented)
                    }
                }
                if !isIncome {
                    Section {
                        Picker("Group", selection: $group) { ForEach(groups, id: \.self) { Text($0) } }
                        Picker("At month end", selection: $policy) {
                            ForEach(RolloverPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Toggle("Keep unspent money out of safe-to-spend", isOn: $reserve)
                    } footer: {
                        Text("Roll over: what's left stays here next month, and overspending carries until you cover it. Start fresh: leftovers go back to Available to allocate.")
                    }
                }
                Section("Look") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(icons, id: \.self) { s in
                                Button { icon = s } label: {
                                    IconBadge(symbol: s, color: icon == s ? Color(hex: colorHex) : .gray.opacity(0.4), size: 36)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 28, height: 28)
                                .overlay(Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white).opacity(colorHex == c ? 1 : 0))
                                .onTapGesture { colorHex = c }
                        }
                    }
                }
                if let editing {
                    Section {
                        Button(editing.archived ? "Restore" : "Archive category", role: .destructive) {
                            try? store.updateAccount(editing) { $0.archived.toggle() }
                            dismiss()
                        }
                    } footer: {
                        Text("Archiving hides it from the budget and quick add. Past spending keeps its category.")
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(editing == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                guard let editing else { return }
                name = editing.name
                isIncome = editing.kind == .income
                group = editing.group.isEmpty ? "Other" : editing.group
                policy = editing.policy
                reserve = editing.reserveInSafeToSpend
                icon = editing.icon.isEmpty ? "tag.fill" : editing.icon
                colorHex = editing.colorHex
            }
        }
    }

    private func save() {
        do {
            if let editing {
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Give the category a name."; return }
                try store.updateAccount(editing) {
                    $0.name = name.trimmingCharacters(in: .whitespaces)
                    $0.group = group
                    $0.policy = policy
                    $0.reserveInSafeToSpend = reserve
                    $0.icon = icon
                    $0.colorHex = colorHex
                }
            } else {
                let record = try store.createCategory(name: name, kind: isIncome ? .income : .expense, group: group,
                                                      icon: icon, colorHex: colorHex)
                if !isIncome {
                    try store.updateAccount(record) { $0.policy = policy; $0.reserveInSafeToSpend = reserve }
                }
            }
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
