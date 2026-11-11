//
//  StatementImport.swift
//  NokaelCore
//
//  Reading a bank or card statement exported as CSV, and lining its rows up
//  with what's already recorded. Rows that match an entry are left alone, so
//  importing the same statement twice adds nothing the second time.
//

import Foundation

public enum ImportError: Error, Equatable, LocalizedError {
    case empty
    case unrecognisedColumns
    case unreadableDate(row: Int, text: String)
    case unreadableAmount(row: Int, text: String)
    /// A quote opened and never closed: everything after it would be lost
    case damaged

    public var errorDescription: String? {
        switch self {
        case .empty: return "The file has no rows."
        case .unrecognisedColumns: return "Couldn't find date, description and amount columns. The first row should name the columns."
        case .unreadableDate(let row, let text): return "Row \(row): \"\(text)\" isn't a date this app can read."
        case .unreadableAmount(let row, let text): return "Row \(row): \"\(text)\" isn't an amount."
        case .damaged: return "The file looks damaged: a quote mark is never closed, so some rows can't be read. Export it again from your bank."
        }
    }
}

/// One statement line. `amount` is from the account's point of view: positive
/// means money into it (or a card payment), negative means money out (or a purchase).
public struct StatementRow: Hashable, Sendable, Identifiable {
    /// Position in the file, from 1 after the header
    public let id: Int
    public let date: Date
    public let description: String
    public let amount: Money

    public init(id: Int, date: Date, description: String, amount: Money) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
    }
}

/// Something already recorded that touches the account, for matching
public struct RecordedMovement: Hashable, Sendable {
    public let entryId: UUID
    public let date: Date
    /// Signed, from the account's point of view
    public let amount: Money
    /// What the entry says it was, to tell two purchases of the same amount apart
    public let memo: String

    public init(entryId: UUID, date: Date, amount: Money, memo: String = "") {
        self.entryId = entryId
        self.date = date
        self.amount = amount
        self.memo = memo
    }
}

/// Which column holds what. Positions count from 0 in the header row.
public struct StatementColumns: Equatable, Hashable, Sendable, Codable {
    public var date: Int?
    public var description: Int?
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?
    /// The running balance after each row, when the bank gives one
    public var balance: Int? = nil

    public init(date: Int? = nil, description: Int? = nil, amount: Int? = nil, debit: Int? = nil, credit: Int? = nil,
                balance: Int? = nil) {
        self.date = date
        self.description = description
        self.amount = amount
        self.debit = debit
        self.credit = credit
        self.balance = balance
    }

    /// A date, a description, and one amount or separate money out and money in
    public var isComplete: Bool {
        date != nil && description != nil && (amount != nil || (debit != nil && credit != nil))
    }

    /// What still has to be chosen, in words, or nil when nothing is missing
    public var missing: [String] {
        var out: [String] = []
        if date == nil { out.append("date") }
        if description == nil { out.append("description") }
        if amount == nil && debit == nil && credit == nil { out.append("amount") }
        else if amount == nil && debit == nil { out.append("money out") }
        else if amount == nil && credit == nil { out.append("money in") }
        return out
    }
}

/// A file's column names, the rows under them, and the app's guess at which is which
public struct StatementLayout: Equatable, Sendable {
    /// Row of the column names in the file
    public let headerIndex: Int
    public let names: [String]
    /// The first few rows under the names, to show what each column holds
    public let samples: [[String]]
    /// What the app found on its own; nil when it couldn't tell
    public let guess: StatementColumns?
    /// What the values couldn't settle, when the guess is incomplete
    public var question: ColumnQuestion? = nil
    /// How the guess's balance column agrees with its amounts
    public var check: BalanceCheck? = nil

    /// A column's name, or "Column 3" when the file leaves it blank
    public func name(_ index: Int) -> String {
        let n = index < names.count ? names[index].trimmingCharacters(in: .whitespaces) : ""
        return n.isEmpty ? "Column \(index + 1)" : n
    }

    /// The first non-empty value under a column
    public func sample(_ index: Int) -> String? {
        samples.lazy.compactMap { $0.count > index ? $0[index].trimmingCharacters(in: .whitespaces) : nil }
            .first { !$0.isEmpty }
    }

    /// A short key for this set of column names, to remember a choice for the next file like it
    public var signature: String {
        names.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.joined(separator: "|")
    }
}

/// What a statement says the account held, before its first row and after its last
public struct StatementBalances: Equatable, Sendable {
    public let opening: Money?
    public let closing: Money?
    /// The day of the first and last rows
    public let firstDay: Date
    public let lastDay: Date
}

public enum StatementImport {

    // MARK: - CSV

    /// Rows and fields, honouring quotes. The delimiter (comma, semicolon or tab)
    /// is whichever appears most in the first line.
    public static func csvRows(_ text: String) -> [[String]] { scan(text).rows }

    /// The rows, and whether a quote was left open at the end of the file
    static func scan(_ text: String) -> (rows: [[String]], unclosed: Bool) {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // Whichever splits some line among the first few into the most cells: account details
        // above the column names may have none
        let lines = body.split(omittingEmptySubsequences: true) { $0 == "\n" || $0 == "\r" }.prefix(20)
        func most(_ d: Character) -> Int { lines.map { line in line.filter { $0 == d }.count }.max() ?? 0 }
        let delimiter: Character = [",", ";", "\t"].max { most($0) < most($1) } ?? ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(body)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return (rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }, quoted)
    }

    // MARK: - Columns

    // English first, then the names banks use in other languages: German, French, Spanish, Portuguese, Italian, Dutch, Arabic
    static let dateNames = ["date", "transaction date", "posting date", "posted date", "value date", "txn date", "trans date",
                                    "datum", "buchungstag", "buchungsdatum", "date d'opération", "date opération", "fecha", "data",
                                    "data operazione", "التاريخ", "تاريخ العملية"]
    static let descriptionNames = ["description", "details", "transaction details", "narrative", "narration", "merchant",
                                           "payee", "particulars", "memo", "name", "reference", "remarks",
                                           "beschreibung", "verwendungszweck", "buchungstext", "empfänger", "libellé", "libelle",
                                           "concepto", "descripción", "descripcion", "descrição", "descricao", "histórico",
                                           "descrizione", "omschrijving", "البيان", "الوصف", "التفاصيل"]
    static let amountNames = ["amount", "transaction amount", "value", "betrag", "umsatz", "montant", "importe",
                                      "valor", "importo", "bedrag", "المبلغ"]
    static let debitNames = ["debit", "debits", "debit amount", "withdrawal", "withdrawals", "money out", "paid out", "out",
                                     "soll", "lastschrift", "débit", "debito", "débito", "cargo", "cargos", "addebiti", "af", "مدين", "سحب"]
    static let creditNames = ["credit", "credits", "credit amount", "deposit", "deposits", "money in", "paid in", "in",
                                      "haben", "gutschrift", "crédit", "credito", "crédito", "abono", "abonos", "accrediti", "bij", "دائن", "إيداع"]
    static let balanceNames = ["balance", "running balance", "available balance", "ledger balance", "closing balance",
                                       "saldo", "kontostand", "solde", "الرصيد"]

    /// Every role found by its column's name, or nil when one is missing
    public static func columns(header: [String]) -> StatementColumns? {
        let c = columnsByName(header)
        guard c.date != nil, c.description != nil, c.amount != nil || (c.debit != nil && c.credit != nil) else { return nil }
        return c
    }

    // MARK: - Layout

    /// The column names and the app's guess, for showing the person which column is which.
    /// nil when the file has no rows to choose from.
    public static func layout(in text: String, currency: String = "USD", calendar: Calendar = .current) -> StatementLayout? {
        let rows = csvRows(text)
        guard let headerIndex = headerIndex(in: rows) else { return nil }
        let body = rows.dropFirst(headerIndex + 1).filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !body.isEmpty else { return nil }
        let found = findColumns(header: rows[headerIndex], body: Array(body), currency: currency, calendar: calendar)
        let any = [found.columns.date, found.columns.description, found.columns.amount, found.columns.debit, found.columns.credit]
            .contains { $0 != nil }
        return StatementLayout(headerIndex: headerIndex, names: rows[headerIndex], samples: Array(body.prefix(5)),
                               guess: any ? found.columns : nil, question: found.question, check: found.check)
    }

    /// The row with the column names: the first the app recognises, else the first wide row
    /// that holds no dates or amounts (the names may sit below a few lines of account details)
    static func headerIndex(in rows: [[String]]) -> Int? {
        if let known = rows.prefix(15).firstIndex(where: { columns(header: $0) != nil }) { return known }
        let widest = rows.prefix(40).map { row in row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }.max() ?? 0
        guard widest >= 2 else { return nil }
        return rows.prefix(15).firstIndex { row in
            let cells = row.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return cells.count >= widest - 1 && cells.count >= 2
                && !cells.contains { cell in looksLikeValue(cell) }
        } ?? rows.prefix(15).firstIndex { row in row.filter { !$0.isEmpty }.count >= widest - 1 }
    }

    /// A cell that's an amount or a date rather than a column name
    private static func looksLikeValue(_ cell: String) -> Bool {
        let digits = cell.filter(\.isNumber).count
        return digits > 0 && digits * 2 >= cell.filter { !$0.isWhitespace }.count
    }

    /// The header row and the columns to use: the person's choice when it's complete, else the app's guess
    static func resolve(_ rows: [[String]], chosen: StatementColumns?, currency: String,
                        calendar: Calendar) -> (header: Int, columns: StatementColumns)? {
        guard let i = headerIndex(in: rows) else { return nil }
        if let chosen, chosen.isComplete { return (i, chosen) }
        let body = rows.dropFirst(i + 1).filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        let found = findColumns(header: rows[i], body: Array(body), currency: currency, calendar: calendar).columns
        return found.isComplete ? (i, found) : nil
    }

    /// Rows and cells as CSV text, for files that aren't CSV to begin with (a PDF's tables)
    public static func csvText(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                let clean = cell.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
                return clean.contains(",") || clean.contains("\"") ? "\"" + clean.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : clean
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    // MARK: - Values

    /// Day-first formats come before month-first, as banks in the UAE and UK use them
    static let dateFormats = ["yyyy-MM-dd", "d/M/yyyy", "M/d/yyyy", "d-M-yyyy", "d.M.yyyy", "d MMM yyyy", "d-MMM-yyyy",
                              "d MMM yy", "d-MMM-yy", "d/M/yy", "yyyy/M/d", "MMM d, yyyy"]

    /// The first format that reads every date in the file
    /// When day-first and month-first both read every date ("03/04/2026"), the one that keeps the rows
    /// in date order wins, then the one whose dates lie closest together: a statement covers weeks, not
    /// months scattered across the year. Day-first when nothing tells them apart.
    static func dateFormat(for texts: [String], calendar: Calendar) -> DateFormatter? {
        let fits = dateFormats.map { formatter($0, calendar: calendar) }.filter { f in texts.allSatisfy { parse($0, with: f) != nil } }
        guard fits.count > 1 else { return fits.first }
        func rank(_ f: DateFormatter) -> (Int, Double) {
            let days = texts.compactMap { parse($0, with: f) }
            let pairs = Array(zip(days, days.dropFirst()))
            let inOrder = max(pairs.filter { $0 <= $1 }.count, pairs.filter { $0 >= $1 }.count)
            let span = (days.max() ?? .distantPast).timeIntervalSince(days.min() ?? .distantPast)
            return (inOrder, -span)
        }
        return fits.enumerated().max { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return (ra.0, ra.1, -a.offset) < (rb.0, rb.1, -b.offset)
        }?.element
    }

    static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        f.isLenient = false
        return f
    }

    static func parse(_ text: String, with f: DateFormatter) -> Date? {
        if let d = f.date(from: text) { return d }
        // Some banks add a time: "25/10/2026 14:03" or "2026-10-25T14:03:00"
        if let time = text.range(of: #"[ T]\d{1,2}:\d{2}"#, options: .regularExpression),
           let d = f.date(from: String(text[..<time.lowerBound])) {
            return d
        }
        // A date with something stuck to it, as a scanned page can read: "11/11/2026ł 00:57:13"
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let lead = trimmed.range(of: #"^(\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4}|\d{1,2}[ \-][A-Za-z]{3,9}[ \-]\d{2,4})"#,
                                    options: .regularExpression), lead.upperBound < trimmed.endIndex {
            return f.date(from: String(trimmed[lead]))
        }
        return nil
    }

    /// "1,234.50", "-45", "(45.00)", "45.00 DR", "AED 1.234,50"
    public static func amount(_ text: String, currency: String) -> Money? {
        var t = text.uppercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        // Only a currency, DR/CR, signs, brackets and separators may sit around the digits:
        // "12abc34" isn't an amount, and neither is "12.34.56"
        let letters = t.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let codes = Set(Locale.commonISOCurrencyCodes).union([currency.uppercased(), "DR", "CR"])
        guard letters.allSatisfy(codes.contains) else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.,'()-+ \u{00A0}\u{202F}").union(.letters).union(.symbols)
        guard t.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        var negative = false
        if t.hasPrefix("(") && t.hasSuffix(")") { negative = true }
        if t.hasSuffix("DR") || t.hasSuffix("-") { negative = true }
        if t.contains("-") && !t.hasSuffix("-") { negative = true }
        t = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !t.isEmpty else { return nil }
        // "1.234.567" groups with dots; any other repeated dot is a mistake
        if !t.contains(","), t.filter({ $0 == "." }).count > 1 {
            let groups = t.split(separator: ".", omittingEmptySubsequences: false)
            guard groups.dropFirst().allSatisfy({ $0.count == 3 }), (1...3).contains(groups[0].count) else { return nil }
            t = t.replacingOccurrences(of: ".", with: "")
        }
        if t.contains(",") && t.contains(".") {
            // Whichever comes last is the decimal mark
            if t.lastIndex(of: ",")! > t.lastIndex(of: ".")! {
                t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                t = t.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma = t.lastIndex(of: ","), t.distance(from: comma, to: t.endIndex) == 3, t.filter({ $0 == "," }).count == 1 {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        guard t.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")),
              let money = Money.exact(d, currency: currency) else { return nil }
        return negative ? -money : money
    }

    // MARK: - Reading

    /// Statement rows, oldest first. `flipSigns` is for card statements that show
    /// purchases as positive numbers.
    /// `chosen` is the person's own choice of columns, used in place of the app's guess.
    public static func read(_ text: String, currency: String, flipSigns: Bool = false, columns chosen: StatementColumns? = nil,
                            calendar: Calendar) throws -> [StatementRow] {
        let (rows, unclosed) = scan(text)
        guard !unclosed else { throw ImportError.damaged }
        guard rows.count > 1 else { throw ImportError.empty }
        guard let found = resolve(rows, chosen: chosen, currency: currency, calendar: calendar),
              let dateColumn = found.columns.date, let descriptionColumn = found.columns.description else { throw ImportError.unrecognisedColumns }
        let (headerIndex, cols) = (found.header, found.columns)
        let body = Array(rows.dropFirst(headerIndex + 1)).filter { $0.count > dateColumn && !$0[dateColumn].isEmpty }
        guard !body.isEmpty else { throw ImportError.empty }

        guard let f = dateFormat(for: body.map { $0[dateColumn] }, calendar: calendar) else {
            let bad = body.first { r in dateFormats.allSatisfy { parse(r[dateColumn], with: formatter($0, calendar: calendar)) == nil } }
            throw ImportError.unreadableDate(row: 1 + (bad.flatMap { b in body.firstIndex(of: b) } ?? 0), text: bad?[dateColumn] ?? "")
        }

        var out: [StatementRow] = []
        let values = rowValues(body, cols: cols, currency: currency)
        for (n, r) in body.enumerated() {
            func field(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            guard let value = values[n] else {
                let bad = [cols.amount, cols.debit, cols.credit].map(field).first { !$0.isEmpty && amount($0, currency: currency) == nil }
                throw ImportError.unreadableAmount(row: n + 1, text: bad ?? field(cols.amount))
            }
            guard !value.isZero, let day = parse(r[dateColumn], with: f) else { continue }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            out.append(StatementRow(id: n + 1, date: noon, description: field(descriptionColumn),
                                    amount: flipSigns ? -value : value))
        }
        return out.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// A row's amount from the account's point of view: one amount column, or credit minus debit
    static func signedValue(_ r: [String], cols: StatementColumns, currency: String) -> Money? {
        func field(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
        if let a = cols.amount { return amount(field(a), currency: currency) }
        // A blank side is nothing; something there that isn't an amount is an error, never a silent zero
        func side(_ i: Int?) -> Money? {
            let text = field(i)
            return text.isEmpty ? .zero(currency) : amount(text, currency: currency)?.magnitude
        }
        guard let debit = side(cols.debit), let credit = side(cols.credit) else { return nil }
        return credit - debit
    }

    // MARK: - Balances

    /// The balances a statement gives: "Opening Balance: 2.23 AED" lines above
    /// the column names, else worked out from a Balance column. nil when the
    /// file has rows but says nothing about balances.
    public static func balances(in text: String, currency: String, flipSigns: Bool = false, columns chosen: StatementColumns? = nil,
                                calendar: Calendar) -> StatementBalances? {
        let rows = csvRows(text)
        guard let found = resolve(rows, chosen: chosen, currency: currency, calendar: calendar), let dateColumn = found.columns.date else { return nil }
        let (headerIndex, cols) = (found.header, found.columns)
        let body = Array(rows.dropFirst(headerIndex + 1)).filter { $0.count > dateColumn && !$0[dateColumn].isEmpty }
        guard let f = dateFormat(for: body.map { $0[dateColumn] }, calendar: calendar) else { return nil }
        // Oldest first, keeping the file's order within a day
        let values = rowValues(body, cols: cols, currency: currency)
        var dated = body.indices.compactMap { i in parse(body[i][dateColumn], with: f).map { (day: $0, row: body[i], value: values[i]) } }
        guard let first = dated.first, let last = dated.last else { return nil }
        if first.day > last.day { dated.reverse() }
        dated = dated.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }.map(\.element)

        var opening: Money?
        var closing: Money?
        for cell in rows.prefix(headerIndex).flatMap({ $0 }) {
            let lower = cell.lowercased()
            let value = cell.split(separator: ":").last.map(String.init).flatMap { amount($0, currency: currency) }
            if lower.contains("opening balance") || lower.contains("balance brought forward") || lower.contains("starting balance") {
                opening = opening ?? value
            } else if lower.contains("closing balance") || lower.contains("ending balance") {
                closing = closing ?? value
            }
        }
        if let b = cols.balance {
            func balance(_ r: [String]) -> Money? { b < r.count ? amount(r[b], currency: currency) : nil }
            if closing == nil, let row = dated.last?.row { closing = balance(row) }
            if opening == nil, let row = dated.first?.row, let after = balance(row), let moved = dated.first?.value {
                opening = after - (flipSigns ? -moved : moved)
            }
        }
        guard opening != nil || closing != nil, let firstDay = dated.first?.day, let lastDay = dated.last?.day else { return nil }
        return StatementBalances(opening: opening, closing: closing, firstDay: firstDay, lastDay: lastDay)
    }

    /// The currency a statement names above its rows ("Account Number: … AED") or in its column names
    /// ("Amount (USD)"), if any
    public static func currency(in text: String) -> String? {
        let rows = csvRows(text)
        let above = rows.prefix(while: { columns(header: $0) == nil }).prefix(15)
        let top = Array(above) + Array(rows.dropFirst(above.count).prefix(1))
        let codes = Set(Locale.commonISOCurrencyCodes)
        for cell in top.flatMap({ $0 }) {
            let words = cell.components(separatedBy: CharacterSet.letters.inverted)
            if let code = words.first(where: { $0.count == 3 && $0 == $0.uppercased() && codes.contains($0) }) { return code }
        }
        return nil
    }

    // MARK: - Matching

    /// Pairs statement rows with recorded entries of the same amount within
    /// `days` of each other, each entry used once, nearest date first.
    public static func match(_ rows: [StatementRow], with recorded: [RecordedMovement], days: Int = 3,
                             calendar: Calendar) -> [Int: UUID] {
        var unused = recorded
        var out: [Int: UUID] = [:]
        // Exact-date pairs first, so a near miss can't steal a same-day match
        let candidates = rows.flatMap { row in
            recorded.compactMap { m -> (row: Int, entry: UUID, gap: Int)? in
                guard m.amount == row.amount, sameName(row.description, m.memo) else { return nil }
                let gap = abs(dayGap(row.date, m.date, calendar: calendar))
                return gap <= days ? (row.id, m.entryId, gap) : nil
            }
        }.sorted { ($0.gap, $0.row) < ($1.gap, $1.row) }
        for c in candidates where out[c.row] == nil {
            guard let i = unused.firstIndex(where: { $0.entryId == c.entry }) else { continue }
            unused.remove(at: i)
            out[c.row] = c.entry
        }
        // A row left over may still have an entry, taken by a nearer row that could use another one.
        // Moving that row along leaves both matched, rather than this one imported a second time
        let options = Dictionary(grouping: candidates, by: \.row).mapValues { $0.map(\.entry) }
        var owner = Dictionary(out.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        func place(_ row: Int, seen: inout Set<UUID>) -> Bool {
            for entry in options[row] ?? [] where !seen.contains(entry) {
                seen.insert(entry)
                if let holder = owner[entry], !place(holder, seen: &seen) { continue }
                owner[entry] = row
                out[row] = entry
                return true
            }
            return false
        }
        for row in rows.map(\.id) where out[row] == nil && options[row] != nil {
            var seen = Set<UUID>()
            _ = place(row, seen: &seen)
        }
        return out
    }

    /// Whether a statement line and an entry could name the same thing. Either may say nothing useful
    /// ("Lunch", a blank memo); two shop names with no word in common are two purchases.
    static func sameName(_ description: String, _ memo: String) -> Bool {
        let a = Set(merchantWords(description, limit: 6)), b = Set(merchantWords(memo, limit: 6))
        return a.isEmpty || b.isEmpty || !a.isDisjoint(with: b)
    }

    /// Rows that `match` left alone but that have an entry of the same amount close by under another name.
    /// Not proof of a duplicate, so they're shown for the person to decide rather than hidden.
    public static func possibleMatches(_ rows: [StatementRow], with recorded: [RecordedMovement], matched: [Int: UUID],
                                       days: Int = 3, calendar: Calendar) -> [Int: UUID] {
        let used = Set(matched.values)
        var out: [Int: UUID] = [:]
        for row in rows where matched[row.id] == nil {
            out[row.id] = recorded
                .filter { !used.contains($0.entryId) && $0.amount == row.amount && abs(dayGap(row.date, $0.date, calendar: calendar)) <= days }
                .min { abs(dayGap(row.date, $0.date, calendar: calendar)) < abs(dayGap(row.date, $1.date, calendar: calendar)) }?
                .entryId
        }
        return out
    }

    /// An unpaid bill this row probably pays: same amount (or close, for
    /// estimates) and due within `days`
    public static func bill(for row: StatementRow, occurrences: [Occurrence], items: [PlannedItem], accountId: UUID,
                            days: Int = 5, calendar: Calendar) -> Occurrence? {
        guard row.amount.isNegative else { return nil }
        let paid = row.amount.magnitude
        return occurrences.filter { occ in
            guard let item = items.first(where: { $0.id == occ.itemId }), item.direction == .outflow,
                  !occ.skipped, occ.remaining.isPositive,
                  item.accountId == nil || item.accountId == accountId,
                  abs(dayGap(row.date, occ.dueDate, calendar: calendar)) <= days else { return false }
            if occ.isEstimate {
                let r = Double(occ.remaining.minorUnits)
                return abs(Double(paid.minorUnits) - r) <= r * 0.25
            }
            return occ.remaining == paid
        }
        .min { abs(dayGap(row.date, $0.dueDate, calendar: calendar)) < abs(dayGap(row.date, $1.dueDate, calendar: calendar)) }
    }

    /// The category used last time for a similar description. "Carrefour" in
    /// the history matches "POS CARREFOUR CITY 4411".
    public static func category(for description: String, history: [(memo: String, categoryId: UUID)]) -> UUID? {
        let words = merchantWords(description)
        guard !words.isEmpty else { return nil }
        return history.first { past in
            let pastWords = merchantWords(past.memo)
            let (short, long) = pastWords.count <= words.count ? (pastWords, words) : (words, pastWords)
            return !short.isEmpty && short[0].count >= 3 && Array(long.prefix(short.count)) == short
        }?.categoryId
    }

    /// Another of the person's accounts the description names, e.g.
    /// "MASHREQ CARD PAYMENT" → "Mashreq Cashback"
    public static func account(for description: String, accounts: [(id: UUID, name: String)]) -> UUID? {
        let words = Set(merchantWords(description, limit: 8))
        let generic: Set = ["current", "savings", "saving", "account", "credit", "loan", "bank", "cash", "main", "card"]
        let hits = accounts.filter { account in
            merchantWords(account.name, limit: 4).contains { $0.count >= 3 && !generic.contains($0) && words.contains($0) }
        }
        return hits.count == 1 ? hits[0].id : nil
    }

    /// The statement's own account number, from the details above the column
    /// names: "Account Number: 70345126560001 AED" → "70345126560001"
    public static func accountNumber(in text: String) -> String? {
        let rows = csvRows(text)
        let top = rows.prefix(while: { columns(header: $0) == nil }).prefix(15)
        for cell in top.flatMap({ $0 }) {
            let lower = cell.lowercased()
            guard lower.contains("account number") || lower.contains("account no") || lower.contains("iban") else { continue }
            if let number = longNumbers(cell).first { return number }
        }
        return nil
    }

    /// Money moved to another account of the same person at the same bank:
    /// the description names an account number that isn't this one but
    /// starts with the same customer digits ("…@70345126730001" from 70345126560001)
    public static func isOwnAccountTransfer(_ description: String, ownNumber: String?) -> Bool {
        otherOwnAccount(in: description, ownNumber: ownNumber) != nil
    }

    /// The person's other account a transfer names: "70345126730001" in
    /// "49051225550MBTRFAED1000.00@70345126730001", not the reference before it
    public static func otherOwnAccount(in description: String, ownNumber: String?) -> String? {
        guard let own = ownNumber, own.count >= 10 else { return nil }
        return longNumbers(description).first { $0 != own && $0.count == own.count && $0.prefix(8) == own.prefix(8) }
    }

    /// Runs of 10 or more digits, spaces inside an IBAN allowed
    public static func longNumbers(_ text: String) -> [String] {
        text.replacingOccurrences(of: " ", with: "")
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { $0.count >= 10 }
    }

    /// A loan instalment ("LOANRECOVERY-EMI:1139…", "MORTGAGE INSTALMENT") goes to the loan
    /// it names, else to the only loan there is
    public static func loan(for description: String, loans: [(id: UUID, name: String)]) -> UUID? {
        guard !loans.isEmpty, isInstalment(description) else { return nil }
        if let named = account(for: description, accounts: loans) { return named }
        return loans.count == 1 ? loans[0].id : nil
    }

    /// Reads as a loan instalment: "LOANRECOVERY-EMI:1139…", "MORTGAGE INSTALMENT"
    public static func isInstalment(_ description: String) -> Bool {
        let words = description.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let marks = ["loan", "emi", "instal", "mortgage", "finance", "repayment"]
        return words.contains { w in marks.contains { w == $0 || ($0.count > 3 && w.contains($0)) } }
    }

    /// The loan's own reference in an instalment, "LOANRECOVERY-EMI:70345126P022001" → "70345126P022001":
    /// the last run of six or more letters and digits that has a digit in it
    public static func loanReference(_ description: String) -> String? {
        description.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .last { $0.count >= 6 && $0.contains(where: \.isNumber) }
    }

    /// "POS PURCHASE CARREFOUR CITY 1234 DUBAI AE" → ["carrefour", "city"]
    public static func merchantWords(_ text: String, limit: Int = 3) -> [String] {
        let noise: Set = ["pos", "pur", "purchase", "card", "ae", "uae", "dubai", "abu", "dhabi", "sharjah", "llc", "the",
                          "payment", "transfer", "to", "from", "bill"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 1 && !noise.contains($0) }
        return Array(words.prefix(limit))
    }

    private static func dayGap(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
