//
//  StatementColumnFinder.swift
//  NokaelCore
//
//  Which column is which, worked out from what the columns hold rather than
//  what they're called, so it works in any language and any order: the date
//  column reads as dates, the money columns as amounts, and the balance is the
//  column that moves by each row's amount. Column names are only a hint for
//  what the values can't settle.
//

import Foundation

/// Something the values alone can't settle, for Apple Intelligence or the person to answer
public enum ColumnQuestion: Equatable, Sendable {
    /// Two money columns, one money out and the other money in, with no balance to tell which
    case outOrIn(Int, Int)
    /// Several columns hold amounts and nothing tells which is each row's amount
    case whichAmount([Int])
}

/// How many rows' amounts account for the change in the running balance
public struct BalanceCheck: Equatable, Sendable {
    /// Rows that have a balance and one before them to compare with
    public let rows: Int
    public let addUp: Int

    public var allAddUp: Bool { rows > 0 && addUp == rows }

    public init(rows: Int, addUp: Int) {
        self.rows = rows
        self.addUp = addUp
    }
}

/// The app's own reading of a statement's columns
public struct ColumnFinding: Equatable, Sendable {
    /// May be incomplete: then `question` says what's left
    public var columns: StatementColumns
    public var question: ColumnQuestion?
    public var check: BalanceCheck?
}

extension StatementImport {

    /// Each role found by its name alone, any of them nil
    static func columnsByName(_ header: [String]) -> StatementColumns {
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
        let debit = find(debitNames), credit = find(creditNames)
        return StatementColumns(date: find(dateNames), description: find(descriptionNames),
                                amount: debit != nil && credit != nil ? nil : find(amountNames), debit: debit, credit: credit,
                                balance: names.firstIndex { balanceNames.contains($0) })
    }

    /// Which column is which, from the rows under the column names
    public static func findColumns(header: [String], body: [[String]], currency: String, calendar: Calendar) -> ColumnFinding {
        let width = max(header.count, body.map(\.count).max() ?? 0)
        let rows = body.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        func cell(_ r: [String], _ c: Int) -> String { c < r.count ? r[c].trimmingCharacters(in: .whitespaces) : "" }
        func values(_ c: Int) -> [String] { rows.map { cell($0, c) }.filter { !$0.isEmpty } }
        let byName = columnsByName(header)
        let formatters = dateFormats.map { formatter($0, calendar: calendar) }
        func isDate(_ t: String) -> Bool { formatters.contains { parse(t, with: $0) != nil } }
        func share(_ c: Int, _ test: (String) -> Bool) -> Double {
            let v = values(c).prefix(40)
            return v.isEmpty ? 0 : Double(v.filter(test).count) / Double(v.count)
        }
        let filled = { (c: Int) in values(c).count }

        // Dates: a column where nearly every row reads as one. The first, unless its name says otherwise
        let dateColumns = (0..<width).filter { filled($0) * 2 >= rows.count && share($0, isDate) >= 0.8 }
        let date = byName.date.flatMap { dateColumns.contains($0) ? $0 : nil } ?? dateColumns.first

        // Money: nearly every value an amount. Long runs of digits are references; when some columns
        // write a decimal mark, ones that never do (card digits, counts) aren't money
        func isReference(_ c: Int) -> Bool { values(c).prefix(40).allSatisfy { $0.count >= 6 && $0.allSatisfy(\.isNumber) } }
        var money = (0..<width).filter { c in
            !dateColumns.contains(c) && filled(c) > 0 && share(c, { amount($0, currency: currency) != nil }) >= 0.8 && !isReference(c)
        }
        let marked = money.filter { c in values(c).contains { $0.contains(".") || $0.contains(",") } }
        if !marked.isEmpty { money = marked }
        // A column named for money whose values are amounts counts too, even when it's empty or has no decimals
        let named = [byName.amount, byName.debit, byName.credit, byName.balance].compactMap { $0 }.filter { c in
            !dateColumns.contains(c) && c < width && (filled(c) == 0 || share(c, { amount($0, currency: currency) != nil }) >= 0.8)
        }
        money = Array(Set(money).union(named)).sorted()

        var found = StatementColumns(date: date)
        var question: ColumnQuestion?
        var check: BalanceCheck?

        // The balance: the column each row's amount moves, from one row to the next
        let amounts: [Int: [Int64?]] = Dictionary(uniqueKeysWithValues: money.map { c in
            (c, rows.map { r in amount(cell(r, c), currency: currency)?.minorUnits })
        })
        var best: (columns: StatementColumns, check: BalanceCheck)?
        for b in money {
            let balance = amounts[b]!
            func consider(_ cols: StatementColumns, _ moved: (Int) -> Int64?, magnitude: Bool) {
                let fit = balanceFit(balance, moved: moved, magnitude: magnitude)
                // One pair that adds up exactly counts; with more, four in five must
                guard fit.rows >= 1, Double(fit.addUp) >= Double(fit.rows) * 0.8 else { return }
                if best == nil || fit.addUp > best!.check.addUp
                    || (fit.addUp == best!.check.addUp && cols.debit != nil && best!.columns.debit == nil) {
                    best = (cols, fit)
                }
            }
            for a in money where a != b {
                consider(StatementColumns(amount: a, balance: b), { amounts[a]![$0] }, magnitude: true)
            }
            for out in money where out != b {
                for into in money where into != b && into != out {
                    consider(StatementColumns(debit: out, credit: into, balance: b), { i in
                        let o = amounts[out]![i], n = amounts[into]![i]
                        guard o != nil || n != nil else { return nil }
                        return abs(n ?? 0) - abs(o ?? 0)
                    }, magnitude: false)
                }
            }
        }
        if let best {
            found.amount = best.columns.amount
            found.debit = best.columns.debit
            found.credit = best.columns.credit
            found.balance = best.columns.balance
            check = best.check
        } else if money.count == 1 {
            found.amount = money[0]
        } else if money.count == 2 {
            // Each row filled in one or the other: money out and money in
            let either = rows.filter { r in money.contains { !cell(r, $0).isEmpty } }
            let one = either.filter { r in money.filter { !cell(r, $0).isEmpty }.count == 1 }
            if !either.isEmpty, Double(one.count) >= Double(either.count) * 0.8 {
                if let d = byName.debit, let c = byName.credit, Set([d, c]) == Set(money) {
                    found.debit = d; found.credit = c
                } else {
                    question = .outOrIn(money[0], money[1])
                }
            } else if let a = byName.amount, money.contains(a) {
                found.amount = a
                found.balance = money.first { $0 != a }
            } else {
                question = .whichAmount(money)
            }
        } else if money.count > 2 {
            if let d = byName.debit, let c = byName.credit, money.contains(d), money.contains(c) {
                found.debit = d; found.credit = c
                found.balance = byName.balance.flatMap { money.contains($0) ? $0 : nil }
            } else if let a = byName.amount, money.contains(a) {
                found.amount = a
                found.balance = byName.balance.flatMap { money.contains($0) ? $0 : nil }
            } else {
                question = .whichAmount(money)
            }
        }

        // The description: the column of words that differ most from row to row
        let used = Set([found.date, found.amount, found.debit, found.credit, found.balance].compactMap { $0 } + dateColumns + money)
        let text = (0..<width).filter { c in
            !used.contains(c) && filled(c) > 0 && share(c, { $0.contains { $0.isLetter } }) >= 0.5
        }
        func variety(_ c: Int) -> Double {
            let v = values(c)
            let length = Double(v.map(\.count).reduce(0, +)) / Double(max(1, v.count))
            return Double(Set(v).count) / Double(max(1, v.count)) * length * Double(v.count) / Double(max(1, rows.count))
        }
        found.description = byName.description.flatMap { text.contains($0) ? $0 : nil } ?? text.max { variety($0) < variety($1) }

        // What the values couldn't fill, the names may: then reading says which value is wrong
        let taken = { (c: Int?) in c.map { c in [found.date, found.description, found.amount, found.debit, found.credit, found.balance].contains(c) } ?? true }
        if found.date == nil, !taken(byName.date) { found.date = byName.date }
        if found.description == nil, !taken(byName.description) { found.description = byName.description }
        if question == nil, found.amount == nil, found.debit == nil, found.credit == nil {
            if let d = byName.debit, let c = byName.credit, !taken(d), !taken(c) { found.debit = d; found.credit = c }
            else if !taken(byName.amount) { found.amount = byName.amount }
        }
        return ColumnFinding(columns: found, question: question, check: check)
    }

    /// How well a balance column follows the rows' amounts, read oldest first or newest first,
    /// whichever fits more rows. `magnitude` compares sizes only, for amounts printed without a sign.
    static func balanceFit(_ balance: [Int64?], moved: (Int) -> Int64?, magnitude: Bool) -> BalanceCheck {
        let have = balance.indices.filter { balance[$0] != nil }
        func fit(_ pairs: [(now: Int, before: Int)]) -> BalanceCheck {
            var addUp = 0
            for p in pairs {
                guard let m = moved(p.now) else { continue }
                let change = balance[p.now]! - balance[p.before]!
                if magnitude ? abs(change) == abs(m) : change == m { addUp += 1 }
            }
            return BalanceCheck(rows: pairs.count, addUp: addUp)
        }
        let oldestFirst = fit(zip(have.dropFirst(), have).map { ($0, $1) })
        let newestFirst = fit(zip(have, have.dropFirst()).map { ($0, $1) })
        return oldestFirst.addUp >= newestFirst.addUp ? oldestFirst : newestFirst
    }

    /// Each row's amount. One column of amounts that are never negative, beside a balance,
    /// takes its sign from which way the balance moved.
    static func rowValues(_ body: [[String]], cols: StatementColumns, currency: String) -> [Money?] {
        var out = body.map { signedValue($0, cols: cols, currency: currency) }
        guard cols.amount != nil, let b = cols.balance, !out.contains(where: { $0?.isNegative == true }) else { return out }
        let balance = body.map { b < $0.count ? amount($0[b], currency: currency)?.minorUnits : nil }
        let have = balance.indices.filter { balance[$0] != nil }
        func downs(_ pairs: [(now: Int, before: Int)]) -> [Int: Bool] {
            var d: [Int: Bool] = [:]
            for p in pairs {
                guard let m = out[p.now]?.minorUnits else { continue }
                let change = balance[p.now]! - balance[p.before]!
                if change == -m { d[p.now] = true } else if change == m { d[p.now] = false }
            }
            return d
        }
        let oldest = downs(zip(have.dropFirst(), have).map { ($0, $1) })
        let newest = downs(zip(have, have.dropFirst()).map { ($0, $1) })
        let moves = oldest.count >= newest.count ? oldest : newest
        // Only when the balance went down somewhere: otherwise there's nothing to learn
        guard moves.values.contains(true) else { return out }
        for (i, down) in moves where down { out[i] = out[i].map { -$0 } }
        return out
    }

    /// The balance check for columns already chosen
    public static func balanceCheck(_ text: String, currency: String, columns chosen: StatementColumns? = nil,
                                    calendar: Calendar) -> BalanceCheck? {
        let rows = csvRows(text)
        guard let found = resolve(rows, chosen: chosen, currency: currency, calendar: calendar),
              let b = found.columns.balance else { return nil }
        let body = rows.dropFirst(found.header + 1).filter { r in found.columns.date.map { $0 < r.count && !r[$0].isEmpty } ?? true }
        let balance = body.map { b < $0.count ? amount($0[b], currency: currency)?.minorUnits : nil }
        let values = rowValues(body, cols: found.columns, currency: currency)
        let fit = balanceFit(balance, moved: { values[$0]?.minorUnits }, magnitude: false)
        return fit.rows > 0 ? fit : nil
    }
}
