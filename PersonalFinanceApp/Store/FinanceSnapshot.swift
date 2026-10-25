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

        let categories = accounts.filter { $0.kind == .expense && !$0.archived }
            .map { BudgetCategory(id: $0.id, name: $0.name, group: $0.group, policy: $0.policy) }
        self.budget = Budget(ledger: ledger, categories: categories,
                             allocations: store.fetch(AllocationRecord.self).map(\.allocation), calendar: store.calendar)

        let itemRecords = store.fetch(PlannedItemRecord.self).filter { !$0.archived }
        self.itemRecords = Dictionary(itemRecords.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.items = itemRecords.map(\.item)
        let itemIds = Set(itemRecords.map(\.id))
        self.occurrences = store.fetch(OccurrenceRecord.self).map(\.occurrence)
            .filter { itemIds.contains($0.itemId) }
            .sorted { $0.dueDate < $1.dueDate }
        self.reserves = store.fetch(ReserveRecord.self).filter { !$0.archived }.map(\.reserve)
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

    var expenseCategories: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind == .expense && !$0.archived }
    }

    var incomeCategories: [LedgerAccountRecord] {
        accountRecords.filter { $0.kind == .income && !$0.archived }
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

    var netWorth: NetWorth { ledger.netWorth() }

    var cashAndBank: Money {
        accounts.filter { $0.kind.isAsset && $0.kind != .investment }.map { balance($0.id) }.sum(currency)
    }

    var totalDebt: Money {
        accounts.filter { $0.kind.isLiability }.map { balance($0.id).negated }.sum(currency)
    }

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
    var defaultPeriodEnd: Date {
        let nextIncome = occurrences
            .filter { occ in items.first { $0.id == occ.itemId }?.direction == .inflow && occ.dueDate > today && !occ.remaining.isZero }
            .map(\.dueDate).min()
        if let nextIncome, let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: nextIncome)) {
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
            CategoryReservation(categoryId: $0.id, name: $0.name, remaining: budget.line($0.id, month: monthKey).remaining)
        }
    }

    var safeToSpendCalculator: SafeToSpendCalculator {
        SafeToSpendCalculator(ledger: ledger, items: items, occurrences: occurrences, reserves: reserves,
                              categoryReservations: categoryReservations, buffer: settings.buffer,
                              lastConfirmed: lastConfirmed, staleAfterDays: settings.staleAfterDays, calendar: calendar)
    }

    func safeToSpend(through end: Date? = nil) -> SafeToSpend {
        safeToSpendCalculator.calculate(today: today, periodEnd: end ?? defaultPeriodEnd)
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

    var activeReservesTotal: Money { reserves.map(\.amount).sum(currency) }

    /// Setup is complete enough for a reliable safe-to-spend
    var setupComplete: Bool { settings.onboardingDone && hasAccounts }
}
