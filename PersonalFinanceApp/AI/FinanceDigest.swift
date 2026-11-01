//
//  FinanceDigest.swift
//  Nokael Money
//
//  A plain-text, Sendable copy of the numbers Apple Intelligence may read.
//  Built from one FinanceSnapshot on the main actor, so the model sees exactly
//  what the screens show. Nothing here leaves the device.
//

import Foundation
import NokaelCore

struct FinanceDigest: Sendable {
    struct Account: Sendable {
        let name: String
        let kind: String
        let balance: String
        let spendable: Bool
    }

    struct Category: Sendable {
        let name: String
        let group: String
        let planned: String
        let spent: String
        let spentMinor: Int64
        let remaining: String
        let overBy: String
        let overspent: Bool
        let used: Bool
        /// Loan instalments, not spending to cut back on
        var loans: [String] = []
    }

    struct Transaction: Sendable {
        let date: Date
        let memo: String
        let kind: String
        let category: String?
        let account: String?
        let amount: Money
    }

    struct Month: Sendable {
        let key: String
        let title: String
        let income: String
        let spending: String
        let leftOver: String
        let topCategories: [(name: String, amount: String)]
    }

    struct Bill: Sendable {
        let name: String
        let due: Date
        let amount: String
        let overdue: Bool
        let estimated: Bool
    }

    let currency: String
    let today: Date
    let monthKey: String
    let safeToSpend: String
    let safeToSpendThrough: Date
    let cashAndBank: String
    let totalDebt: String
    let netWorth: String
    let accounts: [Account]
    let categories: [Category]
    let spentThisMonth: String
    let plannedThisMonth: String
    let incomeCategoryNames: [String]
    let transactions: [Transaction]
    let months: [Month]
    let bills: [Bill]
    let goals: [String]
    /// Salary and other expected income from Plan, with this period's status
    let expectedIncome: [String]
    /// Regular bills from Plan, how often and how much
    let plannedBills: [String]
    /// Cards and loans: owed, rate, monthly payment
    let debts: [String]

    @MainActor
    init(_ snapshot: FinanceSnapshot) {
        let calendar = snapshot.calendar
        currency = snapshot.currency
        today = snapshot.today
        monthKey = snapshot.monthKey

        let sts = snapshot.safeToSpend()
        safeToSpend = snapshot.setupComplete ? (sts.amount?.compact ?? "unknown") : "not set up yet"
        safeToSpendThrough = sts.periodEnd
        cashAndBank = snapshot.cashAndBank.compact
        totalDebt = snapshot.totalDebt.compact
        let worth = snapshot.netWorth
        netWorth = (worth.assets - worth.liabilities).compact

        accounts = snapshot.accounts.map {
            Account(name: $0.name, kind: Redesign.kindName($0.kind),
                    balance: snapshot.balance($0.id).compact, spendable: $0.spendable)
        }

        let month = snapshot.monthKey
        let lines = snapshot.expenseCategories.map { ($0, snapshot.budget.line($0.id, month: month)) }
        categories = lines.map { c, line in
            let planned = line.planned
            return Category(name: c.name, group: c.group, planned: planned.compact,
                            spent: line.spent.compact, spentMinor: line.spent.minorUnits, remaining: line.remaining.compact,
                            overBy: line.remaining.magnitude.compact, overspent: line.isOverspent, used: !planned.isZero || !line.spent.isZero,
                            loans: snapshot.loans(in: c.id).map(\.name))
        }
        .sorted { $0.spentMinor > $1.spentMinor }
        spentThisMonth = lines.map { $0.1.spent }.sum(snapshot.currency).compact
        plannedThisMonth = lines.map { $0.1.planned }.sum(snapshot.currency).compact
        incomeCategoryNames = snapshot.incomeCategories.map(\.name)

        transactions = snapshot.entries().prefix(400).map { record in
            let lines = record.lines
            let category = lines.lazy.compactMap { snapshot.account($0.accountId) }.first { $0.kind.isCategory }
            let sheet = lines.filter { snapshot.account($0.accountId)?.kind.isBalanceSheet == true }
            let amount = lines.map { Money(minorUnits: $0.minorUnits, currency: $0.currency) }
                .filter(\.isPositive).sum(snapshot.currency)
            return Transaction(date: record.date, memo: record.memo, kind: record.kind.rawValue,
                               category: category?.name,
                               account: sheet.first.flatMap { snapshot.account($0.accountId)?.name },
                               amount: amount)
        }

        let expense = snapshot.spendingCategoryInfos
        let income = snapshot.earningCategoryInfos
        months = (0..<6).map { back in
            let key = BudgetMonth.adding(-back, to: month, calendar: calendar)
            let report = Reports.month(key, ledger: snapshot.ledger, expenseCategories: expense,
                                       incomeCategories: income, calendar: calendar, loanCategories: snapshot.loanCategories)
            let title = BudgetMonth.start(of: key, calendar: calendar)?
                .formatted(.dateTime.month(.wide).year()) ?? key
            return Month(key: key, title: title, income: report.totals.income.compact,
                         spending: report.totals.spending.compact, leftOver: report.totals.leftOver.compact,
                         topCategories: report.spending.prefix(5).map { ($0.name, $0.amount.compact) })
        }

        bills = snapshot.upcomingBills(days: 45).map { occ in
            Bill(name: snapshot.item(for: occ)?.name ?? "Bill", due: occ.dueDate, amount: occ.remaining.compact,
                 overdue: snapshot.state(of: occ) == .overdue, estimated: snapshot.item(for: occ)?.isEstimate ?? false)
        }

        func next(_ item: PlannedItem) -> String {
            let open = snapshot.occurrences.filter { $0.itemId == item.id && !$0.skipped && $0.remaining.isPositive }.min { $0.dueDate < $1.dueDate }
            return open.map { "next expected \($0.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))" } ?? "nothing pending"
        }
        let payday = PaydayPlan.make(snapshot)
        expectedIncome = snapshot.items.filter { $0.direction == .inflow }.map { item in
            var line = "\(item.name): \(item.amount.compact), \(item.schedule.frequency.label.lowercased())"
            if let account = snapshot.account(item.accountId) { line += ", paid into \(account.name)" }
            line += ", \(next(item))"
            if item.id == payday.item?.id, let received = payday.alreadyReceived {
                line += "; this month's was received \(received.formatted(.dateTime.day().month(.abbreviated)))"
            }
            return line
        }
        plannedBills = snapshot.items.filter { $0.direction == .outflow }.map { item in
            "\(item.name): \(item.amount.compact)\(item.isEstimate ? " (estimate)" : ""), \(item.schedule.frequency.label.lowercased()), \(next(item))"
        }
        debts = snapshot.debts.map { debt in
            var line = "\(debt.name) (\(Redesign.kindName(debt.kind))): owe \(snapshot.owed(debt.id).compact)"
            if let terms = debt.debtTerms { line += ", interest \(terms.rateText), monthly payment \(terms.monthlyPayment.compact)" }
            switch snapshot.payoff(for: debt) {
            case .paidOff(_, let last, let interest, _)?:
                line += ", paid off by \(last.formatted(.dateTime.month(.wide).year())) with \(interest.compact) more interest"
            case .never?:
                line += ", the payment doesn't cover the interest so it never falls"
            default: break
            }
            return line
        }

        goals = snapshot.reserves.map { r in
            if let target = r.target { return "\(r.name): \(r.amount.compact) saved of \(target.compact)" }
            return "\(r.name): \(r.amount.compact) set aside"
        }
    }

    // MARK: - Text the model reads

    func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()) }

    var overview: String {
        var out = """
        Today: \(day(today)). Currency: \(currency).
        Safe to spend (flexible spending through \(day(safeToSpendThrough)), after bills, savings and budget reservations): \(safeToSpend)
        Cash & bank: \(cashAndBank). Total debt: \(totalDebt). Net worth (what they own minus what they owe; there is no net worth target): \(netWorth).
        Accounts:
        """
        for a in accounts { out += "\n- \(a.name) (\(a.kind)\(a.spendable ? ", spendable" : "")): \(a.balance)" }
        if accounts.isEmpty { out += "\n- none yet" }
        if !goals.isEmpty { out += "\nSavings goals and set-aside money:\n" + goals.map { "- \($0)" }.joined(separator: "\n") }
        out += "\nExpected income (the person's salary and other regular income, from their plan):"
        out += expectedIncome.isEmpty ? "\n- none set up" : "\n" + expectedIncome.map { "- \($0)" }.joined(separator: "\n")
        if !plannedBills.isEmpty { out += "\nRegular bills:\n" + plannedBills.map { "- \($0)" }.joined(separator: "\n") }
        if !debts.isEmpty { out += "\nCards and loans:\n" + debts.map { "- \($0)" }.joined(separator: "\n") }
        return out
    }

    func budget(monthKey key: String?) -> String {
        if let key, key != monthKey { return monthSummary(key) }
        let used = categories.filter(\.used)
        guard !used.isEmpty else { return "Nothing planned or spent this month yet." }
        let spentOn = used.filter { $0.spentMinor > 0 }
        var out = "This month so far: spent \(spentThisMonth) in total, against \(plannedThisMonth) planned.\n"
        out += spentOn.isEmpty ? "Nothing spent yet.\n"
            : "Actually spent, largest first: " + spentOn.map { "\($0.name) \($0.spent)" }.joined(separator: ", ") + ".\n"
        let over = used.filter(\.overspent)
        out += over.isEmpty ? "No category is over budget.\n"
            : "Over budget: " + over.map { "\($0.name) is over by \($0.overBy) (spent \($0.spent), planned \($0.planned))" }.joined(separator: ", ") + ".\n"
        out += "Each category:\n" + used.map {
            "- \($0.name): spent \($0.spent) of \($0.planned) planned, \($0.remaining) left"
        }.joined(separator: "\n")
        for c in used where !c.loans.isEmpty {
            out += "\n\(c.name) holds fixed loan instalments (interest plus repaying the loan) for \(c.loans.joined(separator: ", ")), not spending to cut back on."
        }
        return out
    }

    func monthSummary(_ key: String) -> String {
        guard let m = months.first(where: { $0.key == key }) else { return "No figures for \(key); only the last six months are available." }
        return "\(m.title): income \(m.income), spending \(m.spending), left over \(m.leftOver). Top spending: "
            + (m.topCategories.isEmpty ? "nothing" : m.topCategories.map { "\($0.name) \($0.amount)" }.joined(separator: ", "))
    }

    var trend: String {
        "Last 6 months, newest first:\n" + months.map {
            "- \($0.title): income \($0.income), spending \($0.spending), left over \($0.leftOver). Top: "
                + ($0.topCategories.isEmpty ? "nothing" : $0.topCategories.map { "\($0.name) \($0.amount)" }.joined(separator: ", "))
        }.joined(separator: "\n")
    }

    var billsText: String {
        guard !bills.isEmpty else { return "No unpaid bills in the next 45 days." }
        let overdue = bills.filter(\.overdue).count
        return (overdue == 0 ? "No bills are overdue. " : "\(overdue) bill(s) overdue, marked OVERDUE. ")
            + "Unpaid bills coming up in the next 45 days (planned, not yet spent):\n" + bills.map {
            "- \($0.name): \($0.amount) due \(day($0.due))\($0.overdue ? " (OVERDUE)" : "")\($0.estimated ? " (estimate)" : "")"
        }.joined(separator: "\n")
    }

    /// Everything, for Apple's larger cloud model (32K tokens): the whole picture, three months of
    /// transactions and how the app works, so it can answer like someone who knows both.
    /// Kept to about 80,000 characters (around 20K tokens), leaving room for the question and answer.
    var fullContext: String {
        let parts = [
            overview,
            budget(monthKey: nil),
            billsText,
            trend,
            "Transactions in the last 90 days:\n" + search(text: nil, category: nil, days: 90, limit: 300),
            "How the Nokael Money app works (use these exact button names when explaining):\n" + AppGuide.reference,
        ]
        let text = parts.joined(separator: "\n\n")
        return text.count <= Self.fullContextBudget ? text : String(text.prefix(Self.fullContextBudget))
    }

    static let fullContextBudget = 80_000

    /// Matching transactions, newest first, with a total
    func search(text: String?, category: String?, days: Int?, limit: Int = 25) -> String {
        let since = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
        let needle = text?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let cat = category?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        func matches(_ t: Transaction, _ word: String) -> Bool {
            t.memo.lowercased().contains(word) || (t.category?.lowercased().contains(word) ?? false)
        }
        let recent = transactions.filter { t in since.map { t.date >= $0 } ?? true }
        var hits = recent.filter { t in
            (needle.isEmpty || matches(t, needle)) && (cat.isEmpty || (t.category?.lowercased().contains(cat) ?? false))
        }
        // The model often puts the same word in both fields, or a category name that's only in
        // the description; match either rather than answer that there's nothing
        if hits.isEmpty, !needle.isEmpty || !cat.isEmpty {
            hits = recent.filter { t in (!needle.isEmpty && matches(t, needle)) || (!cat.isEmpty && matches(t, cat)) }
        }
        guard !hits.isEmpty else { return "No matching transactions." }
        let spent = hits.filter { $0.kind == "expense" || $0.kind == "debtPayment" }.map(\.amount).sum(currency)
        let received = hits.filter { $0.kind == "income" }.map(\.amount).sum(currency)
        var out = "\(hits.count) matching transactions. Total spent: \(spent.compact). Total received: \(received.compact).\n"
        out += hits.prefix(limit).map {
            "- \(day($0.date)): \($0.memo), \($0.kind)\($0.category.map { ", \($0)" } ?? "")\($0.account.map { ", \($0)" } ?? ""): \($0.amount.compact)"
        }.joined(separator: "\n")
        if hits.count > limit { out += "\n(\(hits.count - limit) older ones not listed)" }
        return out
    }
}
