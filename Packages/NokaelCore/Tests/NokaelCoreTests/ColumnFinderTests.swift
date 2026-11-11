import Foundation
import Testing
@testable import NokaelCore

/// Which column is which, from the values: any language, any order. Made-up statements.
struct ColumnFinderTests {
    let calendar = Fixture.dubai
    func kes(_ v: String) -> Money { Money(Decimal(string: v)!, currency: "KES") }

    @Test func theDateNeedNotComeFirst() throws {
        let csv = """
        Ref,Booked,Narrative,Amount,Running
        88120451,03/11/2026,Naivas Westlands,-1250.00,48750.00
        88120452,04/11/2026,Salary Ndovu Ltd,90000.00,138750.00
        88120453,06/11/2026,Kenya Power,-3400.00,135350.00
        """
        let layout = try #require(StatementImport.layout(in: csv, currency: "KES", calendar: calendar))
        #expect(layout.guess == StatementColumns(date: 1, description: 2, amount: 3, balance: 4))
        #expect(layout.check == BalanceCheck(rows: 2, addUp: 2))
        let rows = try StatementImport.read(csv, currency: "KES", calendar: calendar)
        #expect(rows.map(\.description) == ["Naivas Westlands", "Salary Ndovu Ltd", "Kenya Power"])
    }

    @Test func columnNamesInAnyLanguageWithMoneyOutAndInToldByTheBalance() throws {
        // Swahili names the app has no list for; which side is money out comes from the balance
        let csv = """
        Tarehe,Maelezo,Imetolewa,Imewekwa,Salio
        01/11/2026,Mshahara,,90000.00,100000.00
        02/11/2026,Duka la Mama Wanjiku,1250.50,,98749.50
        05/11/2026,Kodi ya nyumba,25000.00,,73749.50
        """
        let layout = try #require(StatementImport.layout(in: csv, currency: "KES", calendar: calendar))
        #expect(layout.guess == StatementColumns(date: 0, description: 1, debit: 2, credit: 3, balance: 4))
        #expect(layout.question == nil)
        let rows = try StatementImport.read(csv, currency: "KES", calendar: calendar)
        #expect(rows.map(\.amount) == [kes("90000"), kes("-1250.5"), kes("-25000")])
    }

    @Test func amountsWithoutASignTakeItFromTheBalance() throws {
        // Newest first, every amount positive: the balance says which went out
        let csv = """
        Date,Detail,Value,Bal
        07/11/2026,Matatu card top-up,500.00,9100.00
        05/11/2026,Refund Jumia,600.00,9600.00
        03/11/2026,Jumia order,1000.00,9000.00
        01/11/2026,Opening transfer,10000.00,10000.00
        """
        let rows = try StatementImport.read(csv, currency: "KES", calendar: calendar)
        #expect(rows.map(\.amount) == [kes("10000"), kes("-1000"), kes("600"), kes("-500")])
        let b = try #require(StatementImport.balances(in: csv, currency: "KES", calendar: calendar))
        #expect(b.opening == kes("0"))
        #expect(b.closing == kes("9100"))
        #expect(StatementImport.balanceCheck(csv, currency: "KES", calendar: calendar) == BalanceCheck(rows: 3, addUp: 3))
    }

    @Test func monthFirstDatesAreReadFromTheDatesThemselves() throws {
        // A day over 12 settles it
        let us = "Date,Description,Amount\n11/13/2026,Trader Joe's,-23.10\n11/02/2026,Payroll,2000.00"
        #expect(try StatementImport.read(us, currency: "USD", calendar: calendar).map(\.date)
            == [Fixture.date(2026, 11, 2), Fixture.date(2026, 11, 13)])
        // Every day 12 or under: the reading whose dates sit within days of each other, not months
        let close = "Date,Description,Amount\n10/03/2026,Shell,-40.00\n10/05/2026,Target,-12.00\n10/07/2026,Payroll,900.00"
        #expect(try StatementImport.read(close, currency: "USD", calendar: calendar).map(\.date)
            == [Fixture.date(2026, 10, 3), Fixture.date(2026, 10, 5), Fixture.date(2026, 10, 7)])
        let dayFirst = "Date,Description,Amount\n03/10/2026,Tesco,-40.00\n05/10/2026,Boots,-12.00\n07/10/2026,Salary,900.00"
        #expect(try StatementImport.read(dayFirst, currency: "GBP", calendar: calendar).map(\.date)
            == [Fixture.date(2026, 10, 3), Fixture.date(2026, 10, 5), Fixture.date(2026, 10, 7)])
    }

    @Test func twoMoneyColumnsWithNothingToTellThemApartAsk() throws {
        let csv = """
        Siku,Jina,A,B
        01/11/2026,Mshahara,,90000.00
        02/11/2026,Duka,1250.50,
        """
        let layout = try #require(StatementImport.layout(in: csv, currency: "KES", calendar: calendar))
        #expect(layout.question == .outOrIn(2, 3))
        #expect(layout.guess?.isComplete == false)
        #expect(throws: ImportError.unrecognisedColumns) { try StatementImport.read(csv, currency: "KES", calendar: calendar) }
        // Answered, it reads
        let rows = try StatementImport.read(csv, currency: "KES", columns: StatementColumns(date: 0, description: 1, debit: 2, credit: 3),
                                            calendar: calendar)
        #expect(rows.map(\.amount) == [kes("90000"), kes("-1250.5")])
    }

    @Test func arabicColumnNames() throws {
        let csv = """
        التاريخ,البيان,مدين,دائن,الرصيد
        01/11/2026,راتب,,9000.00,10000.00
        02/11/2026,كارفور,250.00,,9750.00
        """
        let rows = try StatementImport.read(csv, currency: "SAR", calendar: calendar)
        #expect(rows.map(\.amount) == [Money(9000, currency: "SAR"), Money(-250, currency: "SAR")])
        #expect(rows.map(\.description) == ["راتب", "كارفور"])
    }

    @Test func referencesAndCardDigitsAreNotTakenForMoney() throws {
        let csv = """
        Date,Card,Reference,Merchant,Amount
        01/11/2026,4417,427333201334,Java House,-450.00
        02/11/2026,4417,405252613207,Carrefour Junction,-3200.50
        """
        let layout = try #require(StatementImport.layout(in: csv, currency: "KES", calendar: calendar))
        #expect(layout.guess == StatementColumns(date: 0, description: 3, amount: 4))
    }
}
