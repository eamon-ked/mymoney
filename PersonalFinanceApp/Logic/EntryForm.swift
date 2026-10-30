//
//  EntryForm.swift
//  Nokael Money
//
//  What someone fills in to record an expense, income, transfer or balance
//  correction. Any screen fills one in and calls store.save(_:); the checks,
//  the wording of what's missing and the ledger lines all live here, so a new
//  design can't record money differently from the old one.
//

import Foundation
import NokaelCore

/// What the Add button can create
enum AddKind: String, Identifiable, CaseIterable {
    case expense, income, transfer, adjustment
    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        case .adjustment: return "Balance adjustment"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}

struct EntryForm {
    var kind: AddKind
    /// For an adjustment: what the account really holds, not the difference
    var amount: Money?
    var accountId: UUID?
    /// Transfers only
    var toAccountId: UUID?
    /// Expenses and income
    var categoryId: UUID?
    var memo = ""
    var notes = ""
    var date = Date()
    /// Adjustments only
    var reason = ""
    /// New entries only: also save it as a repeating bill or income, starting one step after `date`
    var repeats = false
    var frequency: Frequency = .monthly(every: 1)
    /// The bill or expected income this pays
    var occurrenceId: UUID?
    /// One per form: a double tap or a retry can't save it twice
    var key = UUID()

    /// What's wrong with the amount, kept apart so a screen can show it beside the amount
    struct AmountProblem: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    /// The amount, checked; throws AmountProblem
    func checkedAmount() throws -> Money {
        guard let amount else { throw AmountProblem(message: "Enter an amount.") }
        if kind != .adjustment && !amount.isPositive { throw AmountProblem(message: "Enter an amount greater than zero.") }
        return amount
    }

    /// The double-entry lines this form records
    @MainActor func entry(in snapshot: FinanceSnapshot, equity: AccountInfo) throws -> Entry {
        let amount = try checkedAmount()
        let title = memo.trimmingCharacters(in: .whitespaces)
        guard let account = snapshot.account(accountId)?.info else {
            throw StoreError.invalid(snapshot.hasAccounts ? "Choose an account." : "Add an account first.")
        }
        var entry: Entry
        switch kind {
        case .expense:
            guard let category = snapshot.account(categoryId)?.info else { throw StoreError.invalid("Choose what it was for.") }
            entry = try EntryFactory.expense(amount, from: account, category: category, date: date,
                                             memo: title.isEmpty ? category.name : title, key: key)
        case .income:
            guard let category = snapshot.account(categoryId)?.info else { throw StoreError.invalid("Choose the kind of income.") }
            entry = try EntryFactory.income(amount, to: account, category: category, date: date,
                                            memo: title.isEmpty ? category.name : title, key: key)
        case .transfer:
            guard let to = snapshot.account(toAccountId)?.info else { throw StoreError.invalid("Choose where the money goes.") }
            entry = try EntryFactory.transfer(amount, from: account, to: to, date: date,
                                              memo: title.isEmpty ? "Transfer to \(to.name)" : title, key: key)
        case .adjustment:
            let delta = amount - snapshot.ledger.balance(of: account.id, asOf: date)
            guard !delta.isZero else { throw StoreError.invalid("That's already the recorded balance.") }
            entry = try EntryFactory.adjustment(delta, account: account, equity: equity, date: date, reason: reason, key: key)
        }
        entry.occurrenceId = occurrenceId
        return entry
    }

    /// The repeating bill or income saved with a new entry when `repeats` is on
    @MainActor func repeatItem(in snapshot: FinanceSnapshot) -> PlannedItem? {
        guard repeats, kind == .expense || kind == .income, let amount = try? checkedAmount(),
              let next = snapshot.calendar.date(byAdding: frequency.step, to: date) else { return nil }
        return PlannedItem(name: memo.isEmpty ? (snapshot.account(categoryId)?.name ?? kind.title) : memo,
                           direction: kind == .income ? .inflow : .outflow, amount: amount,
                           schedule: Schedule(start: next, frequency: frequency),
                           accountId: accountId, categoryId: categoryId)
    }
}

extension Frequency {
    /// From one occurrence to the next
    var step: DateComponents {
        switch self {
        case .weekly(let n): return DateComponents(day: 7 * n)
        case .monthly(let n): return DateComponents(month: n)
        case .quarterly: return DateComponents(month: 3)
        case .annually: return DateComponents(year: 1)
        case .everyDays(let n): return DateComponents(day: n)
        }
    }
}

extension LedgerStore {
    /// Records the form, or replaces `originalId` with it when editing
    @discardableResult
    func save(_ form: EntryForm, replacing originalId: UUID? = nil) throws -> UUID {
        let entry = try form.entry(in: snapshot, equity: equityAccount.info)
        if let originalId { return try replace(originalId, with: entry, notes: form.notes) }
        let id = try post(entry, notes: form.notes)
        if let item = form.repeatItem(in: snapshot) { try savePlannedItem(item) }
        return id
    }
}
