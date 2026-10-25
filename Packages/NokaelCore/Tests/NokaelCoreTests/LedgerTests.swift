import Foundation
import Testing
@testable import NokaelCore

struct MoneyTests {
    @Test func decimalsStayExact() {
        let a = Money(Decimal(string: "0.10")!, currency: "AED")
        let b = Money(Decimal(string: "0.20")!, currency: "AED")
        #expect((a + b) == Money(Decimal(string: "0.30")!, currency: "AED"))
        #expect((a + b).minorUnits == 30)
    }

    @Test func roundsHalfAwayFromZeroAtCurrencyPrecision() {
        #expect(Money(Decimal(string: "1.005")!, currency: "AED").minorUnits == 101)
        #expect(Money(Decimal(string: "1.0005")!, currency: "KWD").minorUnits == 1001)
        #expect(Money(Decimal(string: "-2.5")!, currency: "JPY").minorUnits == -3)
    }

    @Test func parsesWhatPeopleType() {
        #expect(MoneyFormat.parse("1,250.5", currency: "AED")?.minorUnits == 125050)
        #expect(MoneyFormat.parse("85", currency: "AED")?.minorUnits == 8500)
        #expect(MoneyFormat.parse("", currency: "AED") == nil)
        #expect(MoneyFormat.parse("abc", currency: "AED") == nil)
    }
}

struct LedgerTests {
    let f = Fixture()
    let d = Fixture.date(2026, 10, 1)

    @Test func everyEntryBalances() throws {
        let bad = Entry(kind: .expense, date: d, lines: [Line(accountId: f.current.id, amount: Fixture.aed(-10))])
        #expect(throws: LedgerError.unbalanced(Fixture.aed(-10))) { try EntryFactory.validate(bad) }
        #expect(throws: LedgerError.amountMustBePositive) {
            try EntryFactory.expense(Fixture.aed(0), from: f.current, category: f.groceries, date: d)
        }
        #expect(throws: LedgerError.sameAccount) {
            try EntryFactory.transfer(Fixture.aed(5), from: f.current, to: f.current, date: d)
        }
        #expect(throws: LedgerError.reasonRequired) {
            try EntryFactory.adjustment(Fixture.aed(5), account: f.current, equity: f.equity, date: d, reason: "  ")
        }
    }

    @Test("QA-01: opening balance shows before other entries")
    func qa01OpeningBalance() throws {
        let ledger = f.ledger([try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: d)])
        #expect(ledger.balance(of: f.current.id) == Fixture.aed(12000))
        #expect(ledger.netWorth().total == Fixture.aed(12000))
    }

    @Test("QA-02: transfers between own accounts leave net worth unchanged")
    func qa02Transfer() throws {
        var entries = [
            try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: d),
            try EntryFactory.openingBalance(Fixture.aed(500), for: f.second, equity: f.equity, date: d)
        ]
        let before = f.ledger(entries).netWorth().total
        entries.append(try EntryFactory.transfer(Fixture.aed(1000), from: f.current, to: f.second, date: d))
        let after = f.ledger(entries)
        #expect(after.netWorth().total == before)
        #expect(after.balance(of: f.current.id) == Fixture.aed(11000))
        #expect(after.balance(of: f.second.id) == Fixture.aed(1500))
    }

    @Test("QA-03: spending AED 85 on groceries updates account and category once")
    func qa03Groceries() throws {
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: d),
            try EntryFactory.expense(Fixture.aed(85), from: f.current, category: f.groceries, date: d)
        ])
        #expect(ledger.balance(of: f.current.id) == Fixture.aed(11915))
        #expect(ledger.activity(on: f.groceries.id, from: Fixture.date(2026, 10, 1, 0), to: Fixture.date(2026, 11, 1, 0)) == Fixture.aed(85))
    }

    @Test("QA-07: loan payment of 1,000 with 150 interest")
    func qa07LoanPayment() throws {
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(5000), for: f.current, equity: f.equity, date: d),
            try EntryFactory.openingBalance(Fixture.aed(-30000), for: f.carLoan, equity: f.equity, date: d),
            try EntryFactory.debtPayment(principal: Fixture.aed(850), interest: Fixture.aed(150), fees: Fixture.aed(0),
                                         from: f.current, debt: f.carLoan, interestCategory: f.interest, date: d)
        ])
        #expect(ledger.balance(of: f.current.id) == Fixture.aed(4000))           // cash −1,000
        #expect(ledger.balance(of: f.carLoan.id) == Fixture.aed(-29150))         // principal −850
        #expect(ledger.activity(on: f.interest.id, from: d, to: d.addingTimeInterval(1)) == Fixture.aed(150)) // interest +150
    }

    @Test("QA-12: assets 12,000 and debts 38,000 give net worth −26,000")
    func qa12NegativeNetWorth() throws {
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: d),
            try EntryFactory.openingBalance(Fixture.aed(-30000), for: f.carLoan, equity: f.equity, date: d),
            try EntryFactory.openingBalance(Fixture.aed(-8000), for: f.card, equity: f.equity, date: d)
        ])
        let worth = ledger.netWorth()
        #expect(worth.assets == Fixture.aed(12000))
        #expect(worth.liabilities == Fixture.aed(38000))
        #expect(worth.total == Fixture.aed(-26000))
        // The card is shown as owed, not turned positive
        #expect(ledger.balance(of: f.card.id) == Fixture.aed(-8000))
    }

    @Test func voidedEntriesDoNotCount() throws {
        var spend = try EntryFactory.expense(Fixture.aed(40), from: f.current, category: f.groceries, date: d)
        spend.status = .void
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(100), for: f.current, equity: f.equity, date: d),
            spend
        ])
        #expect(ledger.balance(of: f.current.id) == Fixture.aed(100))
    }

    @Test func runningBalanceIsReproducible() throws {
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(100), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 1)),
            try EntryFactory.expense(Fixture.aed(30), from: f.current, category: f.groceries, date: Fixture.date(2026, 10, 2)),
            try EntryFactory.income(Fixture.aed(50), to: f.current, category: f.salary, date: Fixture.date(2026, 10, 3))
        ])
        let rows = ledger.runningBalance(of: f.current.id)
        #expect(rows.map(\.balance) == [Fixture.aed(100), Fixture.aed(70), Fixture.aed(120)])
        #expect(rows.last?.balance == ledger.balance(of: f.current.id))
    }
}
