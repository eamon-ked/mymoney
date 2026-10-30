//
//  GoalViews.swift
//  Nokael Money
//
//  Savings goals: progress towards a target, what to save each month to get
//  there by the date, and adding or taking out money. Saved money is set
//  aside in its account, so it's kept out of safe-to-spend.
//

import SwiftUI
import NokaelCore

extension GoalProgress {
    /// e.g. "Save AED 1,000 a month", "Goal reached"
    var advice: String {
        switch status {
        case .reached: return "Goal reached"
        case .needsPerMonth(let amount, let months):
            return months == 1 ? "Save \(amount.compact) this month" : "Save \(amount.compact) a month"
        case .noDate: return "\(remaining.compact) to go"
        case .pastDue: return "Date passed, \(remaining.compact) to go"
        }
    }

    var tint: Color {
        switch status {
        case .reached: return .green
        case .pastDue: return .orange
        default: return Palette.plan
        }
    }
}

struct GoalRow: View {
    let goal: Reserve
    let progress: GoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListRow(title: goal.name, caption: caption, symbol: progress.status == .reached ? "checkmark.seal.fill" : "target",
                    color: progress.tint) {
                AmountPill(text: "\(Int((progress.fraction * 100).rounded(.down)))%",
                           style: progress.status == .reached ? .positive : .neutral)
            }
            ProgressBar(value: progress.fraction, tint: progress.tint)
                .padding(.leading, 46)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts = ["\(progress.saved.compact) of \(progress.target.compact)"]
        if let date = goal.targetDate { parts.append("by " + date.formatted(.dateTime.month(.abbreviated).year())) }
        parts.append(progress.advice)
        return parts.joined(separator: " · ")
    }
}

enum GoalSheet: String, Identifiable {
    case add, take, edit
    var id: String { rawValue }
}

struct GoalDetailView: View {
    @Environment(LedgerStore.self) private var store
    let goalId: UUID
    @State private var sheet: GoalSheet?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        if let goal = snapshot.reserves.first(where: { $0.id == goalId }), let progress = snapshot.progress(of: goal) {
            content(goal, progress)
        } else {
            ContentUnavailableView("Goal not found", systemImage: "target")
        }
    }

    private func content(_ goal: Reserve, _ progress: GoalProgress) -> some View {
        List {
            Section {
                SummaryBanner(title: goal.name, amount: progress.saved.whole,
                              caption: "saved of \(progress.target.formatted)", tint: progress.tint) {
                    ProgressBar(value: progress.fraction, tint: .white)
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                }
                .bannerRow()
            }

            Section {
                LabeledContent("Still to save", value: progress.remaining.compact)
                if let date = goal.targetDate {
                    LabeledContent("Reach it by", value: date.formatted(date: .long, time: .omitted))
                }
                switch progress.status {
                case .needsPerMonth(let amount, let months):
                    LabeledContent("Each month", value: amount.compact).bold()
                    Text("\(months) \(months == 1 ? "month" : "months") left, counting this one.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .reached:
                    Label("You've reached this goal.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                case .pastDue:
                    Label("The date has passed. Move it or keep saving.", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                case .noDate:
                    Text("Add a date to see how much to save each month.").font(.footnote).foregroundStyle(.secondary)
                }
                LabeledContent("Kept in", value: snapshot.account(goal.accountId)?.name ?? "—")
            }

            Section {
                Button { sheet = .add } label: { Label("Add money", systemImage: "plus.circle.fill") }
                    .bold()
                    .accessibilityIdentifier("addToGoal")
                Button { sheet = .take } label: { Label("Take money out", systemImage: "minus.circle") }
                    .disabled(!progress.saved.isPositive)
                Button("Edit goal") { sheet = .edit }
            } footer: {
                Text("Saved money stays in \(snapshot.account(goal.accountId)?.name ?? "its account") and is kept out of safe-to-spend. Taking it out makes it spendable again.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .add: GoalMoneySheet(goal: goal, adding: true)
            case .take: GoalMoneySheet(goal: goal, adding: false)
            case .edit: ReserveEditor(editing: goal)
            }
        }
    }
}

/// Adds to or takes from a goal
struct GoalMoneySheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: Reserve
    let adding: Bool

    @State private var key = UUID()
    @State private var amountText = ""
    @State private var moveMoney = false
    @State private var fundingId: UUID?
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        let snapshot = store.snapshot
        let home = snapshot.account(goal.accountId)
        let free = snapshot.freeToSetAside(in: goal.accountId)
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("goalAmount")
                    }
                    if adding, let progress = snapshot.progress(of: goal), case let .needsPerMonth(amount, _) = progress.status {
                        Button("Use this month's amount (\(amount.compact))") { amountText = MoneyFormat.editable(amount) }
                            .font(.subheadline)
                    }
                } footer: {
                    if adding && !moveMoney {
                        let bills = snapshot.unpaidBills(from: goal.accountId)
                        let billsTotal = bills.map(\.occurrence.remaining).sum(store.currency)
                        let afterBills = Money.max(free - billsTotal, .zero(store.currency))
                        VStack(alignment: .leading, spacing: 6) {
                            if billsTotal.isPositive {
                                Text("\(afterBills.compact) is free to save. \(home?.name ?? "The account") has \(Money.max(free, .zero(store.currency)).compact), but \(billsTotal.compact) of it is for bills not paid yet:")
                                ForEach(bills, id: \.occurrence.id) { bill in
                                    Text("• \(bill.item.name), \(bill.occurrence.remaining.compact), due \(bill.occurrence.dueDate.formatted(.dateTime.day().month()))")
                                }
                            } else {
                                Text("\(home?.name ?? "The account") has \(Money.max(free, .zero(store.currency)).compact) not yet set aside, and no bills waiting on it before payday.")
                            }
                            if let entered = MoneyFormat.parse(amountText, currency: store.currency), entered > afterBills {
                                Text("That's more than is free after bills (\(afterBills.compact)). Those bills could come up short.")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else if !adding {
                        Text("\(goal.amount.compact) saved. What you take out stays in \(home?.name ?? "the account") and becomes spendable.")
                    }
                }
                if adding {
                    Section {
                        Toggle("Move it from another account", isOn: $moveMoney)
                        if moveMoney {
                            AccountPicker(title: "From",
                                          accounts: snapshot.accounts.filter { $0.kind.holdsMoney && $0.id != goal.accountId },
                                          selection: $fundingId)
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        }
                    } footer: {
                        Text(moveMoney
                             ? "Records a transfer into \(home?.name ?? "the goal's account") and sets it aside for \(goal.name)."
                             : "Use this when the money is already in \(home?.name ?? "the goal's account").")
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(adding ? "Add to \(goal.name)" : "Take from \(goal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(adding ? "Add" : "Take out", action: save).accessibilityIdentifier("saveGoalMoney")
                }
            }
            .onAppear {
                fundingId = snapshot.accounts.first { $0.spendable && $0.id != goal.accountId }?.id
            }
        }
    }

    private func save() {
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency), amount.isPositive else {
            error = "Enter an amount greater than zero."; return
        }
        if adding && moveMoney && fundingId == nil { error = "Choose the account it comes from."; return }
        do {
            if adding {
                try store.addToGoal(goal.id, amount: amount, from: moveMoney ? fundingId : nil, date: date, key: key)
            } else {
                try store.takeFromGoal(goal.id, amount: amount, key: key)
            }
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
