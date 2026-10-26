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

    public var errorDescription: String? {
        switch self {
        case .empty: return "The file has no rows."
        case .unrecognisedColumns: return "Couldn't find date, description and amount columns. The first row should name the columns."
        case .unreadableDate(let row, let text): return "Row \(row): \"\(text)\" isn't a date this app can read."
        case .unreadableAmount(let row, let text): return "Row \(row): \"\(text)\" isn't an amount."
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

    public init(entryId: UUID, date: Date, amount: Money) {
        self.entryId = entryId
        self.date = date
        self.amount = amount
    }
}

public struct StatementColumns: Equatable, Sendable {
    public var date: Int
    public var description: Int
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?
}

public enum StatementImport {

    // MARK: - CSV

    /// Rows and fields, honouring quotes. The delimiter (comma, semicolon or tab)
    /// is whichever appears most in the first line.
    public static func csvRows(_ text: String) -> [[String]] {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = body.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = [",", ";", "\t"].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
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
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: - Columns

    private static let dateNames = ["date", "transaction date", "posting date", "posted date", "value date", "txn date", "trans date"]
    private static let descriptionNames = ["description", "details", "transaction details", "narrative", "narration", "merchant",
                                           "payee", "particulars", "memo", "name", "reference", "remarks"]
    private static let amountNames = ["amount", "transaction amount", "value"]
    private static let debitNames = ["debit", "debits", "debit amount", "withdrawal", "withdrawals", "money out", "paid out", "out"]
    private static let creditNames = ["credit", "credits", "credit amount", "deposit", "deposits", "money in", "paid in", "in"]

    public static func columns(header: [String]) -> StatementColumns? {
        let names = header.map { h in
            // "Amount (AED)" → "amount"
            h.lowercased().replacingOccurrences(of: #"\(.*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        func find(_ candidates: [String]) -> Int? {
            for c in candidates { if let i = names.firstIndex(of: c) { return i } }
            for c in candidates where c.count > 3 { if let i = names.firstIndex(where: { $0.contains(c) }) { return i } }
            return nil
        }
        guard let date = find(dateNames), let description = find(descriptionNames) else { return nil }
        let amount = find(amountNames)
        let debit = find(debitNames)
        let credit = find(creditNames)
        guard amount != nil || (debit != nil && credit != nil) else { return nil }
        return StatementColumns(date: date, description: description,
                                amount: debit != nil && credit != nil ? nil : amount, debit: debit, credit: credit)
    }

    // MARK: - Values

    /// Day-first formats come before month-first, as banks in the UAE and UK use them
    static let dateFormats = ["yyyy-MM-dd", "d/M/yyyy", "M/d/yyyy", "d-M-yyyy", "d.M.yyyy", "d MMM yyyy", "d-MMM-yyyy",
                              "d MMM yy", "d-MMM-yy", "d/M/yy", "yyyy/M/d", "MMM d, yyyy"]

    /// The first format that reads every date in the file
    static func dateFormat(for texts: [String], calendar: Calendar) -> DateFormatter? {
        for format in dateFormats {
            let f = formatter(format, calendar: calendar)
            if texts.allSatisfy({ parse($0, with: f) != nil }) { return f }
        }
        return nil
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        f.isLenient = false
        return f
    }

    private static func parse(_ text: String, with f: DateFormatter) -> Date? {
        if let d = f.date(from: text) { return d }
        // Some banks add a time: "25/10/2026 14:03" or "2026-10-25T14:03:00"
        if let time = text.range(of: #"[ T]\d{1,2}:\d{2}"#, options: .regularExpression) {
            return f.date(from: String(text[..<time.lowerBound]))
        }
        return nil
    }

    /// "1,234.50", "-45", "(45.00)", "45.00 DR", "AED 1.234,50"
    public static func amount(_ text: String, currency: String) -> Money? {
        var t = text.uppercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var negative = false
        if t.hasPrefix("(") && t.hasSuffix(")") { negative = true }
        if t.hasSuffix("DR") || t.hasSuffix("-") { negative = true }
        if t.contains("-") && !t.hasSuffix("-") { negative = true }
        t = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !t.isEmpty else { return nil }
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
        guard let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let money = Money(d, currency: currency)
        return negative ? -money : money
    }

    // MARK: - Reading

    /// Statement rows, oldest first. `flipSigns` is for card statements that show
    /// purchases as positive numbers.
    public static func read(_ text: String, currency: String, flipSigns: Bool = false,
                            calendar: Calendar) throws -> [StatementRow] {
        let rows = csvRows(text)
        guard rows.count > 1 else { throw ImportError.empty }
        // The header may sit below a few lines of account details
        guard let headerIndex = rows.prefix(15).firstIndex(where: { columns(header: $0) != nil }),
              let cols = columns(header: rows[headerIndex]) else { throw ImportError.unrecognisedColumns }
        let body = Array(rows.dropFirst(headerIndex + 1)).filter { $0.count > cols.date && !$0[cols.date].isEmpty }
        guard !body.isEmpty else { throw ImportError.empty }

        guard let f = dateFormat(for: body.map { $0[cols.date] }, calendar: calendar) else {
            let bad = body.first { r in dateFormats.allSatisfy { parse(r[cols.date], with: formatter($0, calendar: calendar)) == nil } }
            throw ImportError.unreadableDate(row: 1 + (bad.flatMap { b in body.firstIndex(of: b) } ?? 0), text: bad?[cols.date] ?? "")
        }

        var out: [StatementRow] = []
        for (n, r) in body.enumerated() {
            func field(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            let value: Money
            if let a = cols.amount {
                guard let m = amount(field(a), currency: currency) else {
                    throw ImportError.unreadableAmount(row: n + 1, text: field(a))
                }
                value = m
            } else {
                let debit = amount(field(cols.debit), currency: currency)?.magnitude ?? .zero(currency)
                let credit = amount(field(cols.credit), currency: currency)?.magnitude ?? .zero(currency)
                value = credit - debit
            }
            guard !value.isZero, let day = parse(r[cols.date], with: f) else { continue }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            out.append(StatementRow(id: n + 1, date: noon, description: field(cols.description),
                                    amount: flipSigns ? -value : value))
        }
        return out.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
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
                guard m.amount == row.amount else { return nil }
                let gap = abs(dayGap(row.date, m.date, calendar: calendar))
                return gap <= days ? (row.id, m.entryId, gap) : nil
            }
        }.sorted { ($0.gap, $0.row) < ($1.gap, $1.row) }
        for c in candidates where out[c.row] == nil {
            guard let i = unused.firstIndex(where: { $0.entryId == c.entry }) else { continue }
            unused.remove(at: i)
            out[c.row] = c.entry
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

    /// A loan instalment ("LOANRECOVERY-EMI:1139…", "MORTGAGE INSTALMENT") goes to the loan
    /// it names, else to the only loan there is
    public static func loan(for description: String, loans: [(id: UUID, name: String)]) -> UUID? {
        guard !loans.isEmpty else { return nil }
        let words = description.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let marks = ["loan", "emi", "instal", "mortgage", "finance", "repayment"]
        guard words.contains(where: { w in marks.contains { w == $0 || ($0.count > 3 && w.contains($0)) } }) else { return nil }
        if let named = account(for: description, accounts: loans) { return named }
        return loans.count == 1 ? loans[0].id : nil
    }

    /// "POS PURCHASE CARREFOUR CITY 1234 DUBAI AE" → ["carrefour", "city"]
    static func merchantWords(_ text: String, limit: Int = 3) -> [String] {
        let noise: Set = ["pos", "purchase", "card", "ae", "uae", "dubai", "abu", "dhabi", "sharjah", "llc", "the",
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
