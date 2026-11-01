//
//  StatementInsights.swift
//  NokaelCore
//
//  What a statement says about someone's month: their pay, a loan instalment,
//  bills that come back at the same amount. Offered after an import for the
//  person to confirm, never set up on their own.
//

import Foundation

public struct StatementFinding: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case pay, loan, bill
    }

    public let kind: Kind
    /// A short name to show: "Salary", "Loan", "Du Mobile"
    public let name: String
    /// Always positive
    public let amount: Money
    /// When it should come next, a month after it was last seen
    public let nextDate: Date

    public var id: String { "\(kind.rawValue)|\(name.lowercased())|\(amount.minorUnits)" }

    public init(kind: Kind, name: String, amount: Money, nextDate: Date) {
        self.kind = kind
        self.name = name
        self.amount = amount
        self.nextDate = nextDate
    }
}

public enum StatementInsights {
    /// Pay first, then loan instalments, then bills that repeat, each found once
    public static func findings(_ rows: [StatementRow], today: Date, calendar: Calendar) -> [StatementFinding] {
        var out: [StatementFinding] = []
        func next(after date: Date) -> Date {
            var d = date
            while d <= today { d = calendar.date(byAdding: .month, value: 1, to: d) ?? today.addingTimeInterval(86_400) }
            return d
        }

        // Pay: the largest money in that says it's salary
        if let pay = rows.filter({ $0.amount.isPositive && CategoryRules.saysSalary($0.description) }).max(by: { $0.amount < $1.amount }) {
            out.append(StatementFinding(kind: .pay, name: "Salary", amount: pay.amount, nextDate: next(after: pay.date)))
        }

        // Loan instalments: one per amount, the latest date
        let loans = rows.filter { $0.amount.isNegative && CategoryRules.isLoanPayment($0.description) }
        for (_, group) in Dictionary(grouping: loans, by: { $0.amount }) {
            guard let last = group.max(by: { $0.date < $1.date }) else { continue }
            out.append(StatementFinding(kind: .loan, name: "Loan", amount: last.amount.magnitude, nextDate: next(after: last.date)))
        }

        // Bills: the same payee and amount in two or more months, not money to people or a loan
        let spending = rows.filter {
            $0.amount.isNegative && !CategoryRules.isLoanPayment($0.description) && !CategoryRules.isSentToPeople($0.description)
        }
        let byPayee = Dictionary(grouping: spending) { row in
            "\(StatementImport.merchantWords(row.description).joined(separator: " "))|\(row.amount.minorUnits)"
        }
        for (key, group) in byPayee where !key.hasPrefix("|") {
            let months = Set(group.map { calendar.dateComponents([.year, .month], from: $0.date) })
            guard months.count >= 2, let last = group.max(by: { $0.date < $1.date }) else { continue }
            let name = StatementImport.merchantWords(last.description).map(\.capitalized).joined(separator: " ")
            out.append(StatementFinding(kind: .bill, name: name, amount: last.amount.magnitude, nextDate: next(after: last.date)))
        }

        return out.sorted { a, b in
            let order: [StatementFinding.Kind] = [.pay, .loan, .bill]
            return (order.firstIndex(of: a.kind)!, b.amount) < (order.firstIndex(of: b.kind)!, a.amount)
        }
    }
}
