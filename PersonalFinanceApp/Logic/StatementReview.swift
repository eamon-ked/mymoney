//
//  StatementReview.swift
//  Nokael Money
//
//  One statement import, from the file to the entries it adds: reading the
//  CSV, recognising rows already recorded, suggesting where each new row goes
//  and adding the chosen ones. The screen only shows it and passes on taps.
//

import Foundation
import CryptoKit
import NokaelCore

@MainActor
@Observable
final class StatementReview {
    typealias Target = LedgerStore.ImportedRow.Target

    /// One choice for a row, as a menu shows it
    struct Option: Identifiable {
        let target: Target
        let title: String
        let symbol: String
        var id: Target { target }
    }

    let accountId: UUID
    @ObservationIgnored private let store: LedgerStore

    private(set) var fileName = ""
    private(set) var fileText: String?
    private(set) var rows: [StatementRow] = []
    /// Row id → the entry already recorded for it
    private(set) var matched: [Int: UUID] = [:]
    var targets: [Int: Target] = [:]
    var skipped: Set<Int> = []
    /// Card statements often list purchases without a minus sign
    var flipSigns = false {
        didSet { if flipSigns != oldValue { parse() } }
    }
    var error: String?
    /// How many entries were added; set once Add is done
    private(set) var added: Int?
    /// Rows still waiting for a suggested category
    private(set) var suggesting = 0
    @ObservationIgnored private var suggestTask: Task<Void, Never>?

    init(accountId: UUID, store: LedgerStore) {
        self.accountId = accountId
        self.store = store
    }

    private var snapshot: FinanceSnapshot { store.snapshot }
    var account: LedgerAccountRecord? { snapshot.account(accountId) }

    /// Rows not recorded yet
    var inbox: [StatementRow] { rows.filter { matched[$0.id] == nil } }
    /// Ticked, with a choice: what Add adds
    var ready: [StatementRow] { inbox.filter { !skipped.contains($0.id) && targets[$0.id] != nil } }
    /// Ticked, still without a choice
    var unsorted: [StatementRow] { inbox.filter { !skipped.contains($0.id) && targets[$0.id] == nil } }
    var allSelected: Bool { inbox.allSatisfy { !skipped.contains($0.id) } }

    /// "3 ready · 1 needs a category · 2 left out"
    var summary: String {
        let left = inbox.count - ready.count - unsorted.count
        var parts = ["\(ready.count) ready"]
        if !unsorted.isEmpty { parts.append("\(unsorted.count) need a category") }
        if left > 0 { parts.append("\(left) left out") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Reading

    func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            error = "Couldn't read that file."
            return
        }
        load(text, named: url.lastPathComponent)
    }

    func load(_ text: String, named name: String) {
        fileName = name
        fileText = text
        // Card statements usually list purchases as positive numbers
        var flip = false
        if account?.kind.isLiability == true,
           let raw = try? StatementImport.read(text, currency: store.currency, calendar: store.calendar) {
            flip = raw.filter(\.amount.isPositive).count > raw.count / 2
        }
        if flip != flipSigns { flipSigns = flip } else { parse() }
    }

    private func parse() {
        guard let fileText else { return }
        do {
            rows = try StatementImport.read(fileText, currency: store.currency, flipSigns: flipSigns, calendar: store.calendar)
            error = nil
        } catch {
            rows = []
            matched = [:]
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
            self.fileText = nil
            return
        }
        let recorded = snapshot.entries(touching: accountId).filter { $0.kind != .openingBalance }.map { record in
            RecordedMovement(entryId: record.id, date: record.date,
                             amount: record.lines.filter { $0.accountId == accountId }
                                .map { Money(minorUnits: $0.minorUnits, currency: $0.currency) }.sum(store.currency))
        }
        matched = StatementImport.match(rows, with: recorded, calendar: store.calendar)
        suggest()
    }

    /// A bill it pays, else a transfer naming another account, else the category used last time for that shop
    private func suggest() {
        let history: [(memo: String, categoryId: UUID)] = snapshot.entries().compactMap { record in
            guard let c = record.lines.lazy.compactMap({ self.snapshot.account($0.accountId) }).first(where: { $0.kind.isCategory })
            else { return nil }
            return (record.memo, c.id)
        }
        let others = snapshot.accounts.filter { $0.id != accountId }.map { (id: $0.id, name: $0.name) }
        let loans = snapshot.accounts.filter { $0.kind == .loan && !$0.archived }.map { (id: $0.id, name: $0.name) }
        var next: [Int: Target] = [:]
        var billsTaken: Set<UUID> = []
        for row in inbox {
            if let occ = StatementImport.bill(for: row, occurrences: snapshot.occurrences, items: snapshot.items,
                                              accountId: accountId, calendar: store.calendar),
               !billsTaken.contains(occ.id) {
                billsTaken.insert(occ.id)
                next[row.id] = .bill(occ.id)
            } else if row.amount.isNegative, let id = StatementImport.loan(for: row.description, loans: loans) {
                next[row.id] = .transfer(id)
            } else if let id = StatementImport.account(for: row.description, accounts: others) {
                next[row.id] = .transfer(id)
            } else if let id = StatementImport.category(for: row.description, history: history),
                      let c = snapshot.account(id), c.kind == (row.amount.isNegative ? .expense : .income), !c.archived {
                next[row.id] = .category(id)
            }
        }
        targets = next
        suggestRest()
    }

    /// Everything else: well-known shops, then Apple Intelligence, then "Other",
    /// so every row arrives with a category the person only has to glance at
    private func suggestRest() {
        suggestTask?.cancel()
        let pending = inbox.filter { targets[$0.id] == nil }
        suggesting = pending.count
        guard !pending.isEmpty else { return }
        suggestTask = Task {
            var memo: [String: UUID] = [:]
            for row in pending {
                if Task.isCancelled { return }
                let income = !row.amount.isNegative
                let key = "\(income)|\(row.description.lowercased())"
                let id: UUID?
                if let known = memo[key] {
                    id = known
                } else {
                    id = try? await CaptureService.category(for: row.description, income: income,
                                                            snapshot: store.snapshot, store: store).id
                    memo[key] = id
                }
                if Task.isCancelled { return }
                if let id, targets[row.id] == nil { targets[row.id] = .category(id) }
                suggesting -= 1
            }
        }
    }

    // MARK: - Choosing

    func toggleAll() {
        skipped = allSelected ? Set(inbox.map(\.id)) : []
    }

    /// One choice for several rows at once
    func put(_ rows: [StatementRow], in categoryId: UUID) {
        for row in rows { targets[row.id] = .category(categoryId) }
    }

    /// Everything a row could be, grouped as the menu shows it
    func options(for row: StatementRow) -> [(String, [Option])] {
        let out = row.amount.isNegative
        var groups: [(String, [Option])] = []
        if out {
            let bills = snapshot.upcomingBills(days: 45).filter { occ in
                snapshot.item(for: occ).map { $0.accountId == nil || $0.accountId == accountId } ?? false
            }
            if !bills.isEmpty {
                groups.append(("Pays a bill", bills.compactMap { occ in
                    snapshot.item(for: occ).map {
                        Option(target: .bill(occ.id),
                               title: "\($0.name) · \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))", symbol: "calendar")
                    }
                }))
            }
        }
        let categories = out ? snapshot.expenseCategories : snapshot.incomeCategories
        groups.append((out ? "Spending" : "Income", categories.map { Option(target: .category($0.id), title: $0.name, symbol: $0.icon) }))
        let others = snapshot.accounts.filter { $0.id != accountId && $0.kind != .lent }
        if !others.isEmpty {
            groups.append((out ? "Moved to" : "Moved from", others.map {
                Option(target: .transfer($0.id), title: $0.name, symbol: $0.icon)
            }))
        }
        // Money lent isn't spending, and money paid back isn't income
        let people = snapshot.accounts.filter { $0.id != accountId && $0.kind == .lent && !$0.archived }
        if !people.isEmpty {
            groups.append((out ? "Lent to" : "Paid back by", people.map {
                Option(target: .transfer($0.id), title: $0.name, symbol: $0.icon)
            }))
        }
        return groups
    }

    /// What a row's choice reads as
    func label(for row: StatementRow) -> String? {
        switch targets[row.id] {
        case .category(let id): return snapshot.account(id)?.name
        case .transfer(let id):
            return snapshot.account(id).map {
                $0.kind == .loan ? "Pays \($0.name)" : $0.kind == .lent ? "Money lent · \($0.name)" : "Transfer · \($0.name)"
            }
        case .bill(let occId):
            return snapshot.occurrences.first { $0.id == occId }.flatMap(snapshot.item(for:)).map { "Pays \($0.name)" }
        case nil: return nil
        }
    }

    // MARK: - Adding

    func add() {
        let picks = ready.compactMap { row -> LedgerStore.ImportedRow? in
            guard let target = targets[row.id] else { return nil }
            return LedgerStore.ImportedRow(date: row.date, memo: row.description, amount: row.amount, target: target,
                                           key: key(for: row))
        }
        do {
            added = try store.importRows(picks, into: accountId)
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    /// The same row of the same statement always gets the same key, so a
    /// double tap or a second import can't add it twice
    func key(for row: StatementRow) -> UUID {
        let twins = rows.filter { $0.date == row.date && $0.amount == row.amount && $0.description == row.description }
        let ordinal = twins.firstIndex { $0.id == row.id } ?? 0
        let text = "\(accountId)|\(row.date.timeIntervalSince1970)|\(row.amount.minorUnits)|\(row.description)|\(ordinal)"
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
