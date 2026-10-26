//
//  LedgerStore.swift
//  Nokael Money
//
//  The only place that changes money. Every mutation validates, saves once,
//  writes an audit record and bumps `revision`, so every screen reading the
//  snapshot updates together and nothing is ever stale.
//

import Foundation
import Observation
import SwiftData
import NokaelCore

enum StoreError: LocalizedError, Equatable {
    case invalid(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .notFound: return "That item no longer exists."
        }
    }

    static func from(_ error: Error) -> StoreError {
        if let e = error as? StoreError { return e }
        if let e = error as? LedgerError {
            switch e {
            case .amountMustBePositive: return .invalid("Enter an amount greater than zero.")
            case .sameAccount: return .invalid("Choose two different accounts.")
            case .reasonRequired: return .invalid("Add a short reason so you can find this later.")
            case .wrongAccountKind(let hint): return .invalid(hint + ".")
            case .mixedCurrencies: return .invalid("Both sides need the same currency.")
            case .unbalanced, .noLines, .unknownAccount: return .invalid("This entry doesn't add up, so it wasn't saved.")
            }
        }
        if let e = error as? BudgetError {
            switch e {
            case .amountMustBePositive: return .invalid("Enter an amount greater than zero.")
            case .sameCategory: return .invalid("Choose two different categories.")
            case .exceedsAvailable(let available):
                return .invalid("Only \(MoneyFormat.string(available)) is left in that category.")
            }
        }
        return .invalid(error.localizedDescription)
    }
}

@MainActor
@Observable
final class LedgerStore {
    let context: ModelContext
    let calendar: Calendar
    /// Injectable clock, so tests and previews can fix "today"
    var now: () -> Date

    /// Bumped on every change; everything derived re-reads after it
    private(set) var revision = 0
    @ObservationIgnored private var cached: (revision: Int, snapshot: FinanceSnapshot)?

    /// How far ahead bill and income occurrences are kept
    static let horizonDays = 120

    init(context: ModelContext, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.calendar = calendar
        self.now = now
        ensureSettingsAndSystemAccounts()
    }

    // MARK: - Reading

    /// Reading this ties the caller to `revision`, so views update when settings change
    var settings: SettingsRecord {
        _ = revision
        if let s = try? context.fetch(FetchDescriptor<SettingsRecord>()).first { return s }
        let s = SettingsRecord()
        context.insert(s)
        try? context.save()
        return s
    }

    var currency: String { settings.currency }

    var snapshot: FinanceSnapshot {
        _ = revision
        if let cached, cached.revision == revision { return cached.snapshot }
        let s = FinanceSnapshot(store: self)
        cached = (revision, s)
        return s
    }

    func fetch<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>? = nil) -> [T] {
        (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
    }

    func account(_ id: UUID) -> LedgerAccountRecord? {
        fetch(LedgerAccountRecord.self, #Predicate { $0.id == id }).first
    }

    func entryRecord(_ id: UUID) -> EntryRecord? {
        fetch(EntryRecord.self, #Predicate { $0.id == id }).first
    }

    var equityAccount: LedgerAccountRecord {
        let raw = AccountKind.equity.rawValue
        return fetch(LedgerAccountRecord.self, #Predicate { $0.kindRaw == raw }).first!
    }

    var auditTrail: [AuditRecord] {
        _ = revision
        return ((try? context.fetch(FetchDescriptor<AuditRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
    }

    // MARK: - Setup

    private func ensureSettingsAndSystemAccounts() {
        let s = settings
        let raw = AccountKind.equity.rawValue
        if fetch(LedgerAccountRecord.self, #Predicate { $0.kindRaw == raw }).isEmpty {
            context.insert(LedgerAccountRecord(name: "Opening balances & adjustments", kind: .equity,
                                               currency: s.currency, isSystem: true))
            try? context.save()
        }
    }

    /// Editable starting categories; the person can rename, archive or add their own
    func addStarterCategories() throws {
        let existing = Set(fetch(LedgerAccountRecord.self).filter { $0.kind.isCategory }.map(\.name))
        let expenses: [(String, String, String, String)] = [
            ("Rent or mortgage", "Essentials", "house.fill", "#5B6CFF"),
            ("Groceries", "Essentials", "cart.fill", "#2BA84A"),
            ("Utilities", "Essentials", "bolt.fill", "#F2A33A"),
            ("Transport", "Essentials", "car.fill", "#3A7BD5"),
            ("Phone & internet", "Essentials", "wifi", "#5AC8FA"),
            ("Dining out", "Lifestyle", "fork.knife", "#E4572E"),
            ("Entertainment", "Lifestyle", "film.fill", "#AF52DE"),
            ("Shopping", "Lifestyle", "bag.fill", "#FF2D55"),
            ("Health", "Other", "heart.fill", "#FF3B30"),
            ("Interest & fees", "Other", "percent", "#8E8E93"),
            ("Other spending", "Other", "ellipsis.circle.fill", "#8E8E93")
        ]
        for (i, c) in expenses.enumerated() where !existing.contains(c.0) {
            context.insert(LedgerAccountRecord(name: c.0, kind: .expense, currency: currency, colorHex: c.3,
                                               icon: c.2, group: c.1, sortOrder: i))
        }
        for (i, name) in ["Salary", "Other income"].enumerated() where !existing.contains(name) {
            context.insert(LedgerAccountRecord(name: name, kind: .income, currency: currency, colorHex: "#2BA84A",
                                               icon: "arrow.down.circle.fill", sortOrder: i))
        }
        try commit()
    }

    // MARK: - Accounts and categories

    @discardableResult
    func createAccount(name: String, kind: AccountKind, opening: Money, openingDate: Date,
                       institution: String? = nil, colorHex: String = "#3A7BD5") throws -> LedgerAccountRecord {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw StoreError.invalid("Give the account a name.") }
        guard kind.isBalanceSheet else { throw StoreError.invalid("Choose an account type.") }
        let order = fetch(LedgerAccountRecord.self).filter { $0.kind.isBalanceSheet }.count
        let record = LedgerAccountRecord(name: trimmed, kind: kind, currency: currency, colorHex: colorHex,
                                         icon: AccountStyle.icon(for: kind), institution: institution, sortOrder: order)
        context.insert(record)
        let entry = try EntryFactory.openingBalance(opening, for: record.info, equity: equityAccount.info, date: openingDate)
        insert(entry, notes: "")
        context.insert(AuditRecord(action: "account.created", subjectId: record.id,
                                   summary: "Opened \(trimmed) with \(MoneyFormat.string(opening))"))
        if settings.lastUsedAccountId == nil, kind.defaultSpendable { settings.lastUsedAccountId = record.id }
        try commit()
        return record
    }

    func updateAccount(_ record: LedgerAccountRecord, _ change: (LedgerAccountRecord) -> Void) throws {
        let wasArchived = record.archived
        change(record)
        record.updatedAt = now()
        if record.archived != wasArchived {
            context.insert(AuditRecord(action: record.archived ? "account.archived" : "account.restored",
                                       subjectId: record.id, summary: record.name))
        }
        try commit()
    }

    @discardableResult
    func createCategory(name: String, kind: AccountKind, group: String, icon: String = "tag.fill",
                        colorHex: String = "#8E8E93") throws -> LedgerAccountRecord {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw StoreError.invalid("Give the category a name.") }
        guard kind.isCategory else { throw StoreError.invalid("Categories are for income or spending.") }
        let order = fetch(LedgerAccountRecord.self).filter { $0.kind == kind }.count
        let record = LedgerAccountRecord(name: trimmed, kind: kind, currency: currency, colorHex: colorHex,
                                         icon: icon, group: group, sortOrder: order)
        context.insert(record)
        try commit()
        return record
    }

    // MARK: - Entries

    /// Saves an entry once. Saving the same idempotency key again returns the
    /// existing entry instead of creating a duplicate (double taps, retries).
    @discardableResult
    func post(_ entry: Entry, notes: String = "") throws -> UUID {
        let id = try stage(entry, notes: notes)
        try commit()
        return id
    }

    /// Inserts without saving, so a batch can be committed (or rolled back) as one
    private func stage(_ entry: Entry, notes: String = "") throws -> UUID {
        let key = entry.idempotencyKey
        if let existing = fetch(EntryRecord.self, #Predicate { $0.idempotencyKey == key }).first {
            return existing.id
        }
        do { try EntryFactory.validate(entry) } catch { throw StoreError.from(error) }
        insert(entry, notes: notes)
        if let occurrenceId = entry.occurrenceId { applyPayment(of: entry, to: occurrenceId) }
        if let funding = entry.lines.first(where: { account($0.accountId)?.kind.defaultSpendable == true })?.accountId,
           entry.kind == .expense {
            settings.lastUsedAccountId = funding
        }
        return entry.id
    }

    // MARK: - Statement import

    struct ImportedRow {
        enum Target: Hashable {
            case category(UUID)
            /// Money moved to or from another of the person's accounts
            case transfer(UUID)
            /// Pays this bill (only for money out)
            case bill(UUID)
        }
        let date: Date
        let memo: String
        /// Signed, from the imported account's point of view
        let amount: Money
        let target: Target
        let key: UUID
    }

    /// Adds statement rows to one account. Category and transfer rows are saved
    /// together, all or nothing; bill payments go through `pay` so debts split.
    /// Returns how many rows were added.
    @discardableResult
    func importRows(_ rows: [ImportedRow], into accountId: UUID) throws -> Int {
        guard let account = account(accountId) else { throw StoreError.notFound }
        let bills = rows.filter { if case .bill = $0.target { return true } else { return false } }
        // Money out to a loan is an instalment: split into interest and principal like Pay a loan
        var instalments: [(row: ImportedRow, loanId: UUID)] = []
        do {
            for row in rows {
                let size = row.amount.magnitude
                switch row.target {
                case .category(let id):
                    guard let category = self.account(id) else { throw StoreError.notFound }
                    let entry = row.amount.isNegative
                        ? try EntryFactory.expense(size, from: account.info, category: category.info, date: row.date, memo: row.memo, key: row.key)
                        : try EntryFactory.income(size, to: account.info, category: category.info, date: row.date, memo: row.memo, key: row.key)
                    _ = try stage(entry)
                case .transfer(let id):
                    guard let other = self.account(id) else { throw StoreError.notFound }
                    if row.amount.isNegative, other.kind == .loan, account.kind.isAsset {
                        instalments.append((row, id))
                        continue
                    }
                    let entry = row.amount.isNegative
                        ? try EntryFactory.transfer(size, from: account.info, to: other.info, date: row.date, memo: row.memo, key: row.key)
                        : try EntryFactory.transfer(size, from: other.info, to: account.info, date: row.date, memo: row.memo, key: row.key)
                    _ = try stage(entry)
                case .bill:
                    continue
                }
            }
        } catch {
            context.rollback()
            throw StoreError.from(error)
        }
        context.insert(AuditRecord(action: "statement.imported", subjectId: accountId,
                                   summary: "Imported \(rows.count) statement rows into \(account.name)"))
        try commit()
        for row in bills {
            guard case .bill(let occurrenceId) = row.target else { continue }
            try pay(occurrenceId: occurrenceId, amount: row.amount.magnitude, accountId: accountId, categoryId: nil,
                    date: row.date, key: row.key)
        }
        for (row, loanId) in instalments {
            guard let loan = self.account(loanId) else { continue }
            let amount = row.amount.magnitude
            let split = DebtCalculator.split(payment: amount, owed: snapshot.balance(loanId).negated,
                                             annualRateBps: loan.debtRateBps ?? 0)
            if split.overpaid.isPositive {
                // More than is owed: keep it as a plain transfer rather than refuse the row
                let entry = try EntryFactory.transfer(amount, from: account.info, to: loan.info, date: row.date, memo: row.memo, key: row.key)
                _ = try post(entry)
            } else {
                try payDebt(loanId, from: accountId, amount: amount, interest: split.interest, fees: .zero(amount.currency),
                            date: row.date, key: row.key)
            }
        }
        return rows.count
    }

    /// Edits keep history: the original is voided, a replacement posted, and both linked
    @discardableResult
    func replace(_ originalId: UUID, with replacement: Entry, notes: String = "") throws -> UUID {
        guard let original = entryRecord(originalId), original.status == .posted else { throw StoreError.notFound }
        do { try EntryFactory.validate(replacement) } catch { throw StoreError.from(error) }
        let before = original.entry
        original.status = .void
        original.updatedAt = now()
        if let occ = original.occurrenceId { removePayment(of: before, from: occ) }
        var fresh = replacement
        if fresh.occurrenceId == nil { fresh.occurrenceId = before.occurrenceId }
        let record = insert(fresh, notes: notes)
        record.replacesId = originalId
        // Editing an automatic entry counts as reviewing it
        record.sourceRaw = original.sourceRaw
        record.cardHint = original.cardHint
        if let occ = fresh.occurrenceId { applyPayment(of: fresh, to: occ) }
        context.insert(AuditRecord(action: "entry.edited", subjectId: fresh.id,
                                   summary: "Changed \"\(before.memo)\" (\(describe(before))) to \(describe(fresh))"))
        try commit()
        return fresh.id
    }

    func void(_ entryId: UUID, reason: String? = nil) throws {
        guard let record = entryRecord(entryId), record.status == .posted else { throw StoreError.notFound }
        let entry = record.entry
        record.status = .void
        record.updatedAt = now()
        if let occ = record.occurrenceId { removePayment(of: entry, from: occ) }
        context.insert(AuditRecord(action: "entry.voided", subjectId: entryId,
                                   summary: "Deleted \"\(entry.memo)\" (\(describe(entry)))", reason: reason))
        try commit()
    }

    // MARK: - Automatic entries

    /// Saves an entry that arrived by itself (Apple Pay, a bank SMS, Siri)
    @discardableResult
    func postCaptured(_ entry: Entry, source: Capture.Source, cardHint: String?, needsReview: Bool) throws -> UUID {
        let key = entry.idempotencyKey
        if let existing = fetch(EntryRecord.self, #Predicate { $0.idempotencyKey == key }).first { return existing.id }
        do { try EntryFactory.validate(entry) } catch { throw StoreError.from(error) }
        let record = insert(entry, notes: "")
        record.sourceRaw = source.rawValue
        record.cardHint = cardHint
        record.needsReview = needsReview
        context.insert(AuditRecord(action: "entry.captured", subjectId: entry.id,
                                   summary: "\(source.title) added \"\(entry.memo)\" (\(describe(entry)))"))
        try commit()
        return entry.id
    }

    /// The same purchase arrived again from somewhere else; keep what's new
    func enrichCaptured(_ entryId: UUID, cardHint: String?) throws {
        guard let record = entryRecord(entryId) else { throw StoreError.notFound }
        guard record.cardHint == nil, let cardHint else { return }
        record.cardHint = cardHint
        try commit()
    }

    func markReviewed(_ entryId: UUID) throws {
        guard let record = entryRecord(entryId), record.needsReview else { return }
        record.needsReview = false
        record.updatedAt = now()
        try commit()
    }

    func markAllReviewed() throws {
        for record in fetch(EntryRecord.self, #Predicate { $0.needsReview }) { record.needsReview = false }
        try commit()
    }

    /// The account a Wallet card or card number belongs to, once the person said so
    func linkedAccount(forCard hint: String) -> UUID? {
        let key = CardLinkRecord.key(hint)
        guard let id = fetch(CardLinkRecord.self, #Predicate { $0.hint == key }).first?.accountId,
              let account = account(id), !account.archived else { return nil }
        return id
    }

    func linkCard(_ hint: String, to accountId: UUID) throws {
        let key = CardLinkRecord.key(hint)
        guard !key.isEmpty else { return }
        if let existing = fetch(CardLinkRecord.self, #Predicate { $0.hint == key }).first {
            existing.accountId = accountId
        } else {
            context.insert(CardLinkRecord(hint: hint, accountId: accountId))
        }
        try commit()
    }

    func unlinkCard(_ hint: String) throws {
        let key = CardLinkRecord.key(hint)
        for link in fetch(CardLinkRecord.self, #Predicate { $0.hint == key }) { context.delete(link) }
        try commit()
    }

    @discardableResult
    private func insert(_ entry: Entry, notes: String) -> EntryRecord {
        let record = EntryRecord(from: entry, notes: notes)
        context.insert(record)
        for line in entry.lines {
            let l = LineRecord(line)
            context.insert(l)
            l.entry = record
        }
        return record
    }

    private func describe(_ entry: Entry) -> String {
        let moved = entry.lines.filter { $0.amount.isPositive }.map(\.amount).sum(entry.lines.first?.amount.currency ?? currency)
        return MoneyFormat.string(moved) + " on " + entry.date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Reconciliation

    /// Marks everything up to the statement date reconciled. If the ledger and
    /// statement differ, an adjustment is posted only with a reason.
    func reconcile(accountId: UUID, statementDate: Date, statementBalance: Money, reason: String?) throws {
        guard let account = account(accountId) else { throw StoreError.notFound }
        let check = Reconciler.check(ledger: snapshot.ledger, accountId: accountId, statementDate: statementDate,
                                     statementBalance: statementBalance)
        if !check.matches {
            do {
                if let fix = try Reconciler.adjustment(for: check, account: account.info, equity: equityAccount.info,
                                                       reason: reason ?? "") {
                    insert(fix, notes: "")
                }
            } catch { throw StoreError.from(error) }
        }
        let ids = Set(check.unreconciled.map(\.id))
        for record in fetch(EntryRecord.self) where ids.contains(record.id) {
            record.cleared = .reconciled
            record.updatedAt = now()
        }
        account.lastReconciledAt = now()
        context.insert(AuditRecord(action: "account.reconciled", subjectId: accountId,
                                   summary: check.matches
                                       ? "Matched statement of \(MoneyFormat.string(statementBalance))"
                                       : "Adjusted by \(MoneyFormat.string(check.difference)) to match statement",
                                   reason: check.matches ? nil : reason))
        try commit()
    }

    // MARK: - Budget

    /// Sets a category's plan for a month by recording the change from the current amount
    func setAllocation(_ amount: Money, categoryId: UUID, month: String) throws {
        let current = snapshot.budget.allocated(categoryId, month: month)
        let delta = amount - current
        guard !delta.isZero else { return }
        context.insert(AllocationRecord(categoryId: categoryId, month: month, amount: delta))
        try commit()
    }

    func moveAllocation(_ amount: Money, from source: UUID, to destination: UUID, month: String,
                        allowOverdraw: Bool = false) throws {
        let changes: [Allocation]
        do {
            changes = try snapshot.budget.move(amount, from: source, to: destination, month: month, allowOverdraw: allowOverdraw)
        } catch { throw StoreError.from(error) }
        let moveId = UUID()
        for c in changes {
            context.insert(AllocationRecord(categoryId: c.categoryId, month: c.month, amount: c.amount, moveId: moveId))
        }
        try commit()
    }

    func copyPlan(from previous: String, to month: String) throws {
        for a in snapshot.budget.copyPlan(from: previous, to: month) {
            context.insert(AllocationRecord(categoryId: a.categoryId, month: a.month, amount: a.amount, note: "Copied from \(previous)"))
        }
        try commit()
    }

    // MARK: - Bills and expected income

    /// `reminderDays`: days before each due date to remind, negative for never; nil keeps the current choice
    func savePlannedItem(_ item: PlannedItem, reminderDays: Int? = nil) throws {
        guard !item.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw StoreError.invalid("Give it a name.") }
        guard item.amount.isPositive else { throw StoreError.invalid("Enter an amount greater than zero.") }
        let id = item.id
        if let record = fetch(PlannedItemRecord.self, #Predicate { $0.id == id }).first {
            record.update(from: item)
            if let reminderDays { record.reminderDaysBefore = reminderDays }
        } else {
            let record = PlannedItemRecord(item)
            if let reminderDays { record.reminderDaysBefore = reminderDays }
            context.insert(record)
        }
        regenerateOccurrences(for: item)
        try commit()
    }

    func archivePlannedItem(_ id: UUID) throws {
        guard let record = fetch(PlannedItemRecord.self, #Predicate { $0.id == id }).first else { throw StoreError.notFound }
        archive(record)
        try commit()
    }

    private func archive(_ record: PlannedItemRecord) {
        let id = record.id
        record.archived = true
        record.updatedAt = now()
        // Future unpaid occurrences were only projections; paid ones stay as history
        for occ in fetch(OccurrenceRecord.self, #Predicate { $0.itemId == id })
        where occ.paidMinor == 0 && !occ.skipped && occ.dueDate >= calendar.startOfDay(for: now()) {
            context.delete(occ)
        }
    }

    /// Records a real payment for an occurrence and links them
    @discardableResult
    func pay(occurrenceId: UUID, amount: Money, accountId: UUID, categoryId: UUID?, date: Date, key: UUID) throws -> UUID {
        guard let occ = fetch(OccurrenceRecord.self, #Predicate { $0.id == occurrenceId }).first,
              let item = plannedItem(occ.itemId),
              let account = account(accountId) else { throw StoreError.notFound }
        if let debtId = item.debtId, item.direction == .outflow {
            guard let debt = self.account(debtId) else { throw StoreError.notFound }
            let split = DebtCalculator.split(payment: amount, owed: snapshot.balance(debtId).negated,
                                             annualRateBps: debt.debtRateBps ?? 0)
            return try payDebt(debtId, from: accountId, amount: amount, interest: split.interest, fees: .zero(amount.currency),
                               date: date, key: key, occurrenceId: occurrenceId)
        }
        let entry: Entry
        do {
            if item.direction == .inflow {
                guard let category = (categoryId ?? item.categoryId).flatMap(self.account) ?? defaultIncomeCategory else {
                    throw StoreError.invalid("Choose an income category.")
                }
                entry = try EntryFactory.income(amount, to: account.info, category: category.info, date: date,
                                                memo: item.name, key: key, occurrenceId: occurrenceId)
            } else {
                guard let category = (categoryId ?? item.categoryId).flatMap(self.account) else {
                    throw StoreError.invalid("Choose a spending category.")
                }
                entry = try EntryFactory.expense(amount, from: account.info, category: category.info, date: date,
                                                 memo: item.name, key: key, occurrenceId: occurrenceId)
            }
        } catch { throw StoreError.from(error) }
        return try post(entry)
    }

    /// Links an entry that is already posted (e.g. from the bank) to an occurrence
    func match(occurrenceId: UUID, entryId: UUID) throws {
        guard let record = entryRecord(entryId), record.status == .posted else { throw StoreError.notFound }
        if let previous = record.occurrenceId { removePayment(of: record.entry, from: previous) }
        record.occurrenceId = occurrenceId
        record.updatedAt = now()
        applyPayment(of: record.entry, to: occurrenceId)
        try commit()
    }

    func skip(occurrenceId: UUID) throws {
        guard let occ = fetch(OccurrenceRecord.self, #Predicate { $0.id == occurrenceId }).first else { throw StoreError.notFound }
        var o = occ.occurrence
        o.skipped = true
        occ.update(from: o)
        try commit()
    }

    /// Keeps occurrences generated through the horizon; call on launch and when a month starts
    func extendSchedules() {
        for record in fetch(PlannedItemRecord.self) where !record.archived {
            regenerateOccurrences(for: record.item)
        }
        try? commit()
    }

    private func plannedItem(_ id: UUID) -> PlannedItem? {
        fetch(PlannedItemRecord.self, #Predicate { $0.id == id }).first?.item
    }

    private var defaultIncomeCategory: LedgerAccountRecord? {
        fetch(LedgerAccountRecord.self).filter { $0.kind == .income && !$0.archived }.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    private func regenerateOccurrences(for item: PlannedItem) {
        let itemId = item.id
        let records = fetch(OccurrenceRecord.self, #Predicate { $0.itemId == itemId })
        let today = calendar.startOfDay(for: now())
        guard let through = calendar.date(byAdding: .day, value: Self.horizonDays, to: today) else { return }
        // Only today onwards follows the schedule. Earlier occurrences (paid, or
        // unpaid and therefore overdue) are history, and a new bill never invents
        // past payments the person has probably already made.
        let rebuilt = OccurrencePlanner.regenerate(item, existing: records.map(\.occurrence),
                                                   from: today, through: through, calendar: calendar)
        let keep = Set(rebuilt.map(\.id))
        for r in records where !keep.contains(r.id) { context.delete(r) }
        for o in rebuilt {
            if let r = records.first(where: { $0.id == o.id }) { r.update(from: o) } else { context.insert(OccurrenceRecord(o)) }
        }
    }

    private func paymentAmount(of entry: Entry, direction: Direction) -> Money {
        let sheet = entry.lines.filter { account($0.accountId)?.kind.isBalanceSheet == true }.map(\.amount)
        let c = entry.lines.first?.amount.currency ?? currency
        return direction == .outflow
            ? sheet.filter(\.isNegative).sum(c).negated
            : sheet.filter(\.isPositive).sum(c)
    }

    private func applyPayment(of entry: Entry, to occurrenceId: UUID) {
        guard let occ = fetch(OccurrenceRecord.self, #Predicate { $0.id == occurrenceId }).first,
              let item = plannedItem(occ.itemId) else { return }
        var o = occ.occurrence
        o.recordPayment(entryId: entry.id, amount: paymentAmount(of: entry, direction: item.direction))
        occ.update(from: o)
    }

    private func removePayment(of entry: Entry, from occurrenceId: UUID) {
        guard let occ = fetch(OccurrenceRecord.self, #Predicate { $0.id == occurrenceId }).first,
              let item = plannedItem(occ.itemId) else { return }
        var o = occ.occurrence
        o.removePayment(entryId: entry.id, amount: paymentAmount(of: entry, direction: item.direction))
        occ.update(from: o)
    }

    // MARK: - Debts

    /// Where interest and fees are recorded as spending; recreated if it was removed
    var interestCategory: LedgerAccountRecord {
        let raw = AccountKind.expense.rawValue
        let name = "Interest & fees"
        if let existing = fetch(LedgerAccountRecord.self, #Predicate { $0.kindRaw == raw && $0.name == name }).first {
            if existing.archived { existing.archived = false }
            return existing
        }
        let record = LedgerAccountRecord(name: name, kind: .expense, currency: currency, colorHex: "#8E8E93",
                                         icon: "percent", group: "Other", sortOrder: 99)
        context.insert(record)
        return record
    }

    /// Saves a card's or loan's rate and monthly payment, or clears them with nil.
    /// With an account to pay from and a due day, the payment is kept as a monthly
    /// bill, so it's reserved in safe-to-spend and shows in Plan.
    func saveDebtTerms(_ terms: DebtTerms?, for debtId: UUID, paidFrom fundingId: UUID?) throws {
        guard let debt = account(debtId), debt.kind.isLiability else { throw StoreError.notFound }
        if let terms {
            guard terms.monthlyPayment.isPositive else { throw StoreError.invalid("Enter the monthly payment.") }
            guard (0...10_000).contains(terms.annualRateBps) else { throw StoreError.invalid("Enter the yearly rate as a percentage, e.g. 4.5.") }
            if let day = terms.dueDay, !(1...31).contains(day) { throw StoreError.invalid("Choose a due day from 1 to 31.") }
        }
        debt.debtTerms = terms
        debt.updatedAt = now()

        let linked = fetch(PlannedItemRecord.self).filter { $0.debtId == debtId && !$0.archived }
        if let terms, let fundingId, let dueDay = terms.dueDay {
            let start = DebtCalculator.nextDueDate(dueDay: dueDay, onOrAfter: now(), calendar: calendar)
            let item = PlannedItem(id: linked.first?.id ?? UUID(), name: "\(debt.name) payment", direction: .outflow,
                                   amount: terms.monthlyPayment,
                                   schedule: Schedule(start: start, frequency: .monthly(every: 1)),
                                   accountId: fundingId, debtId: debtId)
            if let record = linked.first { record.update(from: item) } else { context.insert(PlannedItemRecord(item)) }
            for extra in linked.dropFirst() { archive(extra) }
            regenerateOccurrences(for: item)
        } else {
            for record in linked { archive(record) }
        }
        context.insert(AuditRecord(action: "debt.terms", subjectId: debtId,
                                   summary: terms.map { "\(debt.name): \($0.annualRatePercent)% a year, \(MoneyFormat.string($0.monthlyPayment)) a month" }
                                       ?? "\(debt.name): terms removed"))
        try commit()
    }

    /// Records a card or loan payment: the paying account drops by the whole amount,
    /// the debt by the principal, and interest and fees count as spending.
    @discardableResult
    func payDebt(_ debtId: UUID, from fundingId: UUID, amount: Money, interest: Money, fees: Money,
                 date: Date, key: UUID, occurrenceId: UUID? = nil) throws -> UUID {
        guard let debt = account(debtId), let funding = account(fundingId) else { throw StoreError.notFound }
        guard amount.isPositive else { throw StoreError.invalid("Enter an amount greater than zero.") }
        guard !interest.isNegative, !fees.isNegative else { throw StoreError.invalid("Interest and fees can't be negative.") }
        guard !(amount < interest + fees) else { throw StoreError.invalid("Interest and fees can't be more than the payment.") }
        let principal = amount - interest - fees
        let owed = snapshot.balance(debtId).negated
        if owed < principal {
            throw StoreError.invalid("That's more than the \(MoneyFormat.string(Money.max(owed, .zero(owed.currency)))) you owe. Lower the payment or the principal.")
        }
        let entry: Entry
        do {
            entry = try EntryFactory.debtPayment(principal: principal, interest: interest, fees: fees,
                                                 from: funding.info, debt: debt.info, interestCategory: interestCategory.info,
                                                 date: date, memo: "\(debt.name) payment", key: key, occurrenceId: occurrenceId)
        } catch { throw StoreError.from(error) }
        return try post(entry)
    }

    /// The parts of a recorded card or loan payment
    struct DebtPaymentParts {
        let debt: LedgerAccountRecord
        let funding: LedgerAccountRecord
        let total: Money
        let principal: Money
        let interest: Money
        let fees: Money
    }

    func debtPaymentParts(_ record: EntryRecord) -> DebtPaymentParts? {
        guard record.kind == .debtPayment else { return nil }
        let entry = record.entry
        guard let fundingLine = entry.lines.first(where: { account($0.accountId)?.kind.isAsset == true }),
              let funding = account(fundingLine.accountId),
              let debtLine = entry.lines.first(where: { account($0.accountId)?.kind.isLiability == true }),
              let debt = account(debtLine.accountId) else { return nil }
        let charges = entry.lines.filter { account($0.accountId)?.kind == .expense }.map(\.amount)
        let zero = Money.zero(fundingLine.amount.currency)
        return DebtPaymentParts(debt: debt, funding: funding, total: fundingLine.amount.negated, principal: debtLine.amount,
                                interest: charges.first ?? zero, fees: charges.dropFirst().sum(zero.currency))
    }

    /// Re-splits a recorded payment with the interest and fees from the lender's statement
    @discardableResult
    func resplitDebtPayment(_ entryId: UUID, interest: Money, fees: Money) throws -> UUID {
        guard let record = entryRecord(entryId), record.status == .posted, let parts = debtPaymentParts(record) else {
            throw StoreError.notFound
        }
        guard !interest.isNegative, !fees.isNegative else { throw StoreError.invalid("Interest and fees can't be negative.") }
        guard !(parts.total < interest + fees) else { throw StoreError.invalid("Interest and fees can't be more than the payment.") }
        let principal = parts.total - interest - fees
        let owedBefore = snapshot.balance(parts.debt.id).negated + parts.principal
        if owedBefore < principal { throw StoreError.invalid("That would pay off more than was owed. Raise the interest.") }
        let entry: Entry
        do {
            entry = try EntryFactory.debtPayment(principal: principal, interest: interest, fees: fees,
                                                 from: parts.funding.info, debt: parts.debt.info,
                                                 interestCategory: interestCategory.info, date: record.date,
                                                 memo: record.memo, key: UUID(), occurrenceId: record.occurrenceId)
        } catch { throw StoreError.from(error) }
        return try replace(entryId, with: entry, notes: record.notes)
    }

    // MARK: - Reserves

    /// Saves money set aside, or a savings goal (a set-aside amount with a target)
    func saveReserve(_ reserve: Reserve) throws {
        guard !reserve.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw StoreError.invalid("Give it a name.") }
        guard !reserve.amount.isNegative else { throw StoreError.invalid("The amount saved can't be negative.") }
        if let target = reserve.target {
            guard target.isPositive else { throw StoreError.invalid("Enter a target greater than zero.") }
        } else {
            guard reserve.amount.isPositive else { throw StoreError.invalid("Enter an amount greater than zero.") }
        }
        try checkFree(reserve.amount, in: reserve.accountId, excluding: reserve.id)
        let id = reserve.id
        if let record = fetch(ReserveRecord.self, #Predicate { $0.id == id }).first {
            record.name = reserve.name
            record.minorUnits = reserve.amount.minorUnits
            record.accountId = reserve.accountId
            record.targetMinor = reserve.target?.minorUnits
            record.targetDate = reserve.targetDate
            record.updatedAt = now()
        } else {
            context.insert(ReserveRecord(reserve))
        }
        context.insert(AuditRecord(action: "reserve.saved", subjectId: reserve.id,
                                   summary: "\(reserve.name): \(MoneyFormat.string(reserve.amount)) set aside"
                                       + (reserve.target.map { " towards \(MoneyFormat.string($0))" } ?? "")))
        try commit()
    }

    /// Adds to a goal. With another account to take it from, the money is also
    /// moved (a transfer); otherwise it's money already in the goal's account.
    func addToGoal(_ id: UUID, amount: Money, from fundingId: UUID?, date: Date, key: UUID) throws {
        guard let record = fetch(ReserveRecord.self, #Predicate { $0.id == id }).first, !record.archived else { throw StoreError.notFound }
        guard record.lastChangeKey != key else { return }
        guard amount.isPositive else { throw StoreError.invalid("Enter an amount greater than zero.") }
        let moving = fundingId != nil && fundingId != record.accountId
        let current = Money(minorUnits: record.minorUnits, currency: record.currency)
        try checkFree(current + amount, in: record.accountId, excluding: id, arriving: moving ? amount : nil)
        if moving, let fundingId, let from = account(fundingId), let to = account(record.accountId) {
            do {
                let entry = try EntryFactory.transfer(amount, from: from.info, to: to.info, date: date,
                                                      memo: "Saving for \(record.name)", key: key)
                insert(entry, notes: "")
            } catch { throw StoreError.from(error) }
        }
        record.minorUnits += amount.minorUnits
        record.lastChangeKey = key
        record.updatedAt = now()
        context.insert(AuditRecord(action: "goal.added", subjectId: id,
                                   summary: "Added \(MoneyFormat.string(amount)) to \(record.name)"))
        try commit()
    }

    /// Takes money out of a goal; it stays in the account and becomes spendable again
    func takeFromGoal(_ id: UUID, amount: Money, key: UUID) throws {
        guard let record = fetch(ReserveRecord.self, #Predicate { $0.id == id }).first, !record.archived else { throw StoreError.notFound }
        guard record.lastChangeKey != key else { return }
        guard amount.isPositive else { throw StoreError.invalid("Enter an amount greater than zero.") }
        guard amount.minorUnits <= record.minorUnits else {
            throw StoreError.invalid("Only \(MoneyFormat.string(Money(minorUnits: record.minorUnits, currency: record.currency))) is saved.")
        }
        record.minorUnits -= amount.minorUnits
        record.lastChangeKey = key
        record.updatedAt = now()
        context.insert(AuditRecord(action: "goal.taken", subjectId: id,
                                   summary: "Took \(MoneyFormat.string(amount)) from \(record.name)"))
        try commit()
    }

    /// Money set aside can't be more than the account holds, net of other set-aside money
    private func checkFree(_ amount: Money, in accountId: UUID, excluding reserveId: UUID, arriving: Money? = nil) throws {
        let snapshot = self.snapshot
        let free = snapshot.freeToSetAside(in: accountId, excluding: reserveId) + (arriving ?? .zero(amount.currency))
        if free < amount {
            let name = snapshot.account(accountId)?.name ?? "The account"
            throw StoreError.invalid("\(name) only has \(MoneyFormat.string(Money.max(free, .zero(amount.currency)))) that isn't already set aside.")
        }
    }

    func releaseReserve(_ id: UUID) throws {
        guard let record = fetch(ReserveRecord.self, #Predicate { $0.id == id }).first else { throw StoreError.notFound }
        record.archived = true
        record.updatedAt = now()
        context.insert(AuditRecord(action: "reserve.released", subjectId: id, summary: "Released \(record.name)"))
        try commit()
    }

    // MARK: - Settings

    func updateSettings(_ change: (SettingsRecord) -> Void) throws {
        change(settings)
        settings.updatedAt = now()
        try commit()
    }

    /// Deletes every record on this device. Asked for explicitly by the person.
    func eraseAllData() throws {
        for type in Schema1.models { try context.delete(model: type) }
        try context.save()
        ensureSettingsAndSystemAccounts()
        revision += 1
    }

    // MARK: -

    func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            revision += 1
            throw StoreError.invalid("Couldn't save. Nothing was changed, please try again.")
        }
    }
}
