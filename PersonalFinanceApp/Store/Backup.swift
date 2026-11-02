//
//  Backup.swift
//  Nokael Money
//
//  A complete copy of everything on the device as one JSON file, and
//  restoring from it. Restoring checks the whole file first (format, every
//  entry balances, every reference exists) and only then replaces the data,
//  after saving a copy of what was there.
//

import Foundation
import SwiftData
import NokaelCore

struct Backup: Codable {
    static let format = "nokael-money-backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var createdAt: Date
    var appVersion: String
    var settings: SettingsDTO
    var accounts: [AccountDTO]
    var entries: [EntryDTO]
    var allocations: [AllocationDTO]
    var plannedItems: [PlannedItemDTO]
    var occurrences: [OccurrenceDTO]
    var reserves: [ReserveDTO]
    var audit: [AuditDTO]

    /// What a restore would bring back, for the confirmation screen
    var summary: String {
        let real = accounts.filter { AccountKind(rawValue: $0.kindRaw)?.isBalanceSheet == true && !$0.archived }.count
        let posted = entries.filter { $0.statusRaw == EntryStatus.posted.rawValue && $0.kindRaw != EntryKind.openingBalance.rawValue }.count
        let bills = plannedItems.filter { !$0.archived }.count
        let goals = reserves.filter { !$0.archived }.count
        return [plural(real, "account"), plural(posted, "transaction"), plural(bills, "bill or income", "bills or income"),
                plural(goals, "goal or saving", "goals or savings")].joined(separator: ", ")
    }

    private func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: return "This file isn't a Nokael Money backup."
        case .newerVersion: return "This backup was made by a newer version of Nokael Money. Update the app, then try again."
        case .damaged(let detail): return "This backup is damaged, so nothing was changed. (\(detail))"
        }
    }
}

// MARK: - Records ⇄ backup

struct SettingsDTO: Codable {
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
    var lastBackupAt: Date?
    // Optional so backups saved before these existed still restore
    var bankRegion: String?
    var bankSenders: [String]?
    var pinnedCategoryIds: [UUID]?
    var displayName: String?
    var statementFindingsData: Data?
    var dismissedFindings: [String]?
    var unfinishedLoans: [UUID]?

    init(_ r: SettingsRecord) {
        currency = r.currency; localeIdentifier = r.localeIdentifier; firstWeekday = r.firstWeekday
        bufferMinor = r.bufferMinor; staleAfterDays = r.staleAfterDays; onboardingStep = r.onboardingStep
        onboardingDone = r.onboardingDone; payFrequencyData = r.payFrequencyData; lastUsedAccountId = r.lastUsedAccountId
        biometricLock = r.biometricLock; lastBackupAt = r.lastBackupAt
        bankRegion = r.bankRegion; bankSenders = r.bankSenders; pinnedCategoryIds = r.pinnedCategoryIds
        displayName = r.displayName
        statementFindingsData = r.statementFindingsData; dismissedFindings = r.dismissedFindings
        unfinishedLoans = r.unfinishedLoans
    }

    func apply(to r: SettingsRecord) {
        r.currency = currency; r.localeIdentifier = localeIdentifier; r.firstWeekday = firstWeekday
        r.bufferMinor = bufferMinor; r.staleAfterDays = staleAfterDays; r.onboardingStep = onboardingStep
        r.onboardingDone = onboardingDone; r.payFrequencyData = payFrequencyData; r.lastUsedAccountId = lastUsedAccountId
        r.biometricLock = biometricLock; r.lastBackupAt = lastBackupAt
        r.bankRegion = bankRegion; r.bankSenders = bankSenders ?? []; r.pinnedCategoryIds = pinnedCategoryIds ?? []
        r.displayName = displayName ?? ""
        r.statementFindingsData = statementFindingsData; r.dismissedFindings = dismissedFindings ?? []
        r.unfinishedLoans = unfinishedLoans ?? []
    }
}

struct AccountDTO: Codable {
    var id: UUID
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
    var debtRateBps: Int?
    var debtPaymentMinor: Int64?
    var debtDueDay: Int?
    /// Added later; older backups have none. An unknown category falls back to Loan payments.
    var debtCategoryId: UUID?
    var systemRole: String?
    var owedBackBy: Date?
    var accountNumber: String?
    var group: String
    var policyRaw: String
    var reserveInSafeToSpend: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ r: LedgerAccountRecord) {
        id = r.id; name = r.name; kindRaw = r.kindRaw; currency = r.currency; includeInNetWorth = r.includeInNetWorth
        spendable = r.spendable; onBudget = r.onBudget; archived = r.archived; isSystem = r.isSystem; sortOrder = r.sortOrder
        colorHex = r.colorHex; icon = r.icon; institution = r.institution; lastReconciledAt = r.lastReconciledAt
        debtRateBps = r.debtRateBps; debtPaymentMinor = r.debtPaymentMinor; debtDueDay = r.debtDueDay
        debtCategoryId = r.debtCategoryId; systemRole = r.systemRole; owedBackBy = r.owedBackBy
        accountNumber = r.accountNumber; group = r.group; policyRaw = r.policyRaw; reserveInSafeToSpend = r.reserveInSafeToSpend
        createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    func record() -> LedgerAccountRecord {
        let r = LedgerAccountRecord(id: id, name: name, kind: AccountKind(rawValue: kindRaw) ?? .otherAsset, currency: currency)
        r.kindRaw = kindRaw; r.includeInNetWorth = includeInNetWorth; r.spendable = spendable; r.onBudget = onBudget
        r.archived = archived; r.isSystem = isSystem; r.sortOrder = sortOrder; r.colorHex = colorHex; r.icon = icon
        r.institution = institution; r.lastReconciledAt = lastReconciledAt; r.debtRateBps = debtRateBps
        r.debtPaymentMinor = debtPaymentMinor; r.debtDueDay = debtDueDay; r.group = group; r.policyRaw = policyRaw
        r.reserveInSafeToSpend = reserveInSafeToSpend; r.createdAt = createdAt; r.updatedAt = updatedAt
        r.debtCategoryId = debtCategoryId; r.systemRole = systemRole; r.owedBackBy = owedBackBy
        r.accountNumber = accountNumber
        return r
    }
}

struct LineDTO: Codable {
    var accountId: UUID
    var minorUnits: Int64
    var currency: String
}

struct EntryDTO: Codable {
    var id: UUID
    var kindRaw: String
    var date: Date
    var statusRaw: String
    var clearedRaw: String
    var memo: String
    var notes: String
    var idempotencyKey: UUID
    var occurrenceId: UUID?
    var replacesId: UUID?
    var lines: [LineDTO]
    var createdAt: Date
    var updatedAt: Date
    var dismissedOccurrenceIds: [UUID]?

    init(_ r: EntryRecord) {
        id = r.id; kindRaw = r.kindRaw; date = r.date; statusRaw = r.statusRaw; clearedRaw = r.clearedRaw
        memo = r.memo; notes = r.notes; idempotencyKey = r.idempotencyKey; occurrenceId = r.occurrenceId
        replacesId = r.replacesId; createdAt = r.createdAt; updatedAt = r.updatedAt
        dismissedOccurrenceIds = r.dismissedOccurrenceIds.isEmpty ? nil : r.dismissedOccurrenceIds
        lines = r.lines.map { LineDTO(accountId: $0.accountId, minorUnits: $0.minorUnits, currency: $0.currency) }
    }

    /// As a core entry, for checking it balances
    var entry: Entry {
        Entry(id: id, kind: EntryKind(rawValue: kindRaw) ?? .adjustment, date: date, memo: memo,
              lines: lines.map { Line(accountId: $0.accountId, amount: Money(minorUnits: $0.minorUnits, currency: $0.currency)) },
              idempotencyKey: idempotencyKey, occurrenceId: occurrenceId)
    }
}

struct AllocationDTO: Codable {
    var id: UUID
    var categoryId: UUID
    var month: String
    var minorUnits: Int64
    var currency: String
    var moveId: UUID?
    var note: String
    var createdAt: Date

    init(_ r: AllocationRecord) {
        id = r.id; categoryId = r.categoryId; month = r.month; minorUnits = r.minorUnits; currency = r.currency
        moveId = r.moveId; note = r.note; createdAt = r.createdAt
    }

    func record() -> AllocationRecord {
        let r = AllocationRecord(categoryId: categoryId, month: month, amount: Money(minorUnits: minorUnits, currency: currency),
                                 moveId: moveId, note: note)
        r.id = id; r.createdAt = createdAt
        return r
    }
}

struct PlannedItemDTO: Codable {
    var id: UUID
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

    init(_ r: PlannedItemRecord) {
        id = r.id; name = r.name; directionRaw = r.directionRaw; minorUnits = r.minorUnits; currency = r.currency
        isEstimate = r.isEstimate; scheduleStart = r.scheduleStart; frequencyData = r.frequencyData; scheduleEnd = r.scheduleEnd
        accountId = r.accountId; categoryId = r.categoryId; debtId = r.debtId; autopay = r.autopay
        reminderDaysBefore = r.reminderDaysBefore; archived = r.archived; createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    func record() -> PlannedItemRecord {
        let item = PlannedItem(id: id, name: name, direction: Direction(rawValue: directionRaw) ?? .outflow,
                               amount: Money(minorUnits: minorUnits, currency: currency), isEstimate: isEstimate,
                               schedule: Schedule(start: scheduleStart, frequency: .monthly(every: 1), end: scheduleEnd),
                               accountId: accountId, categoryId: categoryId, debtId: debtId)
        let r = PlannedItemRecord(item)
        r.directionRaw = directionRaw; r.frequencyData = frequencyData; r.autopay = autopay
        r.reminderDaysBefore = reminderDaysBefore; r.archived = archived; r.createdAt = createdAt; r.updatedAt = updatedAt
        return r
    }
}

struct OccurrenceDTO: Codable {
    var id: UUID
    var itemId: UUID
    var dueDate: Date
    var expectedMinor: Int64
    var paidMinor: Int64
    var currency: String
    var isEstimate: Bool
    var paidEntryIds: [UUID]
    var skipped: Bool
    var updatedAt: Date
    var settledEstimateMinor: Int64?

    init(_ r: OccurrenceRecord) {
        id = r.id; itemId = r.itemId; dueDate = r.dueDate; expectedMinor = r.expectedMinor; paidMinor = r.paidMinor
        currency = r.currency; isEstimate = r.isEstimate; paidEntryIds = r.paidEntryIds; skipped = r.skipped; updatedAt = r.updatedAt
        settledEstimateMinor = r.settledEstimateMinor
    }

    func record() -> OccurrenceRecord {
        let r = OccurrenceRecord(Occurrence(id: id, itemId: itemId, dueDate: dueDate,
                                            expected: Money(minorUnits: expectedMinor, currency: currency), isEstimate: isEstimate,
                                            paid: Money(minorUnits: paidMinor, currency: currency), paidEntryIds: paidEntryIds,
                                            skipped: skipped,
                                            settledEstimate: settledEstimateMinor.map { Money(minorUnits: $0, currency: currency) }))
        r.updatedAt = updatedAt
        return r
    }
}

struct ReserveDTO: Codable {
    var id: UUID
    var name: String
    var minorUnits: Int64
    var currency: String
    var accountId: UUID
    var targetMinor: Int64?
    var targetDate: Date?
    var lastChangeKey: UUID?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ r: ReserveRecord) {
        id = r.id; name = r.name; minorUnits = r.minorUnits; currency = r.currency; accountId = r.accountId
        targetMinor = r.targetMinor; targetDate = r.targetDate; lastChangeKey = r.lastChangeKey; archived = r.archived
        createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    func record() -> ReserveRecord {
        let r = ReserveRecord(Reserve(id: id, name: name, amount: Money(minorUnits: minorUnits, currency: currency),
                                      accountId: accountId, target: targetMinor.map { Money(minorUnits: $0, currency: currency) },
                                      targetDate: targetDate))
        r.lastChangeKey = lastChangeKey; r.archived = archived; r.createdAt = createdAt; r.updatedAt = updatedAt
        return r
    }
}

struct AuditDTO: Codable {
    var id: UUID
    var date: Date
    var action: String
    var subjectId: UUID
    var summary: String
    var reason: String?

    init(_ r: AuditRecord) {
        id = r.id; date = r.date; action = r.action; subjectId = r.subjectId; summary = r.summary; reason = r.reason
    }

    func record() -> AuditRecord {
        let r = AuditRecord(action: action, subjectId: subjectId, summary: summary, reason: reason)
        r.id = id; r.date = date
        return r
    }
}

// MARK: - Store

extension LedgerStore {
    func makeBackup() -> Backup {
        Backup(format: Backup.format, version: Backup.currentVersion, createdAt: now(),
               appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
               settings: SettingsDTO(settings),
               accounts: fetch(LedgerAccountRecord.self).map(AccountDTO.init),
               entries: fetch(EntryRecord.self).map(EntryDTO.init),
               allocations: fetch(AllocationRecord.self).map(AllocationDTO.init),
               plannedItems: fetch(PlannedItemRecord.self).map(PlannedItemDTO.init),
               occurrences: fetch(OccurrenceRecord.self).map(OccurrenceDTO.init),
               reserves: fetch(ReserveRecord.self).map(ReserveDTO.init),
               audit: fetch(AuditRecord.self).map(AuditDTO.init))
    }

    /// The backup as a file's contents. Dates keep full precision so schedules
    /// and history line up exactly after a restore.
    func backupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(makeBackup())
    }

    /// Notes that a backup was saved, for the reminder on Home
    func markBackedUp() {
        try? updateSettings { $0.lastBackupAt = now() }
    }

    /// Reads and fully checks a backup without changing anything
    static func readBackup(_ data: Data) throws -> Backup {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == Backup.format else {
            throw BackupError.notABackup
        }
        guard let version = header.version, version <= Backup.currentVersion else { throw BackupError.newerVersion }
        let backup: Backup
        do { backup = try JSONDecoder().decode(Backup.self, from: data) } catch {
            throw BackupError.damaged("unreadable")
        }

        func unique<T>(_ items: [T], _ id: (T) -> UUID, _ what: String) throws -> Set<UUID> {
            let ids = Set(items.map(id))
            guard ids.count == items.count else { throw BackupError.damaged("duplicate \(what)") }
            return ids
        }
        let accounts = try unique(backup.accounts, \.id, "accounts")
        _ = try unique(backup.entries, \.id, "entries")
        _ = try unique(backup.entries, \.idempotencyKey, "entries")
        let items = try unique(backup.plannedItems, \.id, "bills")
        _ = try unique(backup.occurrences, \.id, "due dates")
        _ = try unique(backup.reserves, \.id, "savings")
        guard backup.accounts.filter({ $0.kindRaw == AccountKind.equity.rawValue }).count == 1 else {
            throw BackupError.damaged("opening balances account")
        }
        for e in backup.entries {
            guard e.lines.allSatisfy({ accounts.contains($0.accountId) }) else { throw BackupError.damaged("unknown account in an entry") }
            do { try EntryFactory.validate(e.entry) } catch { throw BackupError.damaged("an entry doesn't balance") }
        }
        for a in backup.allocations where !accounts.contains(a.categoryId) { throw BackupError.damaged("unknown category in budget") }
        for o in backup.occurrences where !items.contains(o.itemId) { throw BackupError.damaged("unknown bill") }
        for r in backup.reserves where !accounts.contains(r.accountId) { throw BackupError.damaged("unknown account in savings") }
        for p in backup.plannedItems {
            for ref in [p.accountId, p.categoryId, p.debtId].compactMap({ $0 }) where !accounts.contains(ref) {
                throw BackupError.damaged("unknown account in a bill")
            }
        }
        return backup
    }

    /// Replaces everything on the device with a checked backup. A copy of the
    /// current data is saved first, and its location returned.
    @discardableResult
    func restore(_ backup: Backup) throws -> URL? {
        let safetyCopy = try? saveSafetyCopy()
        let previous = try? LedgerStore.readBackup(try backupData())
        // The old records must be gone before records with the same IDs are
        // inserted, or the two get merged and some of the backup is lost
        for type in Schema1.models { try context.delete(model: type) }
        try context.save()
        do {
            try insertAll(backup)
        } catch {
            // Put back what was there; the file copy remains if even that fails
            context.rollback()
            if let previous {
                for type in Schema1.models { try? context.delete(model: type) }
                try? context.save()
                try? insertAll(previous, note: false)
            }
            throw error
        }
        extendSchedules()
        return safetyCopy
    }

    private func insertAll(_ backup: Backup, note: Bool = true) throws {
        let settings = SettingsRecord(currency: backup.settings.currency, localeIdentifier: backup.settings.localeIdentifier)
        backup.settings.apply(to: settings)
        context.insert(settings)
        for a in backup.accounts { context.insert(a.record()) }
        for e in backup.entries {
            let record = EntryRecord(from: e.entry, notes: e.notes, replacesId: e.replacesId)
            record.statusRaw = e.statusRaw
            record.clearedRaw = e.clearedRaw
            record.createdAt = e.createdAt
            record.updatedAt = e.updatedAt
            record.dismissedOccurrenceIds = e.dismissedOccurrenceIds ?? []
            context.insert(record)
            for l in e.lines {
                let line = LineRecord(Line(accountId: l.accountId, amount: Money(minorUnits: l.minorUnits, currency: l.currency)))
                context.insert(line)
                line.entry = record
            }
        }
        for a in backup.allocations { context.insert(a.record()) }
        for p in backup.plannedItems { context.insert(p.record()) }
        for o in backup.occurrences { context.insert(o.record()) }
        for r in backup.reserves { context.insert(r.record()) }
        for a in backup.audit { context.insert(a.record()) }
        if note {
            context.insert(AuditRecord(action: "data.restored", subjectId: UUID(),
                                       summary: "Restored a backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))"))
        }
        try commit()
    }

    /// Writes the current data to the app's Documents folder before it's replaced
    private func saveSafetyCopy() throws -> URL {
        let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Before restore \(Self.fileStamp(now())).json")
        try backupData().write(to: url, options: .atomic)
        return url
    }

    static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: date)
    }
}
