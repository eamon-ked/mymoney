//
//  EntryForm.swift
//  Nokael Money
//
//  What someone fills in to record an expense, income, transfer or balance
//  correction. Any screen fills one in and calls store.save(_:); the checks,
//  the wording of what's missing and the ledger lines all live here, so a new
//  design can't record money differently from the old one.
//

import CryptoKit
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
    /// Expenses only: the people who owe part of it back, and how much each
    var shares: [(personId: UUID, amount: Money)] = []
    /// Expenses only: the amount spread over several categories; empty means it all goes to `categoryId`
    var parts: [(categoryId: UUID, amount: Money)] = []
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
    /// `replacing` is the entry being edited: a balance correction is worked out as if it weren't there,
    /// since the edit takes its place
    @MainActor func entry(in snapshot: FinanceSnapshot, equity: AccountInfo, replacing originalId: UUID? = nil) throws -> Entry {
        let amount = try checkedAmount()
        let title = memo.trimmingCharacters(in: .whitespaces)
        guard let account = snapshot.account(accountId)?.info else {
            throw StoreError.invalid(snapshot.hasAccounts ? "Choose an account." : "Add an account first.")
        }
        var entry: Entry
        switch kind {
        case .expense:
            let people = try shares.map { share in
                guard let person = snapshot.account(share.personId)?.info else { throw StoreError.notFound }
                return (person: person, amount: share.amount)
            }
            if parts.count > 1 {
                let split = try parts.map { part in
                    guard let category = snapshot.account(part.categoryId)?.info else { throw StoreError.invalid("Choose a category for each part.") }
                    return (category: category, amount: part.amount)
                }
                do {
                    entry = try EntryFactory.expense(amount, from: account, parts: split, shares: people, date: date,
                                                     memo: title.isEmpty ? split.map(\.category.name).joined(separator: " & ") : title, key: key)
                } catch { throw StoreError.from(error) }
                break
            }
            guard let category = snapshot.account(categoryId)?.info else { throw StoreError.invalid("Choose what it was for.") }
            entry = try EntryFactory.splitExpense(amount, from: account, category: category, shares: people, date: date,
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
            var recorded = snapshot.ledger.balance(of: account.id, asOf: date)
            if let original = snapshot.entryRecords.first(where: { $0.id == originalId }), original.status == .posted,
               original.date <= date {
                for line in original.lines where line.accountId == account.id {
                    recorded = recorded - Money(minorUnits: line.minorUnits, currency: line.currency)
                }
            }
            let delta = amount - recorded
            guard !delta.isZero else { throw StoreError.invalid("That's already the recorded balance.") }
            entry = try EntryFactory.adjustment(delta, account: account, equity: equity, date: date, reason: reason, key: key)
        }
        entry.occurrenceId = occurrenceId
        return entry
    }

    /// The repeating bill or income saved with a new entry when `repeats` is on
    /// It starts on the entry's own date, so a bill entered on the 31st keeps returning to the 31st after
    /// a short month; the entry itself pays that first one. Its id comes from the form's key, so saving
    /// the same form again can never make a second schedule.
    @MainActor func repeatItem(in snapshot: FinanceSnapshot) -> PlannedItem? {
        guard repeats, kind == .expense || kind == .income, let amount = try? checkedAmount() else { return nil }
        return PlannedItem(id: repeatItemId,
                           name: memo.isEmpty ? (snapshot.account(categoryId)?.name ?? kind.title) : memo,
                           direction: kind == .income ? .inflow : .outflow, amount: amount,
                           schedule: Schedule(start: date, frequency: frequency),
                           accountId: accountId, categoryId: categoryId)
    }

    /// The repeating bill's id, the same every time this form is saved
    var repeatItemId: UUID {
        var bytes = Array(SHA256.hash(data: Data("repeat|\(key.uuidString)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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
        if let originalId {
            let entry = try form.entry(in: snapshot, equity: equityAccount.info, replacing: originalId)
            return try replace(originalId, with: entry, notes: form.notes)
        }
        // The same form again (a double tap, a retry): what it saved the first time, nothing more
        if let saved = postedEntry(key: form.key) { return saved }
        // The entry and its repeating bill are kept together, or neither is
        return try inOneSave {
            var entry = try form.entry(in: snapshot, equity: equityAccount.info)
            if let item = form.repeatItem(in: snapshot) {
                try savePlannedItem(item)
                if entry.occurrenceId == nil { entry.occurrenceId = occurrence(of: item.id, on: form.date) }
            }
            return try post(entry, notes: form.notes)
        }
    }

    /// Undoes a new entry, and the repeating bill saved with it
    func undoSave(_ form: EntryForm, entryId: UUID) throws {
        try inOneSave {
            try void(entryId)
            if form.repeats { try deletePlannedItem(form.repeatItemId) }
        }
    }
}
