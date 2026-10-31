//
//  RedesignBudget.swift
//  Nokael Money
//
//  A budget category's page and settings, moving money between categories,
//  the loans a category holds, and savings goals and money set aside.
//

import SwiftUI
import Charts
import NokaelCore

extension Redesign {
    struct CategoryPage: View {
        let category: Category
        @Environment(AppModel.self) private var app
        @State private var section = "Overview"
        @State private var allocation = ""
        @State private var only: CategoryPartFilter?
        @FocusState private var editingBudget: Bool

        private struct CategoryPartFilter: Equatable { let id: String; let name: String; let ids: Set<UUID> }

        var body: some View {
            let share = category.budget > 0 ? (category.spent / category.budget as NSDecimalNumber).doubleValue : 0
            let s = app.snapshot
            let entries = s.entries(in: category.id, month: app.month)
            let spending = entries.compactMap { app.transaction($0.id) }.filter { only == nil || only!.ids.contains($0.id) }
            let pinned = app.store.settings.pinnedCategoryIds.contains(category.id)

            VStack(alignment: .leading, spacing: 0) {
                Text(app.monthStart.formatted(.dateTime.month(.wide).year())).rdText(.caption).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    app.amount(category.spent).rdText(.figure).fontWeight(.regular)
                    Text(private: "/ \(app.number(category.budget))").rdText(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.top, 12).padding(.bottom, 20)
                HStack(spacing: 12) { ProgressBar(value: share); Text(private: app.percent(share)).rdText(.caption).monospacedDigit() }
                Text(private: category.remaining < 0 ? "\(app.money(-category.remaining)) over budget" : "\(app.money(category.remaining)) remaining")
                    .rdText(.caption).foregroundStyle(category.remaining < 0 ? Theme.destructive : Theme.muted).padding(.top, 12)
            }
            .rdPanel(padding: 20)

            HStack(spacing: 4) {
                ForEach(["Overview", "Transactions"], id: \.self) { s in
                    Button { section = s } label: {
                        Text(s).rdText(.captionStrong)
                            .foregroundStyle(section == s ? Theme.primary : Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(section == s ? Theme.card : .clear, in: Capsule())
                            .shadow(color: section == s ? .black.opacity(0.05) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Theme.secondary, in: Capsule())
            .padding(.top, 20)

            if section == "Overview" {
                Field(label: "Budget this month") {
                    TextField("0", text: $allocation).keyboardType(.decimalPad).focused($editingBudget)
                        .accessibilityIdentifier("allocationField")
                        .onSubmit(saveAllocation)
                        .toolbar {
                            if editingBudget {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { editingBudget = false }.fontWeight(.semibold)
                                }
                            }
                        }
                }
                .padding(.top, 20)
                .onChange(of: editingBudget) { _, now in if !now { saveAllocation() } }
                DetailCard {
                    if category.fromBills != 0 { DetailRow(label: "Added for bills", value: app.money(category.fromBills)) }
                    if category.carriedIn > 0 { DetailRow(label: "Carried from last month", value: app.money(category.carriedIn)) }
                    if category.carriedIn < 0 { DetailRow(label: "Overspent last month", value: app.money(-category.carriedIn)) }
                    DetailRow(label: "Spent", value: app.money(category.spent))
                    if category.unpaidBills > 0 { DetailRow(label: "Bills not yet paid", value: app.money(category.unpaidBills)) }
                    DetailRow(label: category.remaining < 0 ? "Over budget by" : "Left", value: app.money(abs(category.remaining)))
                }
                .padding(.top, 12)
                Button { app.open(.moveMoney(category.id)) } label: { Label("Move money from another category", systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(QuietButtonStyle()).padding(.top, 12)
                history
                parts
                SectionHeading(title: "Recent Spending", action: only == nil ? nil : "Show all") { only = nil }.padding(.top, 24)
                Divided(items: Array(spending.prefix(8))) { TransactionRow(t: $0) }
                if spending.isEmpty { Redesign.footnote("Nothing spent here this month.").padding(.vertical, 12) }
            } else {
                Divided(items: spending) { TransactionRow(t: $0) }.padding(.top, 12)
                if spending.isEmpty { EmptyNote(text: "Nothing spent here this month.") }
            }

            VStack(spacing: 12) {
                Button { app.open(.editCategory(category.id)) } label: { Text("Rename, group or settings") }
                    .buttonStyle(QuietButtonStyle())
                Button { app.togglePin(category.id) } label: { Label(pinned ? "Unpin from Home" : "Pin to Home", systemImage: pinned ? "pin.slash" : "pin") }
                    .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.top, 24)
            Redesign.footnote("Your monthly plan is separate from available cash. Bills in this category are included in it, never counted twice.")
                .padding(.top, 12).padding(.horizontal, 4)
            .onAppear { allocation = app.editable(category.allocated) }
        }

        private func saveAllocation() {
            let value = allocation.isEmpty ? Money.zero(app.currency) : app.parse(allocation)
            guard let value, !value.isNegative else { return }
            guard value.decimal != category.allocated else { return }
            if let problem = app.setBudget(category.id, to: value) { app.toast = Toast(message: problem, isError: true) }
        }

        /// What this month's spending was made of, such as each loan or each merchant
        @ViewBuilder private var parts: some View {
            let s = app.snapshot
            let list = s.breakdown(category.id, month: app.month)
            if list.count > 1 || s.holdsLoans(category.id) {
                SectionHeading(title: "What went in", action: s.holdsLoans(category.id) || category.group == "Bills" ? "Choose loans" : nil) {
                    app.open(.loansInCategory(category.id))
                }
                .padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, part in
                        Button {
                            if let loan = part.loanId { app.open(.account(loan)) } else {
                                let ids = Set(s.entries(in: category.id, month: app.month).filter { part.name == ($0.memo.isEmpty ? category.name : $0.memo) }.map(\.id))
                                only = CategoryPartFilter(id: part.id, name: part.name, ids: ids)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.hidesDetails ? "Part \(i + 1)" : part.name).rdText(.detailStrong)
                                    if let detail = part.detail, !app.hidesDetails { Text(detail).rdText(.caption).foregroundStyle(Theme.muted) }
                                }
                                Spacer()
                                app.amount(part.amount.decimal).rdText(.amount)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < list.count - 1 { Redesign.hairline }
                    }
                }
                .rdPanel(padding: 14)
            }
        }

        /// Six months of spending in this category, this month in green
        private var history: some View {
            let months = (0..<6).map { BudgetMonth.adding($0 - 5, to: app.month, calendar: app.calendar) }
            let values = months.map { (app.snapshot.budget.spent(category.id, month: $0).decimal as NSDecimalNumber).doubleValue }
            return VStack(alignment: .leading, spacing: 4) {
                Text("Monthly spending").rdText(.caption).foregroundStyle(Theme.muted)
                if app.hidesCharts || app.hidesAmounts { ChartHidden(height: 140) } else { chart(months, values) }
            }
            .rdPanel(padding: 14)
            .padding(.top, 16)
        }

        private func chart(_ months: [String], _ values: [Double]) -> some View {
            Chart(Array(zip(months, values).enumerated()), id: \.offset) { index, point in
                BarMark(x: .value("Month", (BudgetMonth.start(of: point.0, calendar: app.calendar) ?? app.today).formatted(.dateTime.month(.abbreviated))),
                        y: .value("Spent", point.1), width: 22)
                    .foregroundStyle(index == 5 ? Theme.primary : Theme.border)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption).foregroundStyle(Theme.muted) } }
            .frame(height: 140)
        }
    }

    /// New and existing categories: name, group, what's left at month end, safe-to-spend, icon and archiving
    struct CategoryForm: View {
        let editing: LedgerAccountRecord?
        @Environment(AppModel.self) private var app
        @State private var name = ""
        @State private var income = false
        @State private var group = "Essentials"
        @State private var policy: RolloverPolicy = .rollover
        @State private var reserve = false
        @State private var icon = "tag.fill"
        @State private var budget = ""
        @State private var problem: String?

        private let icons = ["tag.fill", "cart.fill", "house.fill", "car.fill", "bolt.fill", "fork.knife", "film.fill", "bag.fill",
                             "heart.fill", "airplane", "gift.fill", "graduationcap.fill", "pawprint.fill", "dumbbell.fill", "building.columns.fill",
                             "wifi", "cup.and.saucer.fill", "person.2.fill"]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Category name") { TextField("e.g. Health", text: $name).accessibilityIdentifier("categoryName") }
                if editing == nil {
                    Pills(options: ["Spending", "Income"], selection: Binding(get: { income ? "Income" : "Spending" }, set: { income = $0 == "Income" }))
                }
                if !income {
                    Field(label: "Group") { Choice(value: $group, options: FinanceSnapshot.categoryGroupChoices) { $0 } }
                    if editing == nil {
                        AmountBox(label: "Monthly budget in \(app.currency) (optional)", text: $budget, autofocus: false)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon").rdText(.detail)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol.replacingOccurrences(of: ".fill", with: ""))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(icon == symbol ? Theme.onPrimary : Theme.primary)
                                    .background(icon == symbol ? Theme.primary : Theme.primary.opacity(0.075), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                        }
                    }
                }
                if !income {
                    Field(label: "At the end of the month") {
                        Choice(value: $policy, options: RolloverPolicy.allCases) { $0.label }
                    }
                    ToggleRow(title: "Keep unspent money out of safe to spend",
                              detail: "For essentials like groceries: what's left in the budget stays set aside.", isOn: $reserve)
                    if let editing, app.snapshot.holdsLoans(editing.id) || group == "Bills" {
                        Button("Choose the loans in it") { app.open(.loansInCategory(editing.id)) }
                            .rdText(.label).foregroundStyle(Theme.primary).frame(minHeight: 44)
                            .accessibilityIdentifier("categoryLoans")
                    }
                }
                Problem(text: problem)
                Button(editing == nil ? "Add category" : "Save", action: save).buttonStyle(PrimaryButtonStyle())
                if let editing {
                    Button(editing.archived ? "Restore category" : "Archive category") {
                        problem = app.attempt(editing.archived ? "Category restored." : "Category archived.") {
                            try app.store.updateAccount(editing) { $0.archived.toggle() }
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .onAppear {
                guard let editing else { return }
                name = editing.name
                income = editing.kind == .income
                group = editing.group.isEmpty ? "Other" : editing.group
                policy = editing.policy
                reserve = editing.reserveInSafeToSpend
                icon = editing.icon
            }
        }

        private func save() {
            problem = nil
            let title = name.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { problem = "Give the category a name."; return }
            let budgetValue = budget.isEmpty ? nil : app.parse(budget)
            if !budget.isEmpty && budgetValue == nil { problem = "Enter the budget as a number."; return }
            problem = app.attempt(editing == nil ? "Category added." : "Category saved.") {
                let r = try app.store.saveCategory(editing, name: title, isIncome: income, group: income ? "" : group, policy: policy,
                                                   reserve: reserve, icon: icon, colorHex: editing?.colorHex ?? "#8E8E93")
                if editing == nil, !income, let budgetValue, budgetValue.isPositive {
                    try app.store.setAllocation(budgetValue, categoryId: r.id, month: app.month)
                }
            }
        }
    }

    struct MoveMoneyForm: View {
        let destination: UUID
        @Environment(AppModel.self) private var app
        @State private var sourceId: UUID?
        @State private var toId: UUID?
        @State private var amount = ""
        @State private var overdraw = false
        @State private var problem: String?

        var body: some View {
            let cats = app.categories()
            let source = cats.first { $0.id == sourceId }
            let target = cats.first { $0.id == toId }
            let value = app.parse(amount)?.decimal ?? 0
            VStack(alignment: .leading, spacing: 16) {
                AmountBox(label: "Amount in \(app.currency)", text: $amount)
                if let target, target.remaining < 0 {
                    Button("Cover the overspending (\(app.money(-target.remaining)))") { amount = app.editable(-target.remaining) }
                        .rdText(.captionStrong).foregroundStyle(Theme.primary)
                }
                Field(label: "From") {
                    Choice(value: $sourceId, options: [nil] + cats.filter { $0.id != toId }.map { Optional($0.id) }) { id in
                        guard let c = cats.first(where: { $0.id == id }) else { return "Choose" }
                        return "\(app.hidesDetails ? "Category" : c.name) · \(app.money(c.remaining)) left"
                    }
                }
                Field(label: "To") {
                    Choice(value: $toId, options: cats.map { Optional($0.id) }) { id in
                        cats.first { $0.id == id }.map { app.hidesDetails ? "Category" : $0.name } ?? "Choose"
                    }
                }
                if let source, let target, value > 0 {
                    DetailCard {
                        DetailRow(label: "\(app.hidesDetails ? "From" : source.name) after", value: app.money(source.remaining - value))
                        DetailRow(label: "\(app.hidesDetails ? "To" : target.name) after", value: app.money(target.remaining + value))
                    }
                    if source.remaining - value < 0 {
                        ToggleRow(title: "Move it anyway", detail: "That's more than is left there, so it would go over budget.", isOn: $overdraw)
                    }
                }
                Problem(text: problem)
                Button("Move") {
                    guard let money = app.parse(amount), money.isPositive else { problem = "Enter an amount."; return }
                    guard let sourceId, let toId else { problem = "Choose both categories."; return }
                    problem = app.attempt("Budget moved.") {
                        try app.store.moveAllocation(money, from: sourceId, to: toId, month: app.month, allowOverdraw: overdraw)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .onAppear {
                toId = destination
                sourceId = cats.filter { $0.id != destination && $0.remaining > 0 }.max { $0.remaining < $1.remaining }?.id
            }
        }
    }

    /// Ticks which loans' payments count in this category
    struct LoansInCategory: View {
        let categoryId: UUID
        @Environment(AppModel.self) private var app

        var body: some View {
            let s = app.snapshot
            Text("Payments to the loans you tick count in this category, past ones too.").rdText(.body).foregroundStyle(Theme.muted).padding(.bottom, 16)
            if app.loans.isEmpty { EmptyNote(text: "No loans yet. Add one from Accounts.") }
            VStack(spacing: 0) {
                ForEach(Array(app.loans.enumerated()), id: \.element.id) { i, loan in
                    let on = s.loanCategories[loan.id] == categoryId
                    Button {
                        app.attempt(closing: false) { try app.store.setLoanCategory(on ? nil : categoryId, for: loan.id) }
                            .map { app.toast = Toast(message: $0, isError: true) }
                    } label: {
                        HStack {
                            Text(app.accountLabel(loan.id)).rdText(.cardTitle)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.primary)
                        }
                        .frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    if i < app.loans.count - 1 { Redesign.hairline }
                }
            }
            .rdPanel(padding: 14)
        }
    }
}

// MARK: - Goals and money set aside

extension Redesign {
    struct GoalPage: View {
        let goal: Reserve
        @Environment(AppModel.self) private var app

        var body: some View {
            let p = app.snapshot.progress(of: goal)
            VStack(alignment: .leading, spacing: 0) {
                app.amount(goal.amount.decimal).rdText(.balance)
                Text(private: "saved of \(app.money(goal.target ?? .zero(app.currency)))").rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
                ProgressBar(value: p?.fraction ?? 0).padding(.top, 20)
                if let p { Text(private: GoalRow.advice(p, app: app)).rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 10) }
            }
            .rdPanel(padding: 20)
            DetailCard {
                if let p { DetailRow(label: "Still to save", value: app.money(p.remaining)) }
                DetailRow(label: "Reach it by", value: goal.targetDate.map { app.fullDay($0) } ?? "No date")
                if case .needsPerMonth(let m, let months)? = p?.status {
                    DetailRow(label: "Each month", value: "\(app.money(m)) for \(months) month\(months == 1 ? "" : "s")")
                }
                DetailRow(label: "Kept in", value: app.accountLabel(goal.accountId))
            }
            .padding(.top, 20)
            VStack(spacing: 12) {
                Button("Add money") { app.open(.goalMoney(goal.id, adding: true)) }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("addToGoal")
                Button("Take money out") { app.open(.goalMoney(goal.id, adding: false)) }.buttonStyle(QuietButtonStyle())
                    .disabled(!goal.amount.isPositive)
                Button("Edit goal") { app.open(.reserve(goal.id, goal: true)) }
                    .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.top, 24)
            Redesign.footnote("Money in a goal stays in its account but isn't counted as safe to spend.").padding(.top, 12)
        }
    }

    /// A new or existing goal, or money set aside
    struct ReserveForm: View {
        let editing: Reserve?
        let asGoal: Bool
        @Environment(AppModel.self) private var app
        @State private var name = ""
        @State private var amount = ""
        @State private var accountId: UUID?
        @State private var hasTarget = false
        @State private var target = ""
        @State private var hasDate = false
        @State private var date = Date()
        @State private var problem: String?
        @State private var confirmRelease = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Field(label: "Name") { TextField(hasTarget ? "e.g. Holiday" : "e.g. Emergency fund", text: $name).accessibilityIdentifier("goalName") }
                AmountBox(label: hasTarget ? "Saved so far, in \(app.currency)" : "Amount set aside, in \(app.currency)", text: $amount,
                          autofocus: false, identifier: "goalSaved")
                AccountChoice(label: "Kept in", selection: $accountId, accounts: app.moneyAccounts)
                ToggleRow(title: "Saving towards a target", isOn: $hasTarget)
                if hasTarget {
                    Field(label: "Target") { TextField("0", text: $target).keyboardType(.decimalPad).accessibilityIdentifier("goalTarget") }
                    ToggleRow(title: "By a date", isOn: $hasDate)
                    if hasDate { Field(label: "Date") { DatePicker("", selection: $date, in: Date()..., displayedComponents: .date).labelsHidden() } }
                }
                Redesign.footnote("It stays in the account, but isn't counted as safe to spend. You can't set aside more than the account holds.")
                Problem(text: problem)
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveGoal")
                if let editing {
                    Button(editing.isGoal ? "Delete goal (keeps the money)" : "Release this money") { confirmRelease = true }
                        .buttonStyle(QuietButtonStyle())
                        .confirmationDialog("Release \(editing.name)?", isPresented: $confirmRelease, titleVisibility: .visible) {
                            Button("Release", role: .destructive) {
                                problem = app.attempt("Released. The money is spendable again.") { try app.store.releaseReserve(editing.id) }
                            }
                        } message: { Text("The money stays in the account and counts as safe to spend again.") }
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    amount = MoneyFormat.editable(editing.amount, emptyWhenZero: true)
                    accountId = editing.accountId
                    hasTarget = editing.target != nil
                    target = editing.target.map { MoneyFormat.editable($0) } ?? ""
                    hasDate = editing.targetDate != nil
                    if let d = editing.targetDate { date = d }
                } else {
                    hasTarget = asGoal
                    accountId = app.moneyAccounts.first { $0.kind == .savings }?.id ?? app.moneyAccounts.first?.id
                }
            }
        }

        private func save() {
            problem = nil
            guard let value = app.parse(amount.isEmpty ? "0" : amount), !value.isNegative else { problem = "Enter an amount."; return }
            guard let accountId else { problem = "Choose the account it's kept in."; return }
            var goalTarget: Money?
            if hasTarget {
                guard let t = app.parse(target), t.isPositive else { problem = "Enter the target."; return }
                goalTarget = t
            }
            let title = name.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { problem = "Give it a name."; return }
            let reserve = Reserve(id: editing?.id ?? UUID(), name: title, amount: value, accountId: accountId, target: goalTarget,
                                  targetDate: hasTarget && hasDate ? app.snapshot.endOfDay(date) : nil)
            problem = app.attempt(hasTarget ? "Goal saved." : "Money set aside.") { try app.store.saveReserve(reserve) }
        }
    }

    struct GoalMoneyForm: View {
        let goal: Reserve
        let adding: Bool
        @Environment(AppModel.self) private var app
        @State private var key = UUID()
        @State private var amount = ""
        @State private var move = false
        @State private var fundingId: UUID?
        @State private var date = Date()
        @State private var problem: String?

        var body: some View {
            let s = app.snapshot
            let free = s.freeToSetAside(in: goal.accountId)
            let bills = s.unpaidBills(from: goal.accountId).map(\.occurrence.remaining).sum(app.currency)
            let afterBills = free - bills
            VStack(alignment: .leading, spacing: 16) {
                AmountBox(label: "Amount in \(app.currency)", text: $amount, identifier: "goalAmount")
                if adding, case .needsPerMonth(let m, _)? = s.progress(of: goal)?.status {
                    Button("Use this month's amount (\(app.money(m)))") { amount = MoneyFormat.editable(m) }
                        .rdText(.captionStrong).foregroundStyle(Theme.primary)
                }
                if adding {
                    Redesign.footnote("\(app.accountLabel(goal.accountId)) has \(app.money(Money.max(free, .zero(app.currency)))) not yet set aside\(bills.isPositive ? ", and \(app.money(bills)) of bills waiting on it." : ".")")
                    if let entered = app.parse(amount), !move, entered > afterBills {
                        Text(private: "That's more than is free after bills (\(app.money(afterBills))). Those bills could come up short.")
                            .rdText(.caption).foregroundStyle(Theme.warm)
                    }
                    ToggleRow(title: "Move it from another account",
                              detail: move ? "Records a transfer into \(app.accountLabel(goal.accountId)) and sets it aside." : "Use this when the money is already there.",
                              isOn: $move)
                    if move {
                        AccountChoice(label: "From", selection: $fundingId, accounts: app.moneyAccounts.filter { $0.id != goal.accountId })
                        Field(label: "Date") { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }
                    }
                } else {
                    Redesign.footnote("\(app.money(goal.amount)) saved. What you take out stays in \(app.accountLabel(goal.accountId)) and becomes spendable.")
                }
                Problem(text: problem)
                Button(adding ? "Add" : "Take out", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("saveGoalMoney")
            }
            .onAppear { fundingId = app.moneyAccounts.first { $0.id != goal.accountId }?.id }
        }

        private func save() {
            guard let value = app.parse(amount), value.isPositive else { problem = "Enter an amount greater than zero."; return }
            if adding && move && fundingId == nil { problem = "Choose the account it comes from."; return }
            problem = app.attempt(adding ? "Added to \(app.hidesDetails ? "your goal" : goal.name)." : "Taken out.") {
                if adding {
                    try app.store.addToGoal(goal.id, amount: value, from: move ? fundingId : nil, date: date, key: key)
                } else {
                    try app.store.takeFromGoal(goal.id, amount: value, key: key)
                }
            }
        }
    }
}
