import Foundation
import Testing
@testable import NokaelCore

@Suite struct BillMatchTests {
    let f = Fixture()
    let cal = Fixture.dubai
    var aed: (Decimal) -> Money { Fixture.aed }

    func rent() -> (PlannedItem, Occurrence) {
        let item = PlannedItem(name: "Rent", direction: .outflow, amount: aed(2500),
                               schedule: Schedule(start: Fixture.date(2026, 10, 27), frequency: .monthly(every: 1)),
                               accountId: f.current.id, categoryId: f.rent.id)
        return (item, Occurrence(itemId: item.id, dueDate: Fixture.date(2026, 10, 27, 8), expected: aed(2500)))
    }

    var accounts: [UUID: AccountInfo] { Dictionary(uniqueKeysWithValues: f.all.map { ($0.id, $0) }) }

    @Test("T01: rent already recorded as a plain expense is suggested, never linked by itself")
    func alreadyRecordedRent() throws {
        let (item, occ) = rent()
        let entry = try EntryFactory.expense(aed(2500), from: f.current, category: f.rent, date: Fixture.date(2026, 10, 27, 7),
                                             memo: "Rent or mortgage")
        let payment = try #require(BillPayment(entry, accounts: accounts))
        let matches = BillMatcher.candidates(for: payment, occurrences: [occ], items: [item], calendar: cal)
        #expect(matches.map(\.occurrenceId) == [occ.id])
        #expect(matches.first?.isPartial == false)
        #expect(occ.paid.isZero) // suggesting changes nothing
    }

    @Test("T04: an unrelated 2,500 from the same account is not rent")
    func unrelatedExpense() throws {
        let (item, occ) = rent()
        let entry = try EntryFactory.expense(aed(2500), from: f.current, category: f.groceries,
                                             date: Fixture.date(2026, 10, 27), memo: "Carrefour")
        let payment = try #require(BillPayment(entry, accounts: accounts))
        #expect(BillMatcher.candidates(for: payment, occurrences: [occ], items: [item], calendar: cal).isEmpty)

        // A bill without a category needs its name; account and amount alone aren't enough
        var bare = item; bare.categoryId = nil
        let other = BillPayment(date: Fixture.date(2026, 10, 27), amount: aed(2500), fromAccountId: f.current.id,
                                categoryId: nil, debtId: nil, memo: "Furniture")
        #expect(BillMatcher.candidates(for: other, occurrences: [occ], items: [bare], calendar: cal).isEmpty)
    }

    @Test("Too far from the due date, or more than is left, is no match")
    func outsideTheWindow() {
        let (item, occ) = rent()
        let late = BillPayment(date: Fixture.date(2026, 12, 1), amount: aed(2500), fromAccountId: f.current.id,
                               categoryId: f.rent.id, debtId: nil, memo: "Rent")
        #expect(BillMatcher.candidates(for: late, occurrences: [occ], items: [item], calendar: cal).isEmpty)
        let over = BillPayment(date: Fixture.date(2026, 10, 27), amount: aed(2600), fromAccountId: f.current.id,
                               categoryId: f.rent.id, debtId: nil, memo: "Rent")
        #expect(BillMatcher.candidates(for: over, occurrences: [occ], items: [item], calendar: cal).isEmpty)
    }

    @Test("T02/T03: two instalments settle one bill, and unlinking one reopens it")
    func partialPayments() {
        let (item, start) = rent()
        var occ = start
        let first = BillPayment(date: Fixture.date(2026, 10, 25), amount: aed(1000), fromAccountId: f.current.id,
                                categoryId: f.rent.id, debtId: nil, memo: "Rent part 1")
        let match = BillMatcher.candidates(for: first, occurrences: [occ], items: [item], calendar: cal)
        #expect(match.first?.isPartial == true)

        let a = UUID(), b = UUID()
        occ.recordPayment(entryId: a, amount: aed(1000))
        #expect(occ.state(today: Fixture.date(2026, 10, 26), calendar: cal) == .partiallyPaid)
        #expect(occ.remaining == aed(1500))

        let second = BillPayment(date: Fixture.date(2026, 10, 27), amount: aed(1500), fromAccountId: f.current.id,
                                 categoryId: f.rent.id, debtId: nil, memo: "Rent")
        #expect(BillMatcher.candidates(for: second, occurrences: [occ], items: [item], calendar: cal).first?.isPartial == false)
        occ.recordPayment(entryId: b, amount: aed(1500))
        #expect(occ.state(today: Fixture.date(2026, 10, 27), calendar: cal) == .paid)

        occ.removePayment(entryId: a, amount: aed(1000))
        #expect(occ.remaining == aed(1000))
        #expect(occ.state(today: Fixture.date(2026, 10, 28), calendar: cal) == .partiallyPaid)
    }

    @Test("T06: a transfer to the card matches only the card's bill, and stays a transfer")
    func cardRepayment() throws {
        let cardBill = PlannedItem(name: "Credit card payment", direction: .outflow, amount: aed(800),
                                   schedule: Schedule(start: Fixture.date(2026, 10, 20), frequency: .monthly(every: 1)),
                                   accountId: f.current.id, debtId: f.card.id)
        let (rentItem, rentOcc) = rent()
        let cardOcc = Occurrence(itemId: cardBill.id, dueDate: Fixture.date(2026, 10, 20), expected: aed(800))
        let entry = try EntryFactory.transfer(aed(800), from: f.current, to: f.card, date: Fixture.date(2026, 10, 19))
        let payment = try #require(BillPayment(entry, accounts: accounts))
        #expect(payment.debtId == f.card.id && payment.categoryId == nil)
        let matches = BillMatcher.candidates(for: payment, occurrences: [rentOcc, cardOcc], items: [rentItem, cardBill], calendar: cal)
        #expect(matches.map(\.occurrenceId) == [cardOcc.id])

        // Linking doesn't add spending: the ledger still sees one transfer
        var linked = entry; linked.occurrenceId = cardOcc.id
        let ledger = f.ledger([linked])
        #expect(ledger.activity(on: f.interest.id, from: Fixture.date(2026, 10, 1), to: Fixture.date(2026, 11, 1)).isZero)
        #expect(ledger.balance(of: f.card.id) == aed(800))

        // An expense is never a card bill
        let spend = BillPayment(date: Fixture.date(2026, 10, 19), amount: aed(800), fromAccountId: f.current.id,
                                categoryId: nil, debtId: nil, memo: "Credit card payment")
        #expect(BillMatcher.candidates(for: spend, occurrences: [cardOcc], items: [cardBill], calendar: cal).isEmpty)
    }

    @Test("Income and moves between own cash accounts are never bill payments")
    func notPayments() throws {
        let income = try EntryFactory.income(aed(100), to: f.current, category: f.salary, date: Fixture.date(2026, 10, 1))
        let move = try EntryFactory.transfer(aed(100), from: f.current, to: f.savings, date: Fixture.date(2026, 10, 1))
        #expect(BillPayment(income, accounts: accounts) == nil)
        #expect(BillPayment(move, accounts: accounts) == nil)
    }

    @Test("T09: voiding the payment that settled an estimate puts the estimate back")
    func estimateRestored() {
        var occ = Occurrence(itemId: UUID(), dueDate: Fixture.date(2026, 10, 28), expected: aed(400), isEstimate: true)
        let paid = UUID()
        occ.recordPayment(entryId: paid, amount: aed(350))
        #expect(occ.expected == aed(350) && !occ.isEstimate && occ.remaining.isZero)
        occ.removePayment(entryId: paid, amount: aed(350))
        #expect(occ.expected == aed(400) && occ.isEstimate && occ.paid.isZero)
    }

    @Test("T11: skipped bills are never suggested")
    func skipped() {
        let (item, start) = rent()
        var occ = start; occ.skipped = true
        let p = BillPayment(date: Fixture.date(2026, 10, 27), amount: aed(2500), fromAccountId: f.current.id,
                            categoryId: f.rent.id, debtId: nil, memo: "Rent")
        #expect(BillMatcher.candidates(for: p, occurrences: [occ], items: [item], calendar: cal).isEmpty)
    }

    @Test("T10: archived accounts aren't in net worth")
    func archivedNetWorth() throws {
        var old = AccountInfo(name: "Old bank", kind: .bank, currency: "AED")
        old.archived = true
        let open = try EntryFactory.openingBalance(aed(300), for: old, equity: f.equity, date: Fixture.date(2026, 1, 1))
        let ledger = Ledger(accounts: f.all + [old], entries: [open], currency: "AED")
        #expect(ledger.netWorth().assets.isZero)
    }
}
