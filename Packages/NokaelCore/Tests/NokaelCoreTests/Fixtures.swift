import Foundation
@testable import NokaelCore

/// A small household in Dubai, used across tests
struct Fixture {
    static let dubai: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        dubai.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func aed(_ major: Decimal) -> Money { Money(major, currency: "AED") }

    let current = AccountInfo(name: "Current account", kind: .bank, currency: "AED")
    let second = AccountInfo(name: "Second bank", kind: .bank, currency: "AED")
    let savings = AccountInfo(name: "Savings", kind: .savings, currency: "AED")
    let card = AccountInfo(name: "Credit card", kind: .creditCard, currency: "AED")
    let carLoan = AccountInfo(name: "Car loan", kind: .loan, currency: "AED")
    let equity = AccountInfo(name: "Opening balances", kind: .equity, currency: "AED")
    let salary = AccountInfo(name: "Salary", kind: .income, currency: "AED")
    let groceries = AccountInfo(name: "Groceries", kind: .expense, currency: "AED")
    let transport = AccountInfo(name: "Transport", kind: .expense, currency: "AED")
    let rent = AccountInfo(name: "Rent", kind: .expense, currency: "AED")
    let interest = AccountInfo(name: "Interest & fees", kind: .expense, currency: "AED")

    var all: [AccountInfo] { [current, second, savings, card, carLoan, equity, salary, groceries, transport, rent, interest] }

    func ledger(_ entries: [Entry]) -> Ledger { Ledger(accounts: all, entries: entries, currency: "AED") }
}
