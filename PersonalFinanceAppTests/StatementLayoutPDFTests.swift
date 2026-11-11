import Foundation
import Testing
import UIKit
import NokaelCore
@testable import PersonalFinanceApp

/// PDF statements laid out in other ways and languages, read without knowing their column names.
/// Made-up banks, names and numbers.
@MainActor
struct StatementLayoutPDFTests {
    struct Text { var text: String; var x: CGFloat; var y: CGFloat; var right = false }

    static func pdf(_ items: [Text]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 8)
            for item in items {
                let s = item.text as NSString
                let w = s.size(withAttributes: [.font: font]).width
                s.draw(at: CGPoint(x: item.right ? item.x - w : item.x, y: item.y), withAttributes: [.font: font])
            }
        }
    }

    static let calendar = Calendar(identifier: .gregorian)

    func read(_ data: Data, currency: String) async throws -> (grid: [[String]], rows: [StatementRow]) {
        let grid = try await StatementPDF.grid(from: data, password: nil)
        return (grid, try StatementImport.read(StatementImport.csvText(grid), currency: currency, calendar: Self.calendar))
    }

    func money(_ v: String, _ c: String) -> Money { Money(Decimal(string: v)!, currency: c) }

    /// Swahili column names, the reference before the date, the date's name on two lines,
    /// separate money out and money in, and a description wrapped onto a second line
    @Test func dateSecondNamesOnTwoLinesInAnotherLanguage() async throws {
        var items = [Text(text: "Benki ya Mfano", x: 40, y: 40), Text(text: "Taarifa ya akaunti", x: 40, y: 54),
                     Text(text: "Tarehe ya", x: 110, y: 90)]
        for (name, x) in [("Kumb.", 40.0), ("muamala", 110.0), ("Maelezo", 190.0), ("Imetolewa", 380.0), ("Imewekwa", 450.0),
                          ("Salio", 530.0)] {
            items.append(Text(text: name, x: x, y: 100))
        }
        let rows = [("RF-1001", "02/11/2026", "Duka la Mama Wanjiku", "1,250.50", "", "8,749.50"),
                    ("RF-1002", "03/11/2026", "Mshahara Novemba", "", "90,000.00", "98,749.50"),
                    ("RF-1003", "05/11/2026", "Kodi ya nyumba", "25,000.00", "", "73,749.50")]
        for (i, r) in rows.enumerated() {
            let y = 120 + CGFloat(i) * 24
            items += [Text(text: r.0, x: 40, y: y), Text(text: r.1, x: 110, y: y), Text(text: r.2, x: 190, y: y)]
            if !r.3.isEmpty { items.append(Text(text: r.3, x: 430, y: y, right: true)) }
            if !r.4.isEmpty { items.append(Text(text: r.4, x: 500, y: y, right: true)) }
            items.append(Text(text: r.5, x: 570, y: y, right: true))
        }
        items.append(Text(text: "Malipo ya kila mwezi", x: 190, y: 120 + 2 * 24 + 10))

        let (grid, read) = try await read(Self.pdf(items), currency: "KES")
        #expect(grid.first?.count == 6)
        #expect(grid.first?[1] == "Tarehe ya muamala")
        #expect(grid.count == 4)
        #expect(read.map(\.amount) == [money("-1250.5", "KES"), money("90000", "KES"), money("-25000", "KES")])
        #expect(read.last?.description == "Kodi ya nyumba Malipo ya kila mwezi")
    }

    /// No column names at all, month-first dates written out, newest first,
    /// every amount without a sign: the balance says which way each went
    @Test func noColumnNamesAndAmountsWithoutSigns() async throws {
        var items = [Text(text: "Example Credit Union", x: 40, y: 40), Text(text: "Checking 4471", x: 40, y: 54)]
        let rows = [("Nov 9, 2026", "Whole Foods Market", "54.20", "1,245.80"),
                    ("Nov 5, 2026", "Payroll Acme Corp", "1,200.00", "1,300.00"),
                    ("Nov 2, 2026", "Shell Station", "100.00", "100.00"),
                    ("Nov 1, 2026", "Transfer from savings", "200.00", "200.00")]
        for (i, r) in rows.enumerated() {
            let y = 100 + CGFloat(i) * 18
            items += [Text(text: r.0, x: 40, y: y), Text(text: r.1, x: 130, y: y),
                      Text(text: r.2, x: 470, y: y, right: true), Text(text: r.3, x: 560, y: y, right: true)]
        }
        let (grid, read) = try await read(Self.pdf(items), currency: "USD")
        #expect(grid.count == 5)
        #expect(read.map(\.date) == [Self.day(2026, 11, 1), Self.day(2026, 11, 2), Self.day(2026, 11, 5), Self.day(2026, 11, 9)])
        #expect(read.map(\.amount) == [money("200", "USD"), money("-100", "USD"), money("1200", "USD"), money("-54.2", "USD")])
        #expect(read.map(\.description).contains("Whole Foods Market"))
    }

    /// Arabic column names, laid out right to left: the date is the rightmost column
    @Test func arabicRightToLeft() async throws {
        var items: [Text] = []
        for (name, x) in [("الرصيد", 40.0), ("دائن", 130.0), ("مدين", 210.0), ("البيان", 330.0), ("التاريخ", 500.0)] {
            items.append(Text(text: name, x: x, y: 100))
        }
        let rows = [("01/11/2026", "Salary", "", "9,000.00", "10,000.00"),
                    ("02/11/2026", "Carrefour", "250.00", "", "9,750.00")]
        for (i, r) in rows.enumerated() {
            let y = 120 + CGFloat(i) * 18
            items += [Text(text: r.0, x: 500, y: y), Text(text: r.1, x: 330, y: y), Text(text: r.4, x: 100, y: y, right: true)]
            if !r.2.isEmpty { items.append(Text(text: r.2, x: 250, y: y, right: true)) }
            if !r.3.isEmpty { items.append(Text(text: r.3, x: 170, y: y, right: true)) }
        }
        let (_, read) = try await read(Self.pdf(items), currency: "SAR")
        #expect(read.map(\.amount) == [Money(9000, currency: "SAR"), Money(-250, currency: "SAR")])
        #expect(read.map(\.description) == ["Salary", "Carrefour"])
    }

    /// Two money columns with no balance and names that don't say which is which: the person is asked,
    /// with the reason, and the file reads once they choose
    @Test func moneyColumnsNothingCanTellApartAreAskedAbout() throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        review.load("Siku,Jina,A,B\n01/11/2026,Mshahara,,9000.00\n02/11/2026,Duka,250.00,\n", named: "s.csv")
        #expect(review.needsColumns && review.layout?.question == .outOrIn(2, 3))
        review.columns = StatementColumns(date: 0, description: 1, debit: 2, credit: 3)
        #expect(review.rows.map(\.amount) == [Baseline.aed(9000), Baseline.aed(-250)])
    }

    /// The balance check shown on the import screen
    @Test func theReviewSaysHowManyRowsMatchTheBalance() throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        // The last row's balance is off by 50: a row missing from the file
        review.load("""
            Siku,Jina,Kiasi,Salio
            01/11/2026,Mshahara,9000.00,10000.00
            02/11/2026,Duka,-250.00,9750.00
            03/11/2026,Teksi,-50.00,9700.00
            04/11/2026,Soko,-100.00,9600.00
            05/11/2026,Maji,-20.00,9580.00
            06/11/2026,Mkate,-30.00,9500.00
            """, named: "s.csv")
        #expect(review.balanceCheck == BalanceCheck(rows: 5, addUp: 4))
        #expect(review.rows.count == 6)
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
}
