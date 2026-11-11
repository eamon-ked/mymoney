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
    /// Row id → an entry of the same amount close by under another name. Maybe the same, maybe not:
    /// these rows stay in the list, left out until the person ticks them
    private(set) var maybeRecorded: [Int: UUID] = [:]
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
    /// The statement's own account number, when the file names it
    private(set) var ownNumber: String?
    /// Moves to another of the person's accounts that didn't say which: left for them to pick
    private(set) var ownTransfers: Set<Int> = []
    /// Loan instalments for a loan that isn't in the app yet: left for them to pick or add
    private(set) var loanRows: Set<Int> = []
    /// Loans added from this statement, set up once its rows are added
    private var newLoans: Set<UUID> = []
    /// The currency the statement names, when it does
    private(set) var fileCurrency: String?
    /// What the statement says the account held before its first row and after its last
    private(set) var balances: StatementBalances?
    /// The file's column names and the app's guess at which is which
    private(set) var layout: StatementLayout?
    /// The person's own choice of columns; nil uses the app's guess
    var columns: StatementColumns? {
        didSet {
            guard columns != oldValue else { return }
            remember(columns)
            parse()
        }
    }
    /// The columns in use: the person's choice, else Apple Intelligence's answer, else the guess
    var columnsInUse: StatementColumns? { columns ?? suggested ?? layout?.guess }
    /// Apple Intelligence's answer to what the values couldn't settle; used only when the file then reads
    private(set) var suggested: StatementColumns?
    /// Ask Apple Intelligence when the values leave a question; off in tests and on iPhones without it
    var askAI = false
    /// How many rows' amounts account for the change in the balance, with the columns in use
    private(set) var balanceCheck: BalanceCheck?
    /// The file was read but the app couldn't tell which column is which: the person picks them
    private(set) var needsColumns = false
    /// A PDF that's locked with a password, kept until it's unlocked
    @ObservationIgnored private var lockedPDF: Data?
    private(set) var needsPassword = false
    /// "Reading page 3 of 12…" while a PDF is read
    private(set) var reading: String?
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
    /// Rows the bulk "Put them in…" sorts: not moves between the person's own accounts
    var bulkSortable: [StatementRow] { unsorted.filter { !ownTransfers.contains($0.id) && !loanRows.contains($0.id) } }
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
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."
            return
        }
        if StatementPDF.isPDF(data) {
            Task { await loadPDF(data, named: url.lastPathComponent, password: nil) }
            return
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            error = "Couldn't read that file."
            return
        }
        load(text, named: url.lastPathComponent)
    }

    /// A PDF statement: its tables become rows, then the same review as a CSV
    func loadPDF(_ data: Data, named name: String, password: String?) async {
        error = nil
        reading = "Reading the statement…"
        defer { reading = nil }
        do {
            let grid = try await StatementPDF.grid(from: data, password: password) { page, pages in
                self.reading = pages > 1 ? "Reading page \(page) of \(pages)…" : "Reading the statement…"
            }
            lockedPDF = nil
            needsPassword = false
            load(StatementImport.csvText(grid), named: name)
        } catch StatementPDF.Problem.locked {
            lockedPDF = data
            fileName = name
            needsPassword = true
            if password != nil { error = "That password didn't open it. Try again." }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that PDF."
        }
    }

    /// Opens a locked PDF with the password the person typed
    func unlock(_ password: String) async {
        guard let lockedPDF else { return }
        await loadPDF(lockedPDF, named: fileName, password: password)
    }

    func load(_ text: String, named name: String) {
        fileName = name
        fileText = text
        ownNumber = StatementImport.accountNumber(in: text)
        fileCurrency = StatementImport.currency(in: text)
        layout = StatementImport.layout(in: text, currency: store.currency, calendar: store.calendar)
        suggested = nil
        // A choice made for an earlier file with the same column names
        let saved = layout.flatMap(remembered)
        if saved == nil, askAI, let layout, let question = layout.question {
            Task { await ask(question, layout: layout, text: text) }
        }
        // Card statements usually list purchases as positive numbers
        var flip = false
        if account?.kind.isLiability == true,
           let raw = try? StatementImport.read(text, currency: store.currency, columns: saved, calendar: store.calendar) {
            flip = raw.filter(\.amount.isPositive).count > raw.count / 2
        }
        if saved != columns { columns = saved }
        if flip != flipSigns { flipSigns = flip } else { parse() }
    }

    private func parse() {
        guard let fileText else { return }
        do {
            let chosen = columns ?? suggested
            rows = try StatementImport.read(fileText, currency: store.currency, flipSigns: flipSigns, columns: chosen,
                                            calendar: store.calendar)
            balances = StatementImport.balances(in: fileText, currency: store.currency, flipSigns: flipSigns, columns: chosen,
                                                calendar: store.calendar)
            balanceCheck = StatementImport.balanceCheck(fileText, currency: store.currency, columns: chosen, calendar: store.calendar)
            error = nil
            needsColumns = false
        } catch {
            rows = []
            balanceCheck = nil
            matched = [:]
            maybeRecorded = [:]
            targets = [:]
            balances = nil
            // Columns the app couldn't tell apart, or a choice that doesn't read: the person can choose again
            let canChoose = layout != nil && (columns != nil || error as? ImportError == .unrecognisedColumns)
            needsColumns = canChoose
            self.error = canChoose && columns == nil ? nil : (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
            if !canChoose { self.fileText = nil }
            return
        }
        let recorded = snapshot.entries(touching: accountId).filter { $0.kind != .openingBalance }.map { record in
            RecordedMovement(entryId: record.id, date: record.date,
                             amount: record.lines.filter { $0.accountId == accountId }
                                .map { Money(minorUnits: $0.minorUnits, currency: $0.currency) }.sum(store.currency),
                             memo: record.memo)
        }
        matched = StatementImport.match(rows, with: recorded, calendar: store.calendar)
        maybeRecorded = StatementImport.possibleMatches(rows, with: recorded, matched: matched, calendar: store.calendar)
        skipped = Set(maybeRecorded.keys)
        suggest()
    }

    /// Apple Intelligence answers what the values left open. Its answer is kept only when every row
    /// then reads and, where there's a balance, the amounts still add up to it.
    private func ask(_ question: ColumnQuestion, layout: StatementLayout, text: String) async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        reading = "Working out the columns…"
        defer { reading = nil }
        guard let answer = try? await MoneyAI.statementColumns(question, layout: layout, partial: layout.guess ?? StatementColumns()),
              answer.isComplete, fileText == text, columns == nil,
              (try? StatementImport.read(text, currency: store.currency, columns: answer, calendar: store.calendar)) != nil
        else { return }
        if let check = StatementImport.balanceCheck(text, currency: store.currency, columns: answer, calendar: store.calendar),
           Double(check.addUp) < Double(check.rows) * 0.8 { return }
        suggested = answer
        parse()
        #endif
    }

    // MARK: - Remembered columns

    private func columnsKey(_ layout: StatementLayout) -> String {
        let digest = SHA256.hash(data: Data(layout.signature.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "importColumns.\(accountId.uuidString).\(digest)"
    }

    private func remembered(_ layout: StatementLayout) -> StatementColumns? {
        guard let data = UserDefaults.standard.data(forKey: columnsKey(layout)),
              let saved = try? JSONDecoder().decode(StatementColumns.self, from: data),
              saved.isComplete, [saved.date, saved.description, saved.amount, saved.debit, saved.credit, saved.balance]
                .allSatisfy({ ($0 ?? 0) < layout.names.count }) else { return nil }
        return saved
    }

    private func remember(_ columns: StatementColumns?) {
        guard let layout else { return }
        if let columns, columns.isComplete, columns != layout.guess, let data = try? JSONEncoder().encode(columns) {
            UserDefaults.standard.set(data, forKey: columnsKey(layout))
        } else if columns == nil || columns == layout.guess {
            UserDefaults.standard.removeObject(forKey: columnsKey(layout))
        }
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
        let ownAccounts = snapshot.accounts.filter {
            $0.id != accountId && [.bank, .savings, .investment, .creditCard].contains($0.kind)
        }
        var next: [Int: Target] = [:]
        var own: Set<Int> = []
        var loanPayments: Set<Int> = []
        var billsTaken: Set<UUID> = []
        for row in inbox {
            if let occ = StatementImport.bill(for: row, occurrences: snapshot.occurrences, items: snapshot.items,
                                              accountId: accountId, calendar: store.calendar),
               !billsTaken.contains(occ.id) {
                billsTaken.insert(occ.id)
                next[row.id] = .bill(occ.id)
            } else if row.amount.isNegative, let id = StatementImport.loan(for: row.description, loans: loans) {
                next[row.id] = .transfer(id)
            } else if row.amount.isNegative, StatementImport.isInstalment(row.description) {
                // Not spending: it pays down a loan the app doesn't know yet
                loanPayments.insert(row.id)
            } else if let id = StatementImport.account(for: row.description, accounts: others) {
                next[row.id] = .transfer(id)
            } else if let numbered = ownAccounts.first(where: { a in
                a.accountNumber.map { StatementImport.longNumbers(row.description).contains($0) } ?? false
            }) {
                next[row.id] = .transfer(numbered.id)
            } else if StatementImport.isOwnAccountTransfer(row.description, ownNumber: ownNumber) {
                // Not spending: it went to another of their accounts. Which one, if there's only one
                if ownAccounts.count == 1 { next[row.id] = .transfer(ownAccounts[0].id) } else { own.insert(row.id) }
            } else if let id = StatementImport.category(for: row.description, history: history),
                      let c = snapshot.account(id), c.kind == (row.amount.isNegative ? .expense : .income), !c.archived,
                      CategoryRules.historyFits(categoryName: c.name, description: row.description, income: !row.amount.isNegative) {
                next[row.id] = .category(id)
            }
        }
        targets = next
        ownTransfers = own
        loanRows = loanPayments
        suggestRest()
    }

    /// Everything else: well-known shops, then Apple Intelligence, then "Other",
    /// so every row arrives with a category the person only has to glance at
    private func suggestRest() {
        suggestTask?.cancel()
        let pending = inbox.filter { targets[$0.id] == nil && !ownTransfers.contains($0.id) && !loanRows.contains($0.id) }
        suggesting = pending.count
        guard !pending.isEmpty else { return }
        // Holds the review only while a suggestion is being worked out, so closing the screen stops it
        suggestTask = Task { [weak self] in
            var memo: [String: UUID] = [:]
            for row in pending {
                guard let self, !Task.isCancelled else { return }
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

    /// "Maybe already recorded: Carrefour, 6 Nov" for a row that has a lookalike entry
    func lookalike(for row: StatementRow) -> EntryRecord? {
        maybeRecorded[row.id].flatMap { store.entryRecord($0) }
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
        // Money with friends isn't spending or income: it moves what they owe you, or what you owe them
        let people = snapshot.accounts.filter { $0.id != accountId && $0.kind == .lent && !$0.archived }
        if !people.isEmpty {
            groups.append((out ? "To a person" : "From a person", people.map {
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
                $0.kind == .loan ? "Pays \($0.name)" : $0.kind == .lent ? "\(row.amount.isNegative ? "To" : "From") \($0.name)" : "Transfer · \($0.name)"
            }
        case .bill(let occId):
            return snapshot.occurrences.first { $0.id == occId }.flatMap(snapshot.item(for:)).map { "Pays \($0.name)" }
        case nil: return nil
        }
    }

    /// What a row with no choice yet asks for
    func prompt(for row: StatementRow) -> String {
        ownTransfers.contains(row.id) ? "Which of your accounts?" : loanRows.contains(row.id) ? "Which loan?" : "Choose a category"
    }

    // MARK: - Adding

    /// A statement in another currency: its amounts can't be added as this account's money
    var currencyProblem: String? {
        guard let theirs = fileCurrency, let account, theirs != account.currency else { return nil }
        return "This statement is in \(theirs), but \(account.name) is in \(account.currency). Nokael Money doesn't convert between currencies, so it can't be added here."
    }

    func add() {
        if let currencyProblem { error = currencyProblem; return }
        let picks = ready.compactMap { row -> LedgerStore.ImportedRow? in
            guard let target = targets[row.id] else { return nil }
            return LedgerStore.ImportedRow(date: row.date, memo: row.description, amount: row.amount, target: target,
                                           key: key(for: row))
        }
        do {
            added = try store.importRows(picks, into: accountId)
            // The statement's rows were already inside a balance added later: start from the statement instead
            if let balances {
                try store.anchorOpening(accountId, statementOpening: balances.opening, firstDay: balances.firstDay)
            }
            for loanId in newLoans {
                let payments = ready.filter { targets[$0.id] == .transfer(loanId) }.map { (date: $0.date, amount: $0.amount.magnitude) }
                try store.startLoan(loanId, payments: payments, paidFrom: accountId)
            }
            newLoans = []
            if let ownNumber, account?.accountNumber == nil { try store.setAccountNumber(accountId, ownNumber) }
            // Pay, a loan or bills it shows, for Home to offer
            try store.saveFindings(StatementInsights.findings(rows, today: snapshot.today, calendar: store.calendar))
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    /// Money moved to an account of theirs that isn't in the app: it becomes one, kept aside as
    /// savings (not spendable) until they check its balance, and every row naming it goes there
    func addOwnAccount(for row: StatementRow) {
        let number = StatementImport.otherOwnAccount(in: row.description, ownNumber: ownNumber)
            ?? StatementImport.longNumbers(row.description).first { $0 != ownNumber }
        do {
            let record = try store.addAccount(name: number.map { "Account …\($0.suffix(4))" } ?? "Other account", kind: .savings,
                                              balance: .zero(store.currency), openingDate: row.date)
            if let number { try store.setAccountNumber(record.id, number) }
            for r in inbox where ownTransfers.contains(r.id) {
                let same = number.map { StatementImport.longNumbers(r.description).contains($0) } ?? (r.id == row.id)
                if same { targets[r.id] = .transfer(record.id) }
            }
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    /// Payments to a loan that isn't in the app: it becomes one, named from the bank's reference,
    /// and every instalment with the same reference goes to it. What's owed is asked on Home
    func addLoan(for row: StatementRow) {
        let reference = StatementImport.loanReference(row.description)
        let rows = inbox.filter { r in
            loanRows.contains(r.id) && (reference.map { StatementImport.loanReference(r.description) == $0 } ?? (r.id == row.id))
        }
        do {
            let record = try store.addUnfinishedLoan(name: reference.map { "Loan …\($0.suffix(4))" } ?? "Loan",
                                                     openingDate: rows.map(\.date).min() ?? row.date)
            newLoans.insert(record.id)
            for r in rows { targets[r.id] = .transfer(record.id) }
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    // MARK: - Balances

    /// The app's balance at the end of the statement against the statement's own closing balance
    var closingCheck: ReconciliationCheck? {
        guard let balances, let closing = balances.closing else { return nil }
        return Reconciler.check(ledger: snapshot.ledger, accountId: accountId,
                                statementDate: snapshot.endOfDay(balances.lastDay), statementBalance: closing)
    }

    /// Starts the account from the statement and, if it still differs, corrects it to the closing balance
    func matchStatement() {
        guard let balances else { return }
        do {
            try store.anchorOpening(accountId, statementOpening: balances.opening, firstDay: balances.firstDay)
            if let closing = balances.closing, closingCheck?.matches == false {
                try store.reconcile(accountId: accountId, statementDate: snapshot.endOfDay(balances.lastDay),
                                    statementBalance: closing, reason: "Matched to the statement")
            }
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
