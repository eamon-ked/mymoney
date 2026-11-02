//
//  FinanceSnapshot.swift
//  Nokael Money
//
//  An immutable picture of everything at one revision, converted to NokaelCore
//  types. Every number on screen comes from here, so all screens agree.
//

import Foundation
import NokaelCore

@MainActor
struct FinanceSnapshot {
    let currency: String
    let calendar: Calendar
    let today: Date
    let settings: SettingsRecord

    let accountRecords: [LedgerAccountRecord]
    let entryRecords: [EntryRecord]
    let ledger: Ledger
    let budget: Budget
    let items: [PlannedItem]
    let itemRecords: [UUID: PlannedItemRecord]
    let occurrences: [Occurrence]
    let reserves: [Reserve]
    /// The spending category each loan's payments count under (loan id to category id)
    let loanCategories: [UUID: UUID]

    init(store: LedgerStore) {
        let settings = store.settings
        self.settings = settings
        self.currency = settings.currency
        self.calendar = store.calendar
        self.today = store.now()

        let accounts = store.fetch(LedgerAccountRecord.self).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        self.accountRecords = accounts
        let entries = store.fetch(EntryRecord.self).sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        self.entryRecords = entries
        let ledger = Ledger(accounts: accounts.map(\.info), entries: entries.map(\.entry), currency: settings.currency)
        self.ledger = ledger

        // Money sent to people isn't something to budget for, so it isn't planned or counted as unplanned
        let categories = accounts.filter { $0.kind == .expense && !$0.archived && !$0.isTransferCategory }
            .map { BudgetCategory(id: $0.id, name: $0.name, group: $0.group, policy: $0.policy) }
        let reserves = store.fetch(ReserveRecord.self).filter { !$0.archived }.map(\.reserve)
        let budgetAccounts = Set(accounts.filter { $0.kind.isBalanceSheet && $0.onBudget }.map(\.id))
        let itemRecords = store.fetch(PlannedItemRecord.self).filter { !$0.archived }
        self.itemRecords = Dictionary(itemRecords.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.items = itemRecords.map(\.item)
        let itemIds = Set(itemRecords.map(\.id))
        let occurrences = store.fetch(OccurrenceRecord.self).map(\.occurrence)
            .filter { itemIds.contains($0.itemId) }
            .sorted { $0.dueDate < $1.dueDate }
        self.occurrences = occurrences

        // Each loan counts under the category it names, or Loan payments
        let expenseIds = Set(accounts.filter { $0.kind == .expense && !$0.archived }.map(\.id))
        let loanPayments = Self.systemCategory("loanPayments", name: "Loan payments", in: accounts)?.id
        let loanCategories = Dictionary(accounts.filter { $0.kind == .loan }.compactMap { loan -> (UUID, UUID)? in
            guard let category = loan.debtCategoryId.flatMap({ expenseIds.contains($0) ? $0 : nil }) ?? loanPayments else { return nil }
            return (loan.id, category)
        }, uniquingKeysWith: { a, _ in a })
        self.loanCategories = loanCategories

        // Bills count as planned in their category. A loan's goes to its loan's category; a card's
        // payment covers purchases already counted, so it isn't planned again.
        let kinds = Dictionary(accounts.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let billItems = Dictionary(itemRecords.map(\.item).filter { $0.direction == .outflow }.map { ($0.id, $0) },
                                   uniquingKeysWith: { a, _ in a })
        let bills = occurrences.compactMap { occ -> BudgetBill? in
            guard let item = billItems[occ.itemId], !occ.skipped else { return nil }
            let loan = item.debtId.flatMap { kinds[$0] } == .loan
            if item.debtId != nil && !loan { return nil }
            guard let category = loan ? item.debtId.flatMap({ loanCategories[$0] }) : item.categoryId else { return nil }
            return BudgetBill(categoryId: category, month: BudgetMonth.key(for: occ.dueDate, calendar: store.calendar),
                              amount: Money.max(occ.expected, occ.paid), unpaid: occ.remaining)
        }
        self.budget = Budget(ledger: ledger, categories: categories,
                             allocations: store.fetch(AllocationRecord.self).map(\.allocation), calendar: store.calendar,
                             saved: reserves.filter { budgetAccounts.contains($0.accountId) }.map(\.amount).sum(settings.currency),
                             bills: bills, loanCategories: loanCategories)
        self.reserves = reserves
    }

    /// A built-in category by its role, or by name in stores from before roles
    static func systemCategory(_ role: String, name: String, in accounts: [LedgerAccountRecord]) -> LedgerAccountRecord? {
        let expenses = accounts.filter { $0.kind == .expense && !$0.archived }
        return expenses.first { $0.systemRole == role } ?? expenses.first { $0.systemRole == nil && $0.name == name }
    }

    /// Whether a category holds loan payments (Loan payments, or one a loan was put in)
    func holdsLoans(_ categoryId: UUID) -> Bool {
        loanCategories.values.contains(categoryId)
            || Self.systemCategory("loanPayments", name: "Loan payments", in: accountRecords)?.id == categoryId
    }

    /// Loans whose payments count under a category
    func loans(in categoryId: UUID) -> [LedgerAccountRecord] {
        accountRecords.filter { $0.kind == .loan && !$0.archived && loanCategories[$0.id] == categoryId }
    }

    // MARK: - Lookups

    func account(_ id: UUID?) -> LedgerAccountRecord? {
        guard let id else { return nil }
        return accountRecords.first { $0.id == id }
    }

    /// Real accounts the person sees (not categories or the system equity account)
    var accounts: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind.isBalanceSheet && !$0.archived }
    }

    var archivedAccounts: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind.isBalanceSheet && $0.archived }
    }

    /// What an imported statement suggested setting up, still to confirm: pay only while there's no
    /// income planned, a loan or bill only while nothing of that amount is planned
    var statementFindings: [StatementFinding] {
        guard let data = settings.statementFindingsData,
              let all = try? JSONDecoder().decode([StatementFinding].self, from: data) else { return [] }
        let planned = Set(items.filter { $0.direction == .outflow }.map(\.amount))
        return all.filter { f in
            switch f.kind {
            case .pay: return nextIncomeDate == nil
            case .loan, .bill: return !planned.contains(f.amount)
            }
        }
    }

    /// Spending categories the totals count: not money sent to people
    var spendingCategoryInfos: [AccountInfo] {
        accountRecords.filter { $0.kind == .expense && !$0.isTransferCategory }.map(\.info)
    }

    /// Income categories the totals count: not money from people
    var earningCategoryInfos: [AccountInfo] {
        accountRecords.filter { $0.kind == .income && !$0.isTransferCategory }.map(\.info)
    }

    /// Money to and from people, shown on its own line
    var peopleCategoryInfos: (sent: [AccountInfo], received: [AccountInfo]) {
        let people = accountRecords.filter(\.isTransferCategory)
        return (people.filter { $0.kind == .expense }.map(\.info), people.filter { $0.kind == .income }.map(\.info))
    }

    var expenseCategories: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind == .expense && !$0.archived }
    }

    /// Spending categories the budget plans: not money sent to people
    var budgetCategories: [LedgerAccountRecord] {
        expenseCategories.filter { !$0.isTransferCategory }
    }

    var incomeCategories: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind == .income && !$0.archived }
    }

    /// The groups a spending category can be put in
    static let categoryGroupChoices = ["Essentials", "Bills", "Lifestyle", "Savings", "Other"]

    /// Spending categories by group, in Budget's order; a group not in the list comes last, by name
    var expenseCategoryGroups: [(name: String, categories: [LedgerAccountRecord])] {
        let order = ["Essentials", "Lifestyle", "Savings", "Other"]
        let grouped = Dictionary(grouping: budgetCategories) { $0.group.isEmpty ? "Other" : $0.group }
        return grouped.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
            .map { ($0, grouped[$0] ?? []) }
    }

    var hasAccounts: Bool { !accounts.isEmpty }

    func balance(_ accountId: UUID) -> Money { ledger.balance(of: accountId) }

    /// Entries newest first. One account's history includes its opening balance;
    /// the overall activity list leaves opening balances out.
    func entries(touching accountId: UUID? = nil, includeVoided: Bool = false) -> [EntryRecord] {
        entryRecords.filter { record in
            guard includeVoided || record.status == .posted else { return false }
            if let accountId { return record.lines.contains { $0.accountId == accountId } }
            return record.kind != .openingBalance
        }
    }

    // MARK: - Headline numbers

    var monthKey: String { BudgetMonth.key(for: today, calendar: calendar) }

    /// A month's entries in a spending category, loan payments for its loans included (even with no interest)
    func entries(in categoryId: UUID, month: String) -> [EntryRecord] {
        guard let start = BudgetMonth.start(of: month, calendar: calendar),
              let end = BudgetMonth.end(of: month, calendar: calendar) else { return [] }
        return entryRecords.filter { record in
            record.status == .posted && record.date >= start && record.date < end
                && ledger.spending(of: record.entry, on: categoryId, loanCategories: loanCategories) != nil
        }
    }

    /// One row of "what went in" to a category
    struct CategoryPart: Identifiable {
        let id: String
        let name: String
        let amount: Money
        let detail: String?
        /// The loan it's for, when the category holds loans
        var loanId: UUID? = nil
        /// How many entries it sums
        var count = 1
    }

    /// What went into a category in a month: each of its loans (paid, with interest, or when it's due),
    /// then everything else grouped by what it was spent on, largest first
    func breakdown(_ categoryId: UUID, month: String) -> [CategoryPart] {
        let entries = entries(in: categoryId, month: month)
        let loans = loans(in: categoryId)
        let loanIds = Set(loans.map(\.id))
        var parts = loans.map { loan -> CategoryPart in
            let payments = entries.filter { $0.kind == .debtPayment && $0.lines.contains { $0.accountId == loan.id } }
            let paid = payments.compactMap { record -> Money? in
                let lines = record.entry.lines.filter { $0.accountId == loan.id || $0.accountId == categoryId }
                return lines.isEmpty ? nil : lines.map(\.amount).sum(currency)
            }.sum(currency)
            let interest = payments.compactMap { $0.entry.amount(on: categoryId) }.sum(currency)
            let detail: String
            if paid.isPositive {
                detail = interest.isPositive ? "\(interest.compact) interest" : "Paid"
            } else if let item = paymentItem(for: loan.id),
                      let due = occurrences.first(where: { $0.itemId == item.id && !$0.remaining.isZero && !$0.skipped
                                                           && BudgetMonth.key(for: $0.dueDate, calendar: calendar) == month }) {
                detail = "Due " + due.dueDate.formatted(.dateTime.day().month(.abbreviated))
            } else {
                detail = "Not paid this month"
            }
            return CategoryPart(id: loan.id.uuidString, name: loan.name, amount: paid, detail: detail, loanId: loan.id)
        }
        .sorted { ($0.amount.minorUnits, $1.name) > ($1.amount.minorUnits, $0.name) }
        // Everything else, grouped by what it was for
        let others = entries.filter { record in !(record.kind == .debtPayment && record.lines.contains { loanIds.contains($0.accountId) }) }
        func label(_ record: EntryRecord) -> String {
            let memo = record.memo.trimmingCharacters(in: .whitespaces)
            return memo.isEmpty ? "No description" : memo
        }
        // "Carrefour" and "carrefour" are the same shop
        let grouped = Dictionary(grouping: others) { label($0).lowercased() }
        parts += grouped.map { key, records in
            let amount = records.compactMap { ledger.spending(of: $0.entry, on: categoryId, loanCategories: loanCategories) }.sum(currency)
            // Show the spelling used most, the earliest one on a tie
            let spellings = Dictionary(grouping: records.sorted { $0.createdAt < $1.createdAt }, by: label)
            let name = records.sorted { $0.createdAt < $1.createdAt }.map(label)
                .max { spellings[$0]!.count < spellings[$1]!.count } ?? key
            return CategoryPart(id: "memo-" + key, name: name, amount: amount,
                                detail: records.count > 1 ? "\(records.count) times" : nil, count: records.count)
        }
        .sorted { ($0.amount.minorUnits, $1.name) > ($1.amount.minorUnits, $0.name) }
        return parts
    }

    var netWorth: NetWorth { ledger.netWorth() }

    /// Cash, bank and savings accounts counted in net worth: the same accounts as "Own" on Accounts, less investments
    var cashAccounts: [LedgerAccountRecord] {
        accounts.filter { $0.kind.holdsMoney && $0.kind != .investment && $0.includeInNetWorth }
    }

    var cashAndBank: Money { cashAccounts.map { balance($0.id) }.sum(currency) }

    var debtAccounts: [LedgerAccountRecord] {
        accounts.filter { $0.kind.isLiability && $0.includeInNetWorth }
    }

    /// Everything owed on cards and loans, as a positive amount
    var totalDebt: Money { debtAccounts.map { balance($0.id).negated }.sum(currency) }

    /// When each account's balance was last confirmed: reconciled, or its newest entry
    var lastConfirmed: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for record in accountRecords where record.kind.isBalanceSheet {
            let newest = entryRecords.first { $0.status == .posted && $0.lines.contains { $0.accountId == record.id } }?.date
            result[record.id] = [record.lastReconciledAt, newest].compactMap { $0 }.max()
        }
        return result
    }

    /// Safe-to-spend runs until the day before the next expected income, or month end
    var nextIncomeDate: Date? {
        occurrences
            .filter { occ in items.first { $0.id == occ.itemId }?.direction == .inflow && occ.dueDate > today && !occ.remaining.isZero }
            .map(\.dueDate).min()
    }

    var defaultPeriodEnd: Date {
        if let nextIncome = nextIncomeDate, let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: nextIncome)) {
            return endOfDay(max(dayBefore, today))
        }
        let monthEnd = BudgetMonth.end(of: monthKey, calendar: calendar) ?? today
        return monthEnd.addingTimeInterval(-1)
    }

    func endOfDay(_ date: Date) -> Date {
        (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date).addingTimeInterval(-1)
    }

    var categoryReservations: [CategoryReservation] {
        accountRecords.filter { $0.kind == .expense && !$0.archived && $0.reserveInSafeToSpend }.map {
            CategoryReservation(categoryId: $0.id, name: $0.name, remaining: budget.line($0.id, month: monthKey).withoutBills)
        }
    }

    /// The one way safe-to-spend is worked out, so Home, its breakdown, Siri and the widget always agree.
    /// `buffer` previews a buffer that hasn't been saved yet.
    func safeToSpendCalculator(buffer: Money? = nil) -> SafeToSpendCalculator {
        // A debt's bill already holds back its instalment, so the budget line it's paid from isn't held back twice
        let interest = Self.systemCategory("interest", name: "Interest & fees", in: accountRecords)?.id
        let billed = items.map { item -> PlannedItem in
            var item = item
            if let debtId = item.debtId {
                item.categoryId = account(debtId)?.kind == .loan ? loanCategories[debtId] : (item.categoryId ?? interest)
            }
            return item
        }
        return SafeToSpendCalculator(ledger: ledger, items: billed, occurrences: occurrences, reserves: reserves,
                              categoryReservations: categoryReservations, buffer: buffer ?? settings.buffer,
                              lastConfirmed: lastConfirmed, staleAfterDays: settings.staleAfterDays, calendar: calendar)
    }

    func safeToSpend(through end: Date? = nil, buffer: Money? = nil) -> SafeToSpend {
        let calculator = safeToSpendCalculator(buffer: buffer)
        // Bills due on payday are held back too: the salary may land after them
        guard end == nil, let payday = nextIncomeDate else {
            return calculator.calculate(today: today, periodEnd: end ?? defaultPeriodEnd)
        }
        return calculator.calculate(today: today, periodEnd: defaultPeriodEnd, billsThrough: endOfDay(payday))
    }

    // MARK: - Plan

    func item(for occurrence: Occurrence) -> PlannedItem? { items.first { $0.id == occurrence.itemId } }

    /// Unpaid outflows from overdue through `days` ahead
    func upcomingBills(days: Int = 30) -> [Occurrence] {
        let limit = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return occurrences.filter { occ in
            item(for: occ)?.direction == .outflow && !occ.skipped && !occ.remaining.isZero && occ.dueDate <= limit
        }
    }

    func state(of occurrence: Occurrence) -> OccurrenceState { occurrence.state(today: today, calendar: calendar) }

    /// Days before each bill's due date to remind; negative means never
    func reminderDays(for itemId: UUID) -> Int { itemRecords[itemId]?.reminderDaysBefore ?? 2 }

    func billReminders(hour: Int, now: Date) -> [BillReminder] {
        ReminderPlanner.plan(items: items, occurrences: occurrences,
                             daysBefore: itemRecords.mapValues(\.reminderDaysBefore),
                             now: now, hour: hour, calendar: calendar)
    }

    // MARK: - Debts

    var debts: [LedgerAccountRecord] { accounts.filter { $0.kind.isLiability } }

    /// What's owed on a card or loan, as a positive amount
    func owed(_ debtId: UUID) -> Money { balance(debtId).negated }

    /// The monthly bill that pays this debt, if one was set up
    func paymentItem(for debtId: UUID) -> PlannedItem? { items.first { $0.debtId == debtId } }

    /// When the next payment is due: the next unpaid bill, else the due day, else in a month
    func nextPaymentDate(for debt: LedgerAccountRecord) -> Date {
        if let item = paymentItem(for: debt.id),
           let next = occurrences.first(where: { $0.itemId == item.id && !$0.remaining.isZero && !$0.skipped }) {
            return next.dueDate
        }
        if let day = debt.debtTerms?.dueDay {
            return DebtCalculator.nextDueDate(dueDay: day, onOrAfter: today, calendar: calendar)
        }
        return calendar.date(byAdding: .month, value: 1, to: today) ?? today
    }

    func payoff(for debt: LedgerAccountRecord, extra: Money? = nil) -> Payoff? {
        guard let terms = debt.debtTerms else { return nil }
        return DebtCalculator.payoff(owed: owed(debt.id), terms: terms, extra: extra,
                                     firstPayment: nextPaymentDate(for: debt), calendar: calendar)
    }

    /// Spendable balances ahead, as bills are paid and income arrives
    func cashForecast(days: Int) -> CashForecast {
        let spendable = accounts.filter(\.spendable)
        let end = endOfDay(calendar.date(byAdding: .day, value: days, to: today) ?? today)
        return CashForecaster.forecast(start: spendable.map { balance($0.id) }.sum(currency), items: items,
                                       occurrences: occurrences, spendableAccountIds: Set(spendable.map(\.id)),
                                       today: today, through: end, calendar: calendar)
    }

    // MARK: - Savings

    var goals: [Reserve] { reserves.filter(\.isGoal) }

    /// An account's balance less what other set-aside money already claims
    func freeToSetAside(in accountId: UUID, excluding reserveId: UUID? = nil) -> Money {
        let claimed = reserves.filter { $0.accountId == accountId && $0.id != reserveId }.map(\.amount).sum(currency)
        return balance(accountId) - claimed
    }

    /// Unpaid bills paid from an account, due up to and including payday (or month end if no payday is
    /// known): the same bills Safe to spend holds back. Bills with no account count against spendable ones.
    func unpaidBills(from accountId: UUID) -> [(occurrence: Occurrence, item: PlannedItem)] {
        let spendable = account(accountId)?.spendable == true
        let through = nextIncomeDate.map(endOfDay) ?? defaultPeriodEnd
        return occurrences.compactMap { occ in
            guard let item = item(for: occ), item.direction == .outflow, !occ.skipped, !occ.remaining.isZero,
                  occ.dueDate <= through, item.accountId == accountId || (item.accountId == nil && spendable) else { return nil }
            return (occ, item)
        }
    }

    /// Two bills that look like the same payment kept twice: the same amount, as often, in the
    /// same category, with due dates within a week of each other (a skipped month doesn't hide it).
    /// Names aren't compared, so "Loan payment" and "Construction payment" match in any language.
    /// Two different loans never do.
    var duplicateBills: [(PlannedItem, PlannedItem)] {
        let start = calendar.startOfDay(for: today)
        let upcoming = Dictionary(grouping: occurrences.filter { $0.dueDate >= start && !$0.isSettledOrStarted }, by: \.itemId)
            .mapValues { $0.map(\.dueDate) }
        func category(_ item: PlannedItem) -> UUID? {
            item.debtId.flatMap { loanCategories[$0] } ?? item.categoryId
        }
        func close(_ a: [Date], _ b: [Date]) -> Bool {
            a.contains { x in b.contains { abs(x.timeIntervalSince($0)) <= 7 * 86_400 } }
        }
        let bills = items.filter { $0.direction == .outflow && upcoming[$0.id] != nil }
            .sorted { (upcoming[$0.id]!.min()!, $0.name) < (upcoming[$1.id]!.min()!, $1.name) }
        var pairs: [(PlannedItem, PlannedItem)] = []
        for (i, a) in bills.enumerated() {
            for b in bills[(i + 1)...] where a.amount == b.amount && a.schedule.frequency == b.schedule.frequency
                && category(a) == category(b) && (a.debtId == nil || b.debtId == nil || a.debtId == b.debtId)
                && close(upcoming[a.id]!, upcoming[b.id]!) {
                if !pairs.contains(where: { [$0.0.id, $0.1.id].contains(a.id) || [$0.0.id, $0.1.id].contains(b.id) }) {
                    pairs.append((a, b))
                }
            }
        }
        return pairs
    }

    /// Payments already recorded that look like an unpaid bill but aren't linked to it.
    /// Each bill is suggested once, for its best match; nothing is ever linked without asking.
    var billSuggestions: [BillSuggestion] {
        guard let since = calendar.date(byAdding: .day, value: -35, to: today) else { return [] }
        let infos = Dictionary(accountRecords.map { ($0.id, $0.info) }, uniquingKeysWith: { a, _ in a })
        var best: [UUID: (BillSuggestion, Int)] = [:]
        for record in entryRecords where record.status == .posted && record.occurrenceId == nil && record.date >= since {
            guard let payment = BillPayment(record.entry, accounts: infos) else { continue }
            let dismissed = Set(record.dismissedOccurrenceIds)
            guard let match = BillMatcher.candidates(for: payment, occurrences: occurrences, items: items, calendar: calendar)
                .first(where: { !dismissed.contains($0.occurrenceId) }),
                  let occ = occurrences.first(where: { $0.id == match.occurrenceId }),
                  let item = item(for: occ) else { continue }
            if let current = best[occ.id], current.1 >= match.score { continue }
            best[occ.id] = (BillSuggestion(entry: record, payment: payment, occurrence: occ, item: item, isPartial: match.isPartial),
                            match.score)
        }
        return best.values.map(\.0).sorted { $0.occurrence.dueDate < $1.occurrence.dueDate }
    }

    /// Bills a new payment could be, best first, for the "This pays …" option when saving
    func billCandidates(for payment: BillPayment) -> [(occurrence: Occurrence, item: PlannedItem, isPartial: Bool)] {
        BillMatcher.candidates(for: payment, occurrences: occurrences, items: items, calendar: calendar).compactMap { m in
            guard let occ = occurrences.first(where: { $0.id == m.occurrenceId }), let item = item(for: occ) else { return nil }
            return (occ, item, m.isPartial)
        }
    }

    func progress(of goal: Reserve) -> GoalProgress? {
        guard let target = goal.target else { return nil }
        return GoalCalculator.progress(saved: goal.amount, target: target, targetDate: goal.targetDate, today: today, calendar: calendar)
    }

    var activeReservesTotal: Money { reserves.map(\.amount).sum(currency) }

    /// Setup is complete enough for a reliable safe-to-spend
    var setupComplete: Bool { settings.onboardingDone && hasAccounts }
}

extension FinanceSnapshot {
    /// What's still owed on cards and loans that are part of the budget: Budget takes it out
    /// of what's left to plan, while safe-to-spend only holds back the payments due before payday
    var owedInBudget: [(name: String, amount: Money)] {
        accounts.filter { $0.onBudget && $0.kind.isLiability && !$0.archived }.compactMap { a in
            let b = balance(a.id)
            return b.isNegative ? (a.name, b.magnitude) : nil
        }
    }
}

/// A recorded payment that looks like an unpaid bill
struct BillSuggestion: Identifiable {
    let entry: EntryRecord
    let payment: BillPayment
    let occurrence: Occurrence
    let item: PlannedItem
    let isPartial: Bool

    var id: UUID { occurrence.id }
}
