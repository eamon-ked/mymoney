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
    @State private var addingReserve = false
    @State private var month: String?
    @State private var selected: UUID?
    @State private var addingCategory = false
    @State private var editingReserve: Reserve?
    @State private var addingGoal = false
    @State private var explanation: Explanation?
    @State private var error: String?
    @State private var filter = BudgetFilter.all

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
                // The first job comes before any figure; then one plain line about money with no budget
                firstJobSection(hasLastMonth: budget.allocationProgress(month: previousMonth).allocated.isPositive)
                summarySection(available: available, hasFunds: progress.planningFunds.isPositive)
                attentionSection

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

                if filter != .all {
                    let shown = groups.flatMap(\.categories).filter { filter.matches(budget.line($0.id, month: currentMonth)) }
                    Section {
                        HStack {
                            Label("Showing \(filter.title.lowercased())", systemImage: "line.3.horizontal.decrease.circle.fill")
                            Spacer()
                            Button("Show all") { filter = .all }.font(.subheadline.weight(.semibold))
                        }
                        if shown.isEmpty { Text("No categories match").foregroundStyle(.secondary) }
                    }
                }

                ForEach(groups, id: \.name) { group in
                    let categories = group.categories.filter { filter.matches(budget.line($0.id, month: currentMonth)) }
                    if !categories.isEmpty {
                    Section {
                        ForEach(categories, id: \.id) { category in
                            Button { selected = category.id } label: {
                                BudgetRow(category: category, line: budget.line(category.id, month: currentMonth),
                                          holdsLoans: snapshot.holdsLoans(category.id))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        let spent = group.categories.map { budget.line($0.id, month: currentMonth).spent }.sum(store.currency)
                        HStack {
                            Text(group.name); Spacer()
                            // A filtered list shows only some of the group, so its total would mislead
                            if spent.isPositive && filter == .all { Text("\(spent.compact) spent").monospacedDigit() }
                        }
                    }
                    }
                }

                if !snapshot.expenseCategories.isEmpty { savingsSection }

                if let error { Section { FieldError(message: error) } }
            }
            .listStyle(.insetGrouped)
            .canvas()
            .navigationTitle("Budget")
            .paywall($paywall)
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
                        Picker("Show", selection: $filter) {
                            ForEach(BudgetFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Button { addingCategory = true } label: { Label("New category", systemImage: "folder.badge.plus") }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter and new category")
                }
                GlobalAddButton()
            }
            .sheet(item: Binding(get: { selected.map(IdentifiedUUID.init) }, set: { selected = $0?.id })) { item in
                CategoryDetailView(categoryId: item.id, month: currentMonth)
            }
            .sheet(isPresented: $addingCategory) { CategoryEditor() }
            .sheet(item: $editingReserve) { ReserveEditor(editing: $0) }
            .sheet(isPresented: $addingGoal) { ReserveEditor(asGoal: true) }
            .sheet(isPresented: $addingReserve) { ReserveEditor() }
            .sheet(item: $explanation) { ExplanationSheet(explanation: $0) }
        }
    }

    /// Every goal and set-aside, the one place savings live. Their money already has a job,
    /// so it's out of "Not planned yet" just as it's out of Safe to spend.
    @ViewBuilder private var savingsSection: some View {
        Section {
            if snapshot.goals.isEmpty {
                Button { addingGoal = true } label: { Label("Start a savings goal", systemImage: "target") }
                    .accessibilityIdentifier("startGoal")
            }
            ForEach(snapshot.reserves) { r in
                if let progress = snapshot.progress(of: r) {
                    NavigationLink { GoalDetailView(goalId: r.id) } label: { GoalRow(goal: r, progress: progress) }
                } else {
                    Button { editingReserve = r } label: {
                        ListRow(title: r.name, caption: "Set aside in \(snapshot.account(r.accountId)?.name ?? "an account")",
                                symbol: "lock.fill", color: Palette.plan) { AmountPill(r.amount) }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Savings"); Spacer()
                Menu("Add") {
                    Button { newGoal() } label: { Label("Savings goal", systemImage: "target") }
                    Button { addingReserve = true } label: { Label("Money set aside", systemImage: "lock") }
                }
                .font(.subheadline)
            }
        } footer: {
            Text("Saved money isn't counted in Not planned yet or Safe to spend.")
        }
    }

    /// One goal is free; more need Plus
    private func newGoal() {
        if plus.isPlus || snapshot.goals.isEmpty { addingGoal = true } else { paywall = .goals }
    }

    private var previousMonth: String { BudgetMonth.adding(-1, to: currentMonth, calendar: snapshot.calendar) }

    private var groups: [(name: String, categories: [LedgerAccountRecord])] { snapshot.expenseCategoryGroups }

    private func copyLastMonth() {
        do { try store.copyPlan(from: previousMonth, to: currentMonth) } catch { self.error = StoreError.from(error).errorDescription }
    }

    /// Says when card debt is already taken out, so this doesn't look like money missing
    /// Nothing budgeted by hand this month: setting the main budgets is the job, before any number
    @ViewBuilder private func firstJobSection(hasLastMonth: Bool) -> some View {
        let month = currentMonth
        let categories = groups.flatMap(\.categories)
        let nothingSet = !categories.isEmpty && categories.allSatisfy { !snapshot.budget.line($0.id, month: month).allocated.isPositive }
        let next = categories.first { !snapshot.budget.line($0.id, month: month).planned.isPositive }
        if nothingSet && !hasLastMonth, let next {
            Section {
                Button { selected = next.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set budgets for your main costs").font(.headline)
                        Text("Start with \(categories.prefix(3).map(\.name).joined(separator: ", ")). One tap each.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Set \(next.name)").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One plain line about money with no budget. It's a planning figure, kept smaller than Safe to spend
    /// on Home, and it says so; it disappears when there's nothing to say.
    @ViewBuilder private func summarySection(available: Money, hasFunds: Bool) -> some View {
        Section {
            if !hasFunds {
                Text("Add an account with money in it to start budgeting.").foregroundStyle(.secondary)
            } else if available.isNegative {
                Button { explanation = availableExplanation(available) } label: {
                    AlertRow(symbol: "exclamationmark.triangle.fill", color: .red,
                             text: "Your budgets are \(available.magnitude.compact) more than you have",
                             detail: "Lower one of the budgets below.", action: "Why?")
                }.buttonStyle(.plain)
            } else if available.isZero {
                Label("All your money has a budget", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            } else {
                Button { explanation = availableExplanation(available) } label: {
                    // One figure; what it leaves out (cards owed, goals) is one tap away
                    HStack(alignment: .firstTextBaseline) {
                        Text("Not planned yet")
                        Spacer()
                        Text(available.compact).font(.title3.bold()).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how this is worked out")
            }
        }
    }

    /// What needs doing on this month's budget, at most a few rows, each with one action
    @ViewBuilder private var attentionSection: some View {
        let budget = snapshot.budget
        let lines = snapshot.expenseCategories.map { ($0, budget.line($0.id, month: currentMonth)) }
        let over = lines.filter { $0.1.isOverBudget }
        let noBudget = lines.filter { $0.1.isUnbudgetedSpending }.sorted { $0.1.spent > $1.1.spent }
        if !over.isEmpty || !noBudget.isEmpty {
            Section("Needs attention") {
                ForEach(over, id: \.0.id) { c, line in
                    Button { selected = c.id } label: {
                        AlertRow(symbol: "exclamationmark.circle.fill", color: .red,
                                 text: "\(c.name) went \(line.remaining.magnitude.compact) over its budget",
                                 action: "Fix it")
                    }.buttonStyle(.plain)
                }
                if let first = noBudget.first {
                    let total = noBudget.map(\.1.spent).sum(store.currency)
                    Button { selected = first.0.id } label: {
                        AlertRow(symbol: "questionmark.circle.fill", color: .orange,
                                 text: "\(total.compact) spent with no budget",
                                 detail: noBudget.prefix(3).map(\.0.name).joined(separator: ", ") + (noBudget.count > 3 ? " and \(noBudget.count - 3) more" : ""),
                                 action: noBudget.count == 1 ? "Set budget" : "Set budgets")
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func availableExplanation(_ available: Money) -> Explanation {
        let budget = snapshot.budget
        let end = BudgetMonth.end(of: currentMonth, calendar: snapshot.calendar)?.addingTimeInterval(-1)
        let held = snapshot.accounts.filter(\.onBudget).map {
            BreakdownItem(label: $0.name, amount: snapshot.ledger.balance(of: $0.id, asOf: end))
        }
        let setAside = snapshot.expenseCategories.compactMap { c -> BreakdownItem? in
            let r = budget.line(c.id, month: currentMonth).remaining
            return r.isPositive ? BreakdownItem(label: c.name, amount: r) : nil
        }
        let future = snapshot.budget.allocations.filter { $0.month > currentMonth }.map(\.amount).sum(store.currency)
        var sections: [(String, [BreakdownItem], String)] = [("Money in budget accounts", held, ""),
                                                             ("Still left in budgets", setAside, "−")]
        if !future.isZero { sections.append(("Planned for later months", [BreakdownItem(label: "Future months", amount: future)], "−")) }
        let saved = snapshot.reserves.filter { snapshot.account($0.accountId)?.onBudget == true && !$0.amount.isZero }
            .map { BreakdownItem(label: $0.name, amount: $0.amount) }
        if !saved.isEmpty { sections.append(("Saved in goals", saved, "−")) }
        return Explanation(title: "Not planned yet", total: available,
                           definition: "Money in your accounts that no budget uses yet. It isn't extra cash: Safe to spend on Home is what you can actually spend. Setting a budget doesn't move money out of any account.",
                           sections: sections,
                           notes: ["Bills due this month are planned in their category automatically, and count until they're paid.",
                                   "You don't have to plan all of it.", "Spending within a budget lowers what's left in it. Spending past a budget, or where there's no budget, lowers this number.",
                                   "Safe to spend on Home is a different number: it holds back only bills due before payday, and treats what's left in categories like Groceries as money you can spend. Budget also takes out everything still owed on cards in your budget, and everything you've planned."])
    }
}

struct IdentifiedUUID: Identifiable { let id: UUID }

struct BudgetRow: View {
    let category: LedgerAccountRecord
    let line: CategoryLine
    var holdsLoans = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let planned = line.planned
            ListRow(title: category.name, caption: caption(planned: planned),
                    symbol: category.icon, color: Color(hex: category.colorHex)) {
                AmountPill(text: pill(planned: planned),
                           style: line.isOverBudget ? .negative : (nearlySpent(planned) ? .warning : .neutral))
            }
            if planned.isPositive {
                ProgressBar(value: Double(line.spent.minorUnits) / Double(planned.minorUnits),
                            tint: line.isOverBudget ? .red : Color(hex: category.colorHex))
                    .padding(.leading, 46)
            }
        }
        .padding(.vertical, 2)
    }

    private func caption(planned: Money) -> String? {
        // Bills are planned automatically; until they're paid they show as not yet spent
        if line.unpaidBills.isPositive {
            return line.spent.isPositive
                ? "\(line.unpaidBills.compact) for bills not yet paid"
                : "\(line.unpaidBills.compact) for bills, not yet paid"
        }
        // The bar shows how much of the budget is spent; the amount says what's left
        if planned.isPositive { return nil }
        return line.spent.isPositive ? "\(line.spent.compact) spent" : "No budget set"
    }

    /// Colour only where it needs a look: nine-tenths or more of a budget gone
    private func nearlySpent(_ planned: Money) -> Bool {
        planned.isPositive && line.remaining.isPositive && line.remaining.minorUnits * 10 <= planned.minorUnits
    }

    private func pill(planned: Money) -> String {
        if line.isOverBudget { return "\(line.remaining.magnitude.compact) over" }
        if !planned.isPositive { return line.spent.isPositive ? "No budget" : "Set budget" }
        if line.remaining.isZero { return holdsLoans ? "Paid" : "All spent" }
        return "\(line.remaining.compact) left"
    }
}

extension CategoryLine {
    /// More spent than the budget allowed. Spending where no budget was set isn't "over"
    var isOverBudget: Bool { planned.isPositive && isOverspent }
    /// Money spent in a category that has no budget this month
    var isUnbudgetedSpending: Bool { !planned.isPositive && spent.isPositive }
}

/// Narrows the Budget list to the categories that need a look
enum BudgetFilter: CaseIterable {
    case all, over, notPlanned, moneyLeft

    var title: String {
        switch self {
        case .all: "All categories"
        case .over: "Over budget"
        case .notPlanned: "No budget set"
        case .moneyLeft: "Money left"
        }
    }

    func matches(_ line: CategoryLine) -> Bool {
        switch self {
        case .all: true
        case .over: line.isOverBudget
        case .notPlanned: !line.planned.isPositive
        case .moneyLeft: line.remaining.isPositive
        }
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
    /// Entries shown only for one "what went in" row
    @State private var only: String?
    @State private var choosingLoans = false
    @FocusState private var allocationFocused: Bool

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            if let category = snapshot.account(categoryId) {
                let line = snapshot.budget.line(categoryId, month: month)
                List {
                    Section {
                        HStack {
                            Text("Budget this month")
                            Spacer()
                            Text(store.currency).foregroundStyle(.secondary)
                            TextField("0", text: $allocationText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .focused($allocationFocused)
                                .onSubmit(saveAllocation)
                                .accessibilityIdentifier("allocationField")
                        }
                        if line.fromBills.isPositive {
                            LabeledContent("Added for bills", value: line.fromBills.compact)
                        }
                        if !line.carriedIn.isZero {
                            LabeledContent(line.carriedIn.isNegative ? "Overspent last month" : "Carried from last month",
                                           value: line.carriedIn.signed)
                        }
                        LabeledContent("Spent", value: line.spent.compact)
                        if line.unpaidBills.isPositive {
                            LabeledContent("Bills not yet spent", value: line.unpaidBills.compact)
                        }
                        if line.planned.isPositive {
                            LabeledContent {
                                Text(line.remaining.magnitude.compact).bold().foregroundStyle(line.isOverBudget ? .red : .primary)
                            } label: {
                                Text(line.isOverBudget ? "Over budget by" : "Left").bold()
                            }
                        }
                        Button { moving = true } label: { Label("Move money from another category", systemImage: "arrow.left.arrow.right") }
                    } footer: {
                        if line.isUnbudgetedSpending {
                            Text("No budget is set here yet. Enter one above, or move money in from another category to cover what's spent.")
                        } else if line.isOverBudget {
                            Text("\(line.remaining.magnitude.compact) more than the budget was spent. Raise the budget, or move money in from another category.")
                        } else if line.fromBills.isPositive && !snapshot.holdsLoans(categoryId) {
                            Text("This month's bills are planned here automatically, so they're counted before they're paid.")
                        }
                    }

                    let parts = snapshot.breakdown(categoryId, month: month)
                    let holdsLoans = snapshot.holdsLoans(categoryId)
                    // Only when it groups something; otherwise the entries below say it all
                    if holdsLoans || parts.contains(where: { $0.count > 1 }) {
                        Section("What went in") {
                            ForEach(parts) { part in
                                if let loanId = part.loanId {
                                    NavigationLink { AccountDetailView(accountId: loanId) } label: { partRow(part) }
                                } else {
                                    Button { only = only == part.name ? nil : part.name } label: {
                                        partRow(part).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(only == part.name ? .isSelected : [])
                                }
                            }
                            if holdsLoans {
                                Button { choosingLoans = true } label: { Label("Choose loans", systemImage: "checklist") }
                                    .accessibilityIdentifier("chooseLoans")
                            }
                        }
                    }

                    // A loan's payments are in its row above; tapping it shows them
                    let loanIds = Set(snapshot.loans(in: categoryId).map(\.id))
                    let entries = monthEntries.filter { record in
                        (only == nil || label(record).caseInsensitiveCompare(only!) == .orderedSame)
                            && !record.lines.contains { loanIds.contains($0.accountId) }
                    }
                    if !(holdsLoans && entries.isEmpty) {
                    Section {
                        if entries.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                        ForEach(entries, id: \.id) { record in
                            Button { selectedEntry = record } label: { EntryRow(record: record, snapshot: snapshot) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(only ?? "This month's spending")
                            Spacer()
                            if only != nil { Button("Show all") { only = nil }.font(.footnote) }
                        }
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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { if allocationFocused { saveAllocation() }; dismiss() }
                    }
                    if category.kind == .expense {
                        let pinned = snapshot.settings.pinnedCategoryIds.contains(categoryId)
                        ToolbarItem(placement: .cancellationAction) {
                            Button { togglePin() } label: {
                                Label(pinned ? "Unpin from Home" : "Pin to Home", systemImage: pinned ? "pin.slash" : "pin")
                            }
                        }
                    }
                }
                .onAppear { allocationText = shown(line.allocated) }
                .onChange(of: allocationFocused) { _, focused in
                    let allocated = snapshot.budget.line(categoryId, month: month).allocated
                    if focused { allocationText = MoneyFormat.editable(allocated, emptyWhenZero: true) }
                    else { saveAllocation(); allocationText = shown(snapshot.budget.line(categoryId, month: month).allocated) }
                }
                .sheet(isPresented: $moving) {
                    MoveMoneySheet(destinationId: categoryId, month: month) {
                        allocationText = shown(snapshot.budget.line(categoryId, month: month).allocated)
                    }
                }
                .sheet(isPresented: $editing) { CategoryEditor(editing: category) }
                .sheet(item: $selectedEntry) { EntryDetailView(record: $0) }
                .sheet(isPresented: $choosingLoans) { NavigationStack { LoansInCategoryView(categoryId: categoryId) } }
            }
        }
    }

    private var monthEntries: [EntryRecord] { snapshot.entries(in: categoryId, month: month) }

    /// "2,750" while not being edited, like every other amount on the screen
    private func shown(_ money: Money) -> String {
        guard !money.isZero else { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = Currency.scale(of: money.currency)
        return f.string(from: money.decimal as NSDecimalNumber) ?? MoneyFormat.editable(money)
    }

    private func label(_ record: EntryRecord) -> String {
        let memo = record.memo.trimmingCharacters(in: .whitespaces)
        return memo.isEmpty ? "No description" : memo
    }

    private func partRow(_ part: FinanceSnapshot.CategoryPart) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                if let detail = part.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(part.amount.compact).monospacedDigit()
        }
    }

    private func togglePin() {
        do {
            try store.updateSettings { s in
                if let i = s.pinnedCategoryIds.firstIndex(of: categoryId) { s.pinnedCategoryIds.remove(at: i) }
                else { s.pinnedCategoryIds.append(categoryId) }
            }
        } catch { self.error = StoreError.from(error).errorDescription }
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
    /// Made from a loan's category picker: a spending category in Bills
    var forLoans = false
    var onCreated: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var isIncome = false
    @State private var group = "Essentials"
    @State private var policy: RolloverPolicy = .rollover
    @State private var reserve = false
    @State private var icon = "tag.fill"
    @State private var colorHex = "#3A7BD5"
    @State private var error: String?
    @State private var showMore = false

    private let groups = FinanceSnapshot.categoryGroupChoices
    private let icons = ["tag.fill", "cart.fill", "house.fill", "car.fill", "bolt.fill", "fork.knife", "film.fill",
                         "bag.fill", "heart.fill", "airplane", "gift.fill", "graduationcap.fill", "pawprint.fill", "dumbbell.fill", "building.columns.fill"]
    private let colors = ["#3A7BD5", "#2BA84A", "#F2A33A", "#E4572E", "#AF52DE", "#FF2D55", "#0E9AA7", "#8E8E93"]
    private let colorNames = ["Blue", "Green", "Amber", "Red", "Purple", "Pink", "Teal", "Grey"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).accessibilityIdentifier("categoryName")
                    if editing == nil && !forLoans {
                        Picker("For", selection: $isIncome) {
                            Text("Spending").tag(false)
                            Text("Income").tag(true)
                        }.pickerStyle(.segmented)
                    }
                }
                if !isIncome {
                    Section {
                        Picker("Group", selection: $group) { ForEach(groups, id: \.self) { Text($0) } }
                    }
                    // A category like "Loans" can hold the payments of any number of loans
                    if let editing, store.snapshot.accountRecords.contains(where: { $0.kind == .loan && !$0.archived }) {
                        Section {
                            NavigationLink { LoansInCategoryView(categoryId: editing.id) } label: {
                                LabeledContent("Loans", value: loansSummary(editing.id))
                            }
                            .accessibilityIdentifier("categoryLoans")
                        } footer: {
                            Text("Pick loans whose payments count here.")
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(icons, id: \.self) { s in
                            Button { icon = s } label: {
                                IconBadge(symbol: s, color: icon == s ? Color(hex: colorHex) : .gray.opacity(0.4), size: 40)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(icon == s ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    DisclosureGroup("More options", isExpanded: $showMore) {
                        if !isIncome {
                            Picker("At month end", selection: $policy) {
                                ForEach(RolloverPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            Toggle("Keep unspent money out of safe-to-spend", isOn: $reserve)
                            Text("Roll over: what's left stays here next month, and overspending carries until you cover it. Start fresh: leftovers go back to Not planned yet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack {
                            ForEach(Array(zip(colors, colorNames)), id: \.0) { c, label in
                                Button { colorHex = c } label: {
                                    Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                        .overlay(Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                            .opacity(colorHex == c ? 1 : 0))
                                        .frame(minWidth: 36, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(label)
                                .accessibilityAddTraits(colorHex == c ? .isSelected : [])
                            }
                        }
                        if let editing {
                            Button(editing.archived ? "Restore" : "Archive category", role: .destructive) {
                                try? store.updateAccount(editing) { $0.archived.toggle() }
                                dismiss()
                            }
                            Text("Archiving hides it from the budget and quick add. Past spending keeps its category.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
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
                guard let editing else {
                    if forLoans { group = "Bills"; icon = "building.columns.fill" }
                    return
                }
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

    private func loansSummary(_ categoryId: UUID) -> String {
        let loans = store.snapshot.loans(in: categoryId)
        switch loans.count {
        case 0: return "None"
        case 1: return loans[0].name
        default: return "\(loans.count) loans"
        }
    }

    private func save() {
        do {
            let record = try store.saveCategory(editing, name: name, isIncome: isIncome, group: group, policy: policy,
                                                reserve: reserve, icon: icon, colorHex: colorHex)
            if editing == nil { onCreated(record.id) }
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

/// Tick the loans whose payments count in a category; several can share one
struct LoansInCategoryView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: UUID
    @State private var error: String?

    var body: some View {
        let snapshot = store.snapshot
        let loans = snapshot.accountRecords.filter { $0.kind == .loan && !$0.archived }
        List {
            Section {
                if loans.isEmpty { Text("No loans yet. Add one in Accounts.").foregroundStyle(.secondary) }
                ForEach(loans, id: \.id) { loan in
                    let here = snapshot.loanCategories[loan.id] == categoryId
                    Button { toggle(loan, here: here) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loan.name).foregroundStyle(.primary)
                                if let terms = loan.debtTerms {
                                    Text("\(terms.monthlyPayment.compact) a month").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if here { Image(systemName: "checkmark").foregroundStyle(Palette.brand).fontWeight(.semibold) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(here ? .isSelected : [])
                }
            } footer: {
                Text("Their payments count here in Budget and Reports, past ones too. A loan you untick goes back to Loan payments.")
            }
            if let error { Section { FieldError(message: error) } }
        }
        .navigationTitle("Loans in \(snapshot.account(categoryId)?.name ?? "this category")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func toggle(_ loan: LedgerAccountRecord, here: Bool) {
        do { try store.setLoanCategory(here ? nil : categoryId, for: loan.id) }
        catch { self.error = StoreError.from(error).errorDescription }
    }
}
