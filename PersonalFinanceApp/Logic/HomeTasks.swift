//
//  HomeTasks.swift
//  Nokael Money
//
//  Everything that needs the person, in one list, most urgent first. Home
//  shows the top few, each with one button, under Safe to spend.
//

import Foundation
import NokaelCore

enum HomeTask: Identifiable {
    /// Overdue, due today or part paid, with no payment recorded
    case bill(Occurrence)
    /// A payment already recorded that looks like an unpaid bill
    case billLink(BillSuggestion)
    case payday(PlannedItem, Occurrence)
    /// Spent more than the category's budget
    case overspent(LedgerAccountRecord, by: Money)
    /// Spending in categories that have no budget this month, most spent first
    case noBudget([LedgerAccountRecord], total: Money)
    /// Entries saved from Apple Pay, bank messages or Siri, still to check
    case review(count: Int)
    /// Budget money with no job yet, or planned beyond what there is when negative
    case unplanned(Money)
    /// Money with a person that's past its pay-back date, or owed to you untouched for a month.
    /// `balance` is theirs: positive when they owe you, negative when you owe them
    case person(LedgerAccountRecord, balance: Money, due: Date?)
    case stale(LedgerAccountRecord)
    case backup(neverSaved: Bool)
    /// Pay, a loan or a bill an imported statement showed, to set up with one tap
    case finding(StatementFinding)
    /// The rest of the picture, after setup let the person straight into Home
    case setUp(SetUpStep)

    enum SetUpStep: String {
        case payday, bills
    }

    var id: String {
        switch self {
        case .bill(let o): "bill-\(o.id)"
        case .billLink(let s): "link-\(s.id)"
        case .payday(_, let o): "payday-\(o.id)"
        case .overspent(let c, _): "over-\(c.id)"
        case .noBudget: "noBudget"
        case .review: "review"
        case .unplanned: "unplanned"
        case .person(let p, _, _): "person-\(p.id)"
        case .stale(let a): "stale-\(a.id)"
        case .backup: "backup"
        case .finding(let f): "finding-\(f.id)"
        case .setUp(let step): "setUp-\(step.rawValue)"
        }
    }

    /// In order: money already late, then today, then what's quick to settle, then housekeeping
    @MainActor static func all(_ snapshot: FinanceSnapshot) -> [HomeTask] {
        var tasks: [HomeTask] = []
        let suggestions = snapshot.billSuggestions
        let suggested = Set(suggestions.map(\.occurrence.id))
        let bills = snapshot.upcomingBills(days: 1).filter { !suggested.contains($0.id) }
        tasks += bills.filter { snapshot.state(of: $0) == .overdue }.map(HomeTask.bill)
        tasks += bills.filter { [.dueToday, .partiallyPaid].contains(snapshot.state(of: $0)) }.map(HomeTask.bill)
        tasks += suggestions.map(HomeTask.billLink)

        // Filling in the picture: what a statement showed first, then what's still missing
        let findings = snapshot.statementFindings
        tasks += findings.map(HomeTask.finding)

        if snapshot.setupComplete, let due = PaydayPlan.dueSalary(snapshot) { tasks.append(.payday(due.item, due.occurrence)) }

        let month = snapshot.monthKey
        let lines = snapshot.expenseCategories.map { ($0, snapshot.budget.line($0.id, month: month)) }
        for (c, line) in lines where line.isOverBudget { tasks.append(.overspent(c, by: line.remaining.magnitude)) }
        let unbudgeted = lines.filter { $0.1.isUnbudgetedSpending }.sorted { $0.1.spent > $1.1.spent }
        if !unbudgeted.isEmpty {
            tasks.append(.noBudget(unbudgeted.map(\.0), total: unbudgeted.map(\.1.spent).sum(snapshot.currency)))
        }

        let waiting = snapshot.entries().filter(\.needsReview).count
        if waiting > 0 { tasks.append(.review(count: waiting)) }

        if snapshot.setupComplete && !snapshot.expenseCategories.isEmpty {
            let unplanned = snapshot.budget.availableToAllocate(month: month)
            if !unplanned.isZero { tasks.append(.unplanned(unplanned)) }
        }

        tasks += people(snapshot)

        tasks += snapshot.accounts.filter { a in
            guard a.kind.defaultSpendable || a.spendable else { return false }
            guard let d = snapshot.lastConfirmed[a.id] else { return true }
            return (snapshot.calendar.dateComponents([.day], from: d, to: snapshot.today).day ?? 0) > snapshot.settings.staleAfterDays
        }.map(HomeTask.stale)

        if needsBackup(snapshot) { tasks.append(.backup(neverSaved: snapshot.settings.lastBackupAt == nil)) }

        // Last: what's still missing from the picture, until it's added or turned down
        let skipped = Set(snapshot.settings.dismissedFindings)
        if snapshot.hasAccounts, snapshot.nextIncomeDate == nil, !findings.contains(where: { $0.kind == .pay }),
           !skipped.contains("setUp-payday") {
            tasks.append(.setUp(.payday))
        }
        if snapshot.hasAccounts, !snapshot.items.contains(where: { $0.direction == .outflow }),
           !findings.contains(where: { $0.kind != .pay }), !skipped.contains("setUp-bills") {
            tasks.append(.setUp(.bills))
        }
        return tasks
    }

    /// Days without movement before money someone owes you gets a nudge
    static let quietDays = 30

    @MainActor static func people(_ snapshot: FinanceSnapshot) -> [HomeTask] {
        snapshot.accounts.filter { $0.kind == .lent && !$0.archived }.compactMap { p in
            let balance = snapshot.balance(p.id)
            guard !balance.isZero else { return nil }
            if let due = p.owedBackBy {
                return snapshot.calendar.startOfDay(for: due) < snapshot.calendar.startOfDay(for: snapshot.today)
                    ? .person(p, balance: balance, due: due) : nil
            }
            // The empty opening entry a new person gets isn't a movement
            let last = snapshot.entryRecords.first {
                $0.status == .posted && $0.kind != .openingBalance && $0.lines.contains { $0.accountId == p.id }
            }?.date
            guard balance.isPositive, let last,
                  (snapshot.calendar.dateComponents([.day], from: last, to: snapshot.today).day ?? 0) > quietDays else { return nil }
            return .person(p, balance: balance, due: nil)
        }
    }

    /// Once there's real data, remind until a backup is saved, then monthly
    @MainActor static func needsBackup(_ snapshot: FinanceSnapshot) -> Bool {
        guard snapshot.entries().count >= 5 else { return false }
        guard let last = snapshot.settings.lastBackupAt else { return true }
        return (snapshot.calendar.dateComponents([.day], from: last, to: snapshot.today).day ?? 0) > 30
    }
}
