//
//  Payday.swift
//  Nokael Money
//
//  "I received my salary" uses what the person already told us: the salary in
//  their plan (amount, account, category) and the rest of their setup. Payday
//  records it against the expected occurrence, then does the month's routine:
//  plan the budget like last month and put each goal's monthly amount aside.
//

import Foundation
import NokaelCore

@MainActor
struct PaydayPlan {
    struct GoalStep: Identifiable, Hashable {
        let id: UUID
        let name: String
        let amount: Money
        let by: Date?
    }

    /// The salary in Plan, if there is one
    let item: PlannedItem?
    /// The expected payment this salary settles
    let occurrence: Occurrence?
    /// This period's salary was already recorded
    let alreadyReceived: Date?
    var amount: Money
    var accountId: UUID?
    var categoryId: UUID?
    /// Last month's budget, ready to copy into this one
    let budgetFrom: String?
    let budgetTotal: Money
    let budgetCount: Int
    let goals: [GoalStep]
    let nextPayday: Date?
    let billsBeforeNext: Money

    static let salaryWords = ["salary", "payday", "pay day", "got paid", "paycheck", "pay cheque", "wage", "wages"]

    static func mentionsSalary(_ text: String) -> Bool {
        let lower = text.lowercased()
        return salaryWords.contains(where: lower.contains)
    }

    /// The person's salary: an expected income called Salary, else their largest regular income
    static func salaryItem(_ snapshot: FinanceSnapshot) -> PlannedItem? {
        let income = snapshot.items.filter { $0.direction == .inflow }
        return income.first { mentionsSalary($0.name) } ?? income.max { $0.amount < $1.amount }
    }

    /// The salary payment due around today and not yet recorded, for Home's reminder
    static func dueSalary(_ snapshot: FinanceSnapshot) -> (item: PlannedItem, occurrence: Occurrence)? {
        guard let item = salaryItem(snapshot) else { return nil }
        let soon = snapshot.calendar.date(byAdding: .day, value: 1, to: snapshot.today) ?? snapshot.today
        let occ = snapshot.occurrences
            .filter { $0.itemId == item.id && !$0.skipped && $0.remaining.isPositive && $0.dueDate <= soon }
            .max { $0.dueDate < $1.dueDate }
        return occ.map { (item, $0) }
    }

    static func make(_ snapshot: FinanceSnapshot, said: Money? = nil) -> PaydayPlan {
        let cal = snapshot.calendar
        let today = snapshot.today
        let item = salaryItem(snapshot)
        let window = (cal.date(byAdding: .day, value: -20, to: today) ?? today)...(cal.date(byAdding: .day, value: 12, to: today) ?? today)
        let mine = snapshot.occurrences.filter { $0.itemId == item?.id && !$0.skipped && window.contains($0.dueDate) }
        let open = mine.filter { $0.remaining.isPositive }
            .min { abs($0.dueDate.timeIntervalSince(today)) < abs($1.dueDate.timeIntervalSince(today)) }
        let received: Date? = open == nil
            ? mine.filter { !$0.remaining.isPositive }.compactMap { occ in
                snapshot.entryRecords.first { $0.occurrenceId == occ.id && $0.status == .posted }?.date ?? occ.dueDate
            }.max()
            : nil

        let amount = said ?? open?.remaining ?? item?.amount ?? .zero(snapshot.currency)
        let accountId = item?.accountId ?? snapshot.accounts.first(where: \.spendable)?.id
        let categoryId = item?.categoryId ?? snapshot.incomeCategories.first { mentionsSalary($0.name) }?.id
            ?? snapshot.incomeCategories.first?.id

        // The month's budget: only when nothing is planned yet and last month was
        let month = snapshot.monthKey
        let previous = BudgetMonth.adding(-1, to: month, calendar: cal)
        let copies = snapshot.budget.allocationProgress(month: month).allocated.isZero
            ? snapshot.budget.copyPlan(from: previous, to: month) : []

        let goals: [GoalStep] = snapshot.goals.compactMap { goal in
            guard let progress = snapshot.progress(of: goal), case .needsPerMonth(let monthly, _) = progress.status else { return nil }
            return GoalStep(id: goal.id, name: goal.name, amount: monthly, by: goal.targetDate)
        }

        let current = open?.dueDate ?? today
        let next = snapshot.occurrences.filter { $0.itemId == item?.id && !$0.skipped && $0.dueDate > current }.map(\.dueDate).min()
        let bills = snapshot.occurrences.filter { occ in
            guard let it = snapshot.item(for: occ), it.direction == .outflow, !occ.skipped else { return false }
            return occ.dueDate >= cal.startOfDay(for: today) && (next.map { occ.dueDate < $0 } ?? true)
        }.map(\.remaining).sum(snapshot.currency)

        return PaydayPlan(item: item, occurrence: open, alreadyReceived: received, amount: amount,
                          accountId: accountId, categoryId: categoryId,
                          budgetFrom: copies.isEmpty ? nil : previous,
                          budgetTotal: copies.map(\.amount).sum(snapshot.currency), budgetCount: copies.count,
                          goals: goals, nextPayday: next, billsBeforeNext: bills)
    }

    struct Choices {
        var copyBudget = true
        var goals: Set<UUID> = []
        /// With no salary in Plan yet: remember this one, monthly from today
        var remember = true
    }

    /// Does it all; returns one line per thing done
    func run(_ store: LedgerStore, choices: Choices, date: Date, key: UUID) throws -> [String] {
        guard amount.isPositive else { throw StoreError.invalid("Enter the salary you received.") }
        guard let accountId, let account = store.snapshot.account(accountId) else { throw StoreError.invalid("Choose the account it was paid into.") }
        var done: [String] = []

        if let occurrence {
            try store.pay(occurrenceId: occurrence.id, amount: amount, accountId: accountId, categoryId: categoryId, date: date, key: key)
        } else {
            guard let category = store.snapshot.account(categoryId) else { throw StoreError.invalid("Add an income category first.") }
            try store.post(try EntryFactory.income(amount, to: account.info, category: category.info, date: date,
                                                   memo: item?.name ?? "Salary", key: key))
            if item == nil && choices.remember, let next = store.calendar.date(byAdding: .month, value: 1, to: date) {
                try store.savePlannedItem(PlannedItem(name: "Salary", direction: .inflow, amount: amount,
                                                      schedule: Schedule(start: next, frequency: .monthly(every: 1)),
                                                      accountId: accountId, categoryId: categoryId))
                done.append("Saved your salary, so next month's is expected")
            }
        }
        done.insert("Recorded \(MoneyFormat.string(amount, dropWholeFraction: true)) salary into \(account.name)", at: 0)

        if choices.copyBudget, let from = budgetFrom {
            try store.copyPlan(from: from, to: store.snapshot.monthKey)
            done.append("Planned this month's budget like last month (\(budgetTotal.compact))")
        }
        for goal in goals where choices.goals.contains(goal.id) {
            do {
                try store.addToGoal(goal.id, amount: goal.amount, from: accountId, date: date, key: UUID())
                done.append("Put \(goal.amount.compact) into \(goal.name)")
            } catch {
                done.append("Couldn't add to \(goal.name): \(StoreError.from(error).errorDescription ?? "")")
            }
        }
        return done
    }
}
