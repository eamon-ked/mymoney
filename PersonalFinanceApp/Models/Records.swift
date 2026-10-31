//
//  Records.swift
//  Nokael Money
//
//  SwiftData storage. Records mirror NokaelCore types and are converted to
//  them for every calculation; nothing here does money math. Every record has
//  a stable UUID and an updatedAt, and nothing is hard-deleted, so sync can be
//  added later without reshaping data.
//

import Foundation
import SwiftData
import NokaelCore

/// Accounts and categories share one table: both are ledger accounts
@Model
final class LedgerAccountRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var currency: String
    var includeInNetWorth: Bool
    var spendable: Bool
    var onBudget: Bool
    var archived: Bool
    var isSystem: Bool
    var sortOrder: Int
    var colorHex: String
    var icon: String
    var institution: String?
    var lastReconciledAt: Date?
    // Debt terms (cards and loans only)
    var debtRateBps: Int?
    var debtPaymentMinor: Int64?
    var debtDueDay: Int?
    /// Loans only: the spending category its payments count under; nil means Loan payments
    var debtCategoryId: UUID? = nil
    /// Built-in categories only ("loanPayments", "interest"), so renaming one doesn't create another
    var systemRole: String? = nil
    // Category settings (expense categories only)
    var group: String
    var policyRaw: String
    /// Keep this category's unspent budget out of safe-to-spend
    var reserveInSafeToSpend: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, kind: AccountKind, currency: String, colorHex: String = "#3A7BD5",
         icon: String = "", institution: String? = nil, group: String = "", isSystem: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.currency = currency
        self.includeInNetWorth = kind.isBalanceSheet
        self.spendable = kind.defaultSpendable
        self.onBudget = kind.defaultOnBudget
        self.archived = false
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.icon = icon
        self.institution = institution
        self.lastReconciledAt = nil
        self.group = group
        self.policyRaw = RolloverPolicy.rollover.rawValue
        self.reserveInSafeToSpend = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: AccountKind { AccountKind(rawValue: kindRaw) ?? .otherAsset }
    var policy: RolloverPolicy {
        get { RolloverPolicy(rawValue: policyRaw) ?? .rollover }
        set { policyRaw = newValue.rawValue }
    }

    var debtTerms: DebtTerms? {
        get {
            guard kind.isLiability, let debtRateBps, let debtPaymentMinor else { return nil }
            return DebtTerms(annualRateBps: debtRateBps, monthlyPayment: Money(minorUnits: debtPaymentMinor, currency: currency),
                             dueDay: debtDueDay)
        }
        set {
            debtRateBps = newValue?.annualRateBps
            debtPaymentMinor = newValue?.monthlyPayment.minorUnits
            debtDueDay = newValue?.dueDay
        }
    }

    var info: AccountInfo {
        AccountInfo(id: id, name: name, kind: kind, currency: currency, includeInNetWorth: includeInNetWorth,
                    spendable: spendable, onBudget: onBudget, archived: archived)
    }
}

@Model
final class EntryRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var date: Date
    var statusRaw: String
    var clearedRaw: String
    /// What the person called it ("Carrefour", "October salary")
    var memo: String
    var notes: String
    /// One per save attempt; a repeated key never creates a second entry
    @Attribute(.unique) var idempotencyKey: UUID
    var occurrenceId: UUID?
    /// The entry this one replaced when edited (the original is kept, voided)
    var replacesId: UUID?
    @Relationship(deleteRule: .cascade, inverse: \LineRecord.entry) var lines: [LineRecord] = []
    var createdAt: Date
    var updatedAt: Date
    /// Where an automatic entry came from (`Capture.Source`); nil when typed in
    var sourceRaw: String? = nil
    /// The Wallet card name or last four digits it arrived with
    var cardHint: String? = nil
    /// Saved automatically and not yet looked at
    var needsReview: Bool = false
    /// Bills the person said this isn't a payment for, so they aren't suggested again.
    /// An edit makes a new entry, which is looked at afresh.
    var dismissedOccurrenceIds: [UUID] = []

    init(from entry: Entry, notes: String = "", replacesId: UUID? = nil) {
        self.id = entry.id
        self.kindRaw = entry.kind.rawValue
        self.date = entry.date
        self.statusRaw = entry.status.rawValue
        self.clearedRaw = entry.cleared.rawValue
        self.memo = entry.memo
        self.notes = notes
        self.idempotencyKey = entry.idempotencyKey
        self.occurrenceId = entry.occurrenceId
        self.replacesId = replacesId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .adjustment }
    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .posted }
        set { statusRaw = newValue.rawValue }
    }
    var cleared: ClearedState {
        get { ClearedState(rawValue: clearedRaw) ?? .uncleared }
        set { clearedRaw = newValue.rawValue }
    }
    var source: Capture.Source? { sourceRaw.flatMap(Capture.Source.init(rawValue:)) }

    var entry: Entry {
        Entry(id: id, kind: kind, date: date, status: status, cleared: cleared, memo: memo,
              lines: lines.map { Line(accountId: $0.accountId, amount: Money(minorUnits: $0.minorUnits, currency: $0.currency)) },
              idempotencyKey: idempotencyKey, occurrenceId: occurrenceId)
    }
}

@Model
final class LineRecord {
    var accountId: UUID
    var minorUnits: Int64
    var currency: String
    var entry: EntryRecord?

    init(_ line: Line) {
        self.accountId = line.accountId
        self.minorUnits = line.amount.minorUnits
        self.currency = line.amount.currency
    }
}

/// A change to a category's plan for a month. Kept as a history of changes,
/// so a month's allocation is always explainable.
@Model
final class AllocationRecord {
    @Attribute(.unique) var id: UUID
    var categoryId: UUID
    var month: String
    var minorUnits: Int64
    var currency: String
    /// Set on both halves of a move between categories
    var moveId: UUID?
    var note: String
    var createdAt: Date

    init(categoryId: UUID, month: String, amount: Money, moveId: UUID? = nil, note: String = "") {
        self.id = UUID()
        self.categoryId = categoryId
        self.month = month
        self.minorUnits = amount.minorUnits
        self.currency = amount.currency
        self.moveId = moveId
        self.note = note
        self.createdAt = Date()
    }

    var allocation: Allocation {
        Allocation(categoryId: categoryId, month: month, amount: Money(minorUnits: minorUnits, currency: currency))
    }
}

@Model
final class PlannedItemRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var directionRaw: String
    var minorUnits: Int64
    var currency: String
    var isEstimate: Bool
    var scheduleStart: Date
    var frequencyData: Data
    var scheduleEnd: Date?
    var accountId: UUID?
    var categoryId: UUID?
    var debtId: UUID?
    var autopay: Bool
    var reminderDaysBefore: Int
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ item: PlannedItem) {
        self.id = item.id
        self.name = item.name
        self.directionRaw = item.direction.rawValue
        self.minorUnits = item.amount.minorUnits
        self.currency = item.amount.currency
        self.isEstimate = item.isEstimate
        self.scheduleStart = item.schedule.start
        self.frequencyData = (try? JSONEncoder().encode(item.schedule.frequency)) ?? Data()
        self.scheduleEnd = item.schedule.end
        self.accountId = item.accountId
        self.categoryId = item.categoryId
        self.debtId = item.debtId
        self.autopay = false
        self.reminderDaysBefore = 2
        self.archived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func update(from item: PlannedItem) {
        name = item.name
        directionRaw = item.direction.rawValue
        minorUnits = item.amount.minorUnits
        currency = item.amount.currency
        isEstimate = item.isEstimate
        scheduleStart = item.schedule.start
        frequencyData = (try? JSONEncoder().encode(item.schedule.frequency)) ?? frequencyData
        scheduleEnd = item.schedule.end
        accountId = item.accountId
        categoryId = item.categoryId
        debtId = item.debtId
        updatedAt = Date()
    }

    var item: PlannedItem {
        let frequency = (try? JSONDecoder().decode(Frequency.self, from: frequencyData)) ?? .monthly(every: 1)
        return PlannedItem(id: id, name: name, direction: Direction(rawValue: directionRaw) ?? .outflow,
                           amount: Money(minorUnits: minorUnits, currency: currency), isEstimate: isEstimate,
                           schedule: Schedule(start: scheduleStart, frequency: frequency, end: scheduleEnd),
                           accountId: accountId, categoryId: categoryId, debtId: debtId)
    }
}

@Model
final class OccurrenceRecord {
    @Attribute(.unique) var id: UUID
    var itemId: UUID
    var dueDate: Date
    var expectedMinor: Int64
    var paidMinor: Int64
    var currency: String
    var isEstimate: Bool
    var paidEntryIds: [UUID]
    var skipped: Bool
    var updatedAt: Date
    /// The estimate a payment settled, so voiding it can put the estimate back
    var settledEstimateMinor: Int64? = nil

    init(_ o: Occurrence) {
        self.id = o.id
        self.itemId = o.itemId
        self.dueDate = o.dueDate
        self.expectedMinor = o.expected.minorUnits
        self.paidMinor = o.paid.minorUnits
        self.currency = o.expected.currency
        self.isEstimate = o.isEstimate
        self.paidEntryIds = o.paidEntryIds
        self.skipped = o.skipped
        self.updatedAt = Date()
        self.settledEstimateMinor = o.settledEstimate?.minorUnits
    }

    func update(from o: Occurrence) {
        dueDate = o.dueDate
        expectedMinor = o.expected.minorUnits
        paidMinor = o.paid.minorUnits
        isEstimate = o.isEstimate
        paidEntryIds = o.paidEntryIds
        skipped = o.skipped
        settledEstimateMinor = o.settledEstimate?.minorUnits
        updatedAt = Date()
    }

    var occurrence: Occurrence {
        Occurrence(id: id, itemId: itemId, dueDate: dueDate, expected: Money(minorUnits: expectedMinor, currency: currency),
                   isEstimate: isEstimate, paid: Money(minorUnits: paidMinor, currency: currency),
                   paidEntryIds: paidEntryIds, skipped: skipped,
                   settledEstimate: settledEstimateMinor.map { Money(minorUnits: $0, currency: currency) })
    }
}

@Model
final class ReserveRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var minorUnits: Int64
    var currency: String
    var accountId: UUID
    // Savings goal (optional)
    var targetMinor: Int64?
    var targetDate: Date?
    /// The last add/take-out request, so a double tap only counts once
    var lastChangeKey: UUID?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ r: Reserve) {
        self.id = r.id
        self.name = r.name
        self.minorUnits = r.amount.minorUnits
        self.currency = r.amount.currency
        self.accountId = r.accountId
        self.targetMinor = r.target?.minorUnits
        self.targetDate = r.targetDate
        self.archived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var reserve: Reserve {
        Reserve(id: id, name: name, amount: Money(minorUnits: minorUnits, currency: currency), accountId: accountId,
                target: targetMinor.map { Money(minorUnits: $0, currency: currency) }, targetDate: targetDate)
    }
}

/// What changed, when and why: edits, voids, reconciliations, deletions
@Model
final class AuditRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var action: String
    var subjectId: UUID
    var summary: String
    var reason: String?

    init(action: String, subjectId: UUID, summary: String, reason: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.action = action
        self.subjectId = subjectId
        self.summary = summary
        self.reason = reason
    }
}

/// One row of app-wide preferences and onboarding progress
@Model
final class SettingsRecord {
    var currency: String
    var localeIdentifier: String
    var firstWeekday: Int
    var bufferMinor: Int64
    var staleAfterDays: Int
    var onboardingStep: Int
    var onboardingDone: Bool
    var payFrequencyData: Data?
    var lastUsedAccountId: UUID?
    var biometricLock: Bool
    /// When a backup file was last saved, for the reminder on Home
    var lastBackupAt: Date?
    var updatedAt: Date
    /// Country whose banks are suggested for SMS capture; nil follows the phone
    var bankRegion: String? = nil
    /// SMS senders the person chose; empty accepts any message that reads as a transaction
    var bankSenders: [String] = []
    /// Budget categories shown on Home, in the order they were pinned
    var pinnedCategoryIds: [UUID] = []
    /// The person's first name, for Home's greeting; empty until they give it
    var displayName: String = ""

    init(currency: String = "AED", localeIdentifier: String = "en_AE") {
        self.currency = currency
        self.localeIdentifier = localeIdentifier
        self.firstWeekday = 2 // Monday
        self.bufferMinor = 0
        self.staleAfterDays = 30
        self.onboardingStep = 0
        self.onboardingDone = false
        self.payFrequencyData = nil
        self.lastUsedAccountId = nil
        self.biometricLock = false
        self.updatedAt = Date()
    }

    var buffer: Money { Money(minorUnits: bufferMinor, currency: currency) }
    var locale: Locale { Locale(identifier: localeIdentifier) }
}

/// A Wallet card or card number the person tied to one of their accounts
@Model
final class CardLinkRecord {
    @Attribute(.unique) var hint: String
    var accountId: UUID
    var createdAt: Date

    init(hint: String, accountId: UUID) {
        self.hint = CardLinkRecord.key(hint)
        self.accountId = accountId
        self.createdAt = Date()
    }

    /// "ENBD Visa " and "enbd visa" are the same card
    static func key(_ hint: String) -> String {
        hint.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum Schema1 {
    // New models and properties with defaults migrate on their own
    static let models: [any PersistentModel.Type] = [
        LedgerAccountRecord.self, EntryRecord.self, LineRecord.self, AllocationRecord.self,
        PlannedItemRecord.self, OccurrenceRecord.self, ReserveRecord.self, AuditRecord.self, SettingsRecord.self,
        CardLinkRecord.self
    ]
}
