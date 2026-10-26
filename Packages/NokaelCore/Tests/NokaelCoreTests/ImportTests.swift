import Foundation
import Testing
@testable import NokaelCore

struct ImportTests {
    let cal = Fixture.dubai
    let aed = Fixture.aed

    @Test func readsASignedAmountStatementWithQuotesAndDayFirstDates() throws {
        let csv = """
        Account,Current account
        Date,Description,Amount (AED),Balance
        05/10/2026,"CARREFOUR CITY, DUBAI",-245.50,"11,754.50"
        01/10/2026,SALARY OCT,"20,000.00","12,000.00"
        12/10/2026,DEWA 1234,(410.00),"11,344.50"
        """
        let rows = try StatementImport.read(csv, currency: "AED", calendar: cal)
        #expect(rows.map(\.amount) == [aed(20000), aed(-245.5), aed(-410)])
        #expect(rows[1].description == "CARREFOUR CITY, DUBAI")
        // 05/10 is 5 October, not 10 May
        #expect(rows[1].date == Fixture.date(2026, 10, 5))
    }

    @Test func readsDebitAndCreditColumnsSemicolonsAndTimes() throws {
        let csv = """
        Transaction Date;Details;Debit;Credit
        2026-10-03 09:15;Noon.com;1.250,00;
        2026-10-04 18:40;Refund Noon;;99,50
        """
        let rows = try StatementImport.read(csv, currency: "AED", calendar: cal)
        #expect(rows.map(\.amount) == [aed(-1250), aed(99.5)])
        #expect(rows[0].date == Fixture.date(2026, 10, 3))
    }

    @Test func cardStatementsCanFlipSigns() throws {
        let csv = "Date,Merchant,Amount\n10 Oct 2026,Talabat,85.00\n15 Oct 2026,Payment received,-2000.00"
        let rows = try StatementImport.read(csv, currency: "AED", flipSigns: true, calendar: cal)
        #expect(rows.map(\.amount) == [aed(-85), aed(2000)])
    }

    @Test func explainsWhatItCantRead() {
        #expect(throws: ImportError.unrecognisedColumns) {
            try StatementImport.read("a,b,c\n1,2,3", currency: "AED", calendar: cal)
        }
        #expect(throws: ImportError.unreadableAmount(row: 1, text: "abc")) {
            try StatementImport.read("Date,Description,Amount\n01/10/2026,Shop,abc", currency: "AED", calendar: cal)
        }
        #expect(throws: ImportError.unreadableDate(row: 2, text: "yesterday")) {
            try StatementImport.read("Date,Description,Amount\n01/10/2026,Shop,-5\nyesterday,Shop,-6",
                                     currency: "AED", calendar: cal)
        }
    }

    @Test func matchesRecordedEntriesOnceEachNearestDateFirst() {
        let a = UUID(), b = UUID()
        let rows = [
            StatementRow(id: 1, date: Fixture.date(2026, 10, 5), description: "Taxi", amount: aed(-30)),
            StatementRow(id: 2, date: Fixture.date(2026, 10, 7), description: "Taxi", amount: aed(-30)),
            StatementRow(id: 3, date: Fixture.date(2026, 10, 7), description: "Taxi", amount: aed(-30)),
            StatementRow(id: 4, date: Fixture.date(2026, 10, 20), description: "Taxi", amount: aed(-30)),
        ]
        let recorded = [RecordedMovement(entryId: a, date: Fixture.date(2026, 10, 7), amount: aed(-30)),
                        RecordedMovement(entryId: b, date: Fixture.date(2026, 10, 4), amount: aed(-30))]
        let matched = StatementImport.match(rows, with: recorded, calendar: cal)
        #expect(matched == [2: a, 1: b])
    }

    @Test func findsTheBillARowPays() {
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: aed(5000),
                               schedule: Schedule(start: Fixture.date(2026, 10, 1), frequency: .monthly(every: 1)))
        let dewa = PlannedItem(name: "DEWA", direction: .outflow, amount: aed(400), isEstimate: true,
                               schedule: Schedule(start: Fixture.date(2026, 10, 10), frequency: .monthly(every: 1)))
        let occs = [Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000)),
                    Occurrence(itemId: dewa.id, dueDate: Fixture.date(2026, 10, 10), expected: aed(400), isEstimate: true)]
        func row(_ d: Int, _ m: Int, _ amount: Decimal) -> StatementRow {
            StatementRow(id: 1, date: Fixture.date(2026, m, d), description: "x", amount: aed(amount))
        }
        let account = UUID()
        #expect(StatementImport.bill(for: row(30, 10, -5000), occurrences: occs, items: [rent, dewa], accountId: account, calendar: cal)?.itemId == rent.id)
        #expect(StatementImport.bill(for: row(12, 10, -455), occurrences: occs, items: [rent, dewa], accountId: account, calendar: cal)?.itemId == dewa.id)
        #expect(StatementImport.bill(for: row(12, 10, -900), occurrences: occs, items: [rent, dewa], accountId: account, calendar: cal) == nil)
        #expect(StatementImport.bill(for: row(20, 10, -5000), occurrences: occs, items: [rent, dewa], accountId: account, calendar: cal) == nil)
    }

    @Test func remembersCategoriesForTheSameShop() {
        let groceries = UUID()
        let history = [(memo: "Carrefour City", categoryId: groceries)]
        #expect(StatementImport.category(for: "POS PURCHASE CARREFOUR CITY 4411 DUBAI AE", history: history) == groceries)
        #expect(StatementImport.category(for: "Spinneys", history: history) == nil)
        #expect(StatementImport.category(for: "CARREFOUR", history: [(memo: "Carrefour Mall of the Emirates", categoryId: groceries)]) == groceries)
    }

    @Test func spotsTransfersThatNameAnotherAccount() {
        let card = UUID(), savings = UUID()
        let accounts = [(id: card, name: "Mashreq Cashback"), (id: savings, name: "Wio Savings")]
        #expect(StatementImport.account(for: "MASHREQ CARD PAYMENT", accounts: accounts) == card)
        #expect(StatementImport.account(for: "TRANSFER TO WIO 0042", accounts: accounts) == savings)
        #expect(StatementImport.account(for: "SAVINGS INTEREST", accounts: accounts) == nil)
    }
}
