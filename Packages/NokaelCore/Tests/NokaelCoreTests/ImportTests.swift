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
        let rows = try StatementImport.read(csv, currency: "AED", calendar: Fixture.dubai)
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
        let rows = try StatementImport.read(csv, currency: "AED", calendar: Fixture.dubai)
        #expect(rows.map(\.amount) == [aed(-1250), aed(99.5)])
        #expect(rows[0].date == Fixture.date(2026, 10, 3))
    }

    @Test func cardStatementsCanFlipSigns() throws {
        let csv = "Date,Merchant,Amount\n10 Oct 2026,Talabat,85.00\n15 Oct 2026,Payment received,-2000.00"
        let rows = try StatementImport.read(csv, currency: "AED", flipSigns: true, calendar: Fixture.dubai)
        #expect(rows.map(\.amount) == [aed(-85), aed(2000)])
    }

    @Test func explainsWhatItCantRead() {
        #expect(throws: ImportError.unrecognisedColumns) {
            try StatementImport.read("a,b,c\n1,2,3", currency: "AED", calendar: Fixture.dubai)
        }
        #expect(throws: ImportError.unreadableAmount(row: 1, text: "abc")) {
            try StatementImport.read("Date,Description,Amount\n01/10/2026,Shop,abc", currency: "AED", calendar: Fixture.dubai)
        }
        #expect(throws: ImportError.unreadableDate(row: 2, text: "yesterday")) {
            try StatementImport.read("Date,Description,Amount\n01/10/2026,Shop,-5\nyesterday,Shop,-6",
                                     currency: "AED", calendar: Fixture.dubai)
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
        let matched = StatementImport.match(rows, with: recorded, calendar: Fixture.dubai)
        #expect(matched == [2: a, 1: b])
    }

    @Test func aNearerRowDoesNotLeaveAnotherRowUnmatched() {
        // Rows on the 1st and 5th; entries on the 4th and 8th. Pairing the 5th with the 4th because it's
        // nearest would leave the 1st with nothing, and it would be imported as a second payment
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        paris.firstWeekday = 2
        func day(_ d: Int) -> Date { paris.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
        let eur = { (v: Decimal) in Money(v, currency: "EUR") }
        let early = UUID(), late = UUID()
        let rows = [StatementRow(id: 1, date: day(1), description: "Boulangerie", amount: eur(-12.5)),
                    StatementRow(id: 2, date: day(5), description: "Boulangerie", amount: eur(-12.5))]
        let recorded = [RecordedMovement(entryId: early, date: day(4), amount: eur(-12.5)),
                        RecordedMovement(entryId: late, date: day(8), amount: eur(-12.5))]
        #expect(StatementImport.match(rows, with: recorded, calendar: paris) == [1: early, 2: late])
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

struct InternationalStatementTests {
    @Test func readsColumnNamesInOtherLanguages() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let german = try StatementImport.read("Buchungstag;Verwendungszweck;Betrag\n08.11.2026;REWE MARKT;-12,50", currency: "EUR", calendar: berlin)
        #expect(german.map(\.amount) == [Money(Decimal(string: "-12.5")!, currency: "EUR")])
        let french = try StatementImport.read("Date;Libellé;Débit;Crédit\n08/11/2026;CARTE MONOPRIX;23,10;", currency: "EUR", calendar: berlin)
        #expect(french.map(\.amount) == [Money(Decimal(string: "-23.1")!, currency: "EUR")])
        let spanish = try StatementImport.read("Fecha,Concepto,Importe\n08/11/2026,MERCADONA,-30.00", currency: "EUR", calendar: berlin)
        #expect(spanish.first?.description == "MERCADONA")
    }

    @Test func aDateWithSomethingStuckToItIsStillRead() throws {
        // As a scanned page can read it: a stray mark between the date and the time
        let csv = "Posting Date,Description,Amount\n\"11/11/2026\u{142} 00:57:13\",Shop,-5.00\n10/11/2026 23:00:38,Pay,10.00"
        let rows = try StatementImport.read(csv, currency: "AED", calendar: Fixture.dubai)
        #expect(rows.count == 2)
        #expect(rows.contains { Fixture.dubai.component(.day, from: $0.date) == 11 && Fixture.dubai.component(.month, from: $0.date) == 11 })
        // Something that isn't a date at all still says so
        #expect(throws: ImportError.self) {
            try StatementImport.read("Date,Description,Amount\n10317130,Shop,-5.00", currency: "AED", calendar: Fixture.dubai)
        }
    }
}
