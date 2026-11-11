import Foundation
import Testing
@testable import NokaelCore

/// Choosing which column is which, for files the app can't read on its own or reads wrongly
struct StatementColumnsTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Column names the app doesn't know
    let odd = """
    Booked,Shop,Sum,Left
    03.11.2026,REWE Markt,-23.40,976.60
    04.11.2026,Gehalt November,2500.00,3476.60
    """

    @Test func unknownNamesAreWorkedOutFromTheValuesAndCanBeChosen() throws {
        let layout = try #require(StatementImport.layout(in: odd, currency: "EUR", calendar: calendar))
        #expect(layout.headerIndex == 0)
        // Dates, words, and a balance that moves by each amount: no names needed
        #expect(layout.guess == StatementColumns(date: 0, description: 1, amount: 2, balance: 3))
        #expect(layout.check == BalanceCheck(rows: 1, addUp: 1))
        #expect(layout.names == ["Booked", "Shop", "Sum", "Left"])
        #expect(layout.sample(1) == "REWE Markt")
        #expect(try StatementImport.read(odd, currency: "EUR", calendar: calendar).count == 2)

        let chosen = StatementColumns(date: 0, description: 1, amount: 2, balance: 3)
        let rows = try StatementImport.read(odd, currency: "EUR", columns: chosen, calendar: calendar)
        #expect(rows.map(\.description) == ["REWE Markt", "Gehalt November"])
        #expect(rows.map(\.amount) == [Money(Decimal(string: "-23.40")!, currency: "EUR"), Money(2500, currency: "EUR")])
        let b = try #require(StatementImport.balances(in: odd, currency: "EUR", columns: chosen, calendar: calendar))
        #expect(b.closing == Money(Decimal(string: "3476.60")!, currency: "EUR"))
        #expect(b.opening == Money(1000, currency: "EUR"))
    }

    @Test func aChoiceReplacesTheGuess() throws {
        // The app picks Details as the description; the person wants Merchant
        let csv = """
        Date,Details,Merchant,Amount
        2026-11-03,CARD 1234 POS 0311,Corner Cafe,-4.50
        """
        let guessed = try StatementImport.read(csv, currency: "GBP", calendar: calendar)
        #expect(guessed.first?.description == "CARD 1234 POS 0311")
        let layout = try #require(StatementImport.layout(in: csv))
        var cols = try #require(layout.guess)
        cols.description = 2
        let chosen = try StatementImport.read(csv, currency: "GBP", columns: cols, calendar: calendar)
        #expect(chosen.first?.description == "Corner Cafe")
    }

    @Test func separateMoneyInAndOut() throws {
        let csv = """
        When,What,Out,In
        05/11/2026,Rent,1200,
        06/11/2026,Refund,,30
        """
        let cols = StatementColumns(date: 0, description: 1, debit: 2, credit: 3)
        let rows = try StatementImport.read(csv, currency: "USD", columns: cols, calendar: calendar)
        #expect(rows.map(\.amount) == [Money(-1200, currency: "USD"), Money(30, currency: "USD")])
    }

    @Test func anIncompleteChoiceFallsBackToTheGuess() throws {
        let partial = StatementColumns(date: 0)
        #expect(!partial.isComplete)
        #expect(partial.missing == ["description", "amount"])
        #expect(StatementColumns(date: 0, description: 1, debit: 2).missing == ["money in"])
        // The values settle the rest
        #expect(try StatementImport.read(odd, currency: "EUR", columns: partial, calendar: calendar).count == 2)
        // Nothing to go on: still asks
        #expect(throws: ImportError.unrecognisedColumns) {
            try StatementImport.read("a,b,c\nx,y,z\nq,r,s", currency: "EUR", columns: partial, calendar: calendar)
        }
    }

    @Test func namesBelowAccountDetailsAreFound() throws {
        let csv = """
        Konto: DE00 1234 5678
        Zeitraum: November 2026
        Tag;Text;Wert
        03.11.2026;Bäckerei;-3,20
        """
        let layout = try #require(StatementImport.layout(in: csv))
        #expect(layout.headerIndex == 2)
        #expect(layout.names == ["Tag", "Text", "Wert"])
        let rows = try StatementImport.read(csv, currency: "EUR", columns: StatementColumns(date: 0, description: 1, amount: 2),
                                            calendar: calendar)
        #expect(rows.first?.amount == Money(Decimal(string: "-3.20")!, currency: "EUR"))
    }

    @Test func germanNamesAreGuessed() throws {
        let csv = """
        Buchungstag;Verwendungszweck;Betrag
        03.11.2026;Miete;-850,00
        """
        let layout = try #require(StatementImport.layout(in: csv))
        #expect(layout.guess == StatementColumns(date: 0, description: 1, amount: 2))
    }

    @Test func tablesBecomeCSVThatReadsBack() throws {
        let grid = [["Date", "Description", "Amount"], ["2026-11-03", "Shop, Ltd \"Main\"", "-12.00"]]
        let text = StatementImport.csvText(grid)
        #expect(StatementImport.csvRows(text) == grid)
        let rows = try StatementImport.read(text, currency: "EUR", calendar: calendar)
        #expect(rows.first?.description == "Shop, Ltd \"Main\"")
    }

    @Test func choiceSurvivesSaving() throws {
        let cols = StatementColumns(date: 1, description: 3, debit: 4, credit: 5, balance: 6)
        let data = try JSONEncoder().encode(cols)
        #expect(try JSONDecoder().decode(StatementColumns.self, from: data) == cols)
    }
}
