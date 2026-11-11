import Foundation
import Testing
import UIKit
import PDFKit
import NokaelCore
@testable import PersonalFinanceApp

/// PDF statements and choosing columns, through the same review a CSV uses
@MainActor
struct StatementPDFTests {
    /// A one-page statement drawn as a table: column names, then one line per row
    static func statementPDF(rows: [[String]], password: String? = nil) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        if let password {
            format.documentInfo = [kCGPDFContextUserPassword as String: password, kCGPDFContextOwnerPassword as String: password]
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format)
        return renderer.pdfData { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 11)
            ("Example Bank · Statement" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
            let xs: [CGFloat] = [40, 130, 400, 500]
            for (r, row) in rows.enumerated() {
                for (c, cell) in row.enumerated() {
                    (cell as NSString).draw(at: CGPoint(x: xs[c], y: 90 + CGFloat(r) * 20), withAttributes: [.font: font])
                }
            }
        }
    }

    static let table = [["Date", "Description", "Amount", "Balance"],
                        ["03/11/2026", "CARREFOUR CITY", "-45.00", "9955.00"],
                        ["05/11/2026", "SALARY NOVEMBER", "500.00", "10455.00"]]

    @Test func aPDFStatementReadsLikeTheSameCSV() async throws {
        let grid = try await StatementPDF.grid(from: Self.statementPDF(rows: Self.table), password: nil)
        let text = StatementImport.csvText(grid)
        let calendar = Calendar(identifier: .gregorian)
        let fromPDF = try StatementImport.read(text, currency: "AED", calendar: calendar)
        let fromCSV = try StatementImport.read(StatementImport.csvText(Self.table), currency: "AED", calendar: calendar)
        #expect(fromPDF.map(\.amount) == fromCSV.map(\.amount))
        #expect(fromPDF.map { $0.description.uppercased() } == ["CARREFOUR CITY", "SALARY NOVEMBER"])
    }

    @Test func aPasswordIsAskedForAndChecked() async throws {
        let data = Self.statementPDF(rows: Self.table, password: "0411")
        await #expect(throws: StatementPDF.Problem.locked) { try await StatementPDF.grid(from: data, password: nil) }
        await #expect(throws: StatementPDF.Problem.locked) { try await StatementPDF.grid(from: data, password: "wrong") }
        let grid = try await StatementPDF.grid(from: data, password: "0411")
        #expect(grid.count >= 3)
    }

    @Test func theReviewAsksForThePasswordThenReads() async throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        let data = Self.statementPDF(rows: Self.table, password: "0411")
        await review.loadPDF(data, named: "statement.pdf", password: nil)
        #expect(review.needsPassword && review.error == nil && review.fileText == nil)
        await review.unlock("nope")
        #expect(review.needsPassword && review.error != nil)
        await review.unlock("0411")
        #expect(!review.needsPassword)
        #expect(review.rows.map(\.amount) == [Baseline.aed(-45), Baseline.aed(500)])
    }

    @Test func notAStatementSaysSo() async throws {
        let empty = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage()
            ("Thank you for banking with us." as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
        await #expect(throws: StatementPDF.Problem.nothingFound) { try await StatementPDF.grid(from: empty, password: nil) }
        #expect(StatementPDF.isPDF(empty) && !StatementPDF.isPDF(Data("Date,Amount".utf8)))
    }

    @Test func textLinesSplitIntoCellsAndBalanceGivesTheSign() {
        let text = """
        Statement of account
        01/11/2026 Opening balance 1,000.00
        03/11/2026 03/11/2026 CARD PURCHASE LULU 45.00 955.00
        05/11/2026 SALARY 2,500.00 3,455.00
        Page 1 of 1
        """
        let rows = StatementPDF.textRows(text)
        #expect(rows.count == 3)
        #expect(rows[1] == ["03/11/2026", "CARD PURCHASE LULU", "45.00", "955.00"])
        let signed = StatementPDF.signedByBalance(Array(rows.dropFirst()))
        // The first row of a file can't be checked against an earlier balance
        #expect(signed[1][2] == "2,500.00")
        let three = StatementPDF.signedByBalance([["01/11/2026", "A", "100.00", "1,000.00"],
                                                  ["03/11/2026", "B", "45.00", "955.00"],
                                                  ["05/11/2026", "C", "5.00", "960.00"]])
        #expect(three.map { $0[2] } == ["100.00", "-45.00", "5.00"])
        // Newest first
        let newest = StatementPDF.signedByBalance([["05/11/2026", "C", "5.00", "960.00"],
                                                   ["03/11/2026", "B", "45.00", "955.00"],
                                                   ["01/11/2026", "A", "100.00", "1,000.00"]])
        #expect(newest.map { $0[2] } == ["5.00", "-45.00", "100.00"])
    }

    /// A statement laid out the way some banks print one: the time under the date, the description
    /// left-aligned well before its centred column name and wrapped onto a second line, amounts without decimals,
    /// newest first. Made-up names and numbers.
    static func bankLayoutPDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 7)
            func put(_ text: String, _ x: CGFloat, _ y: CGFloat, right: Bool = false) {
                let s = text as NSString
                let w = s.size(withAttributes: [.font: font]).width
                s.draw(at: CGPoint(x: right ? x - w : x, y: y), withAttributes: [.font: font])
            }
            put("Account Statement", 36, 40)
            put("Opening Balance: 130.97 AED", 38, 60)
            for (name, x) in [("Posting Date", 42.0), ("Value Date", 108.0), ("Description", 214.0), ("Ref/Cheque No", 315.0),
                              ("Debit Amount", 379.0), ("Credit Amount", 439.0), ("Balance", 513.0)] { put(name, x, 100) }
            let rows: [(String, String, String, String?, String, String, String, String)] = [
                ("11/11/2026", "00:57:13", "10/11/2026", "45279137425 MBTRF AED150 TRF OUT", "67600815878", "150", "0.00", "1728.8"),
                ("10/11/2026", "23:00:38", "10/11/2026", "701154716 B/O EXAMPLE PAYMENTS LLC", "PHUB7490313", "0.00", "339.39", "1878.8"),
                ("09/11/2026", "15:44:12", "06/11/2026", "PUR 06/11 CORNER SHOP ABU DHABI", "367786", "50", "0.00", "1539.41"),
            ].map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7) }
            for (i, r) in rows.enumerated() {
                let y = 120 + CGFloat(i) * 20
                put(r.0, 47, y); put(r.1, 51, y + 8); put(r.2, 108, y)
                put(r.3!, 161, y); put(i == 0 ? "TO Samira Okello" : "4417", 161, y + 8)
                put(r.4, 315, y)
                put(r.5, 434, y, right: true); put(r.6, 495, y, right: true); put(r.7, 557, y, right: true)
            }
            put("Page 1 of 1", 270, 800)
        }
    }

    @Test func aPrintedStatementIsReadFromItsOwnText() async throws {
        let grid = try await StatementPDF.grid(from: Self.bankLayoutPDF(), password: nil)
        #expect(grid.first == ["Posting Date", "Value Date", "Description", "Ref/Cheque No", "Debit Amount", "Credit Amount", "Balance"])
        #expect(grid.count == 4)
        #expect(grid[1][0] == "11/11/2026 00:57:13")
        #expect(grid[1][2] == "45279137425 MBTRF AED150 TRF OUT TO Samira Okello")
        // The card digits wrapped under the description stay in it, not in the value date
        #expect(grid[3][1] == "06/11/2026" && grid[3][2].hasSuffix("4417"))
        let rows = try StatementImport.read(StatementImport.csvText(grid), currency: "AED", calendar: Calendar(identifier: .gregorian))
        #expect(Set(rows.map(\.amount)) == [Baseline.aed(-150), Baseline.aed(Decimal(string: "339.39")!), Baseline.aed(-50)])
    }

    @Test func amountsKeptAsOnePieceAreSplitIntoTheirColumns() {
        typealias L = StatementPDF.TextLine
        func line(_ t: String, _ x: CGFloat, _ maxX: CGFloat, _ y: CGFloat) -> L { L(text: t, rect: CGRect(x: x, y: y, width: maxX - x, height: 8)) }
        let header = [line("Date", 42, 60, 700), line("Description", 214, 258, 700), line("Debit Amount", 379, 431, 700),
                      line("Credit Amount", 439, 494, 700), line("Balance", 513, 544, 700)]
        let body = [line("16/10/2026", 47, 87, 680), line("PUR SHOP", 161, 200, 680), line("4", 429, 434, 680),
                    line("0.00", 480, 495, 680), line("1.27", 541, 557, 680),
                    line("15/10/2026", 47, 87, 660), line("PUR SHOP", 161, 200, 660), line("5 0.00", 429.5, 495.5, 660),
                    line("5.27", 541, 557, 660)]
        let (rows, _) = StatementPDF.textTable(header + body, columns: nil)
        #expect(rows.count == 2)
        #expect(rows[1] == ["15/10/2026", "PUR SHOP", "5", "0.00", "5.27"])
    }

    // MARK: - Choosing columns

    /// Two money columns with names the app doesn't know and no balance: nothing tells which is money out
    static let odd = "Booked,Ref,Shop,A,B\n2026-11-08,X1,CARREFOUR,45.00,\n2026-11-08,X2,Salary,,500.00\n"

    @Test func unknownColumnsAskInsteadOfFailing() throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        review.load(Self.odd, named: "odd.csv")
        #expect(review.needsColumns && review.error == nil && review.fileText != nil && review.rows.isEmpty)
        #expect(review.layout?.names == ["Booked", "Ref", "Shop", "A", "B"])
        #expect(review.layout?.question == .outOrIn(3, 4))
        review.columns = StatementColumns(date: 0, description: 2, debit: 3, credit: 4)
        #expect(!review.needsColumns && review.rows.map(\.description) == ["CARREFOUR", "Salary"])
        #expect(review.rows.map(\.amount) == [Baseline.aed(-45), Baseline.aed(500)])

        // The next file with the same columns, for the same account, opens with the choice
        let next = StatementReview(accountId: b.main.id, store: b.store)
        next.load(Self.odd, named: "odd-2.csv")
        #expect(!next.needsColumns && next.rows.count == 2)
        // Another account doesn't share it
        let other = StatementReview(accountId: b.savings.id, store: b.store)
        other.load(Self.odd, named: "odd.csv")
        #expect(other.needsColumns)
    }

    @Test func aChoiceThatDoesntReadSaysWhyAndCanBeChanged() throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        review.load(Self.odd, named: "odd.csv")
        review.columns = StatementColumns(date: 1, description: 2, debit: 3, credit: 4)
        #expect(review.needsColumns && review.error != nil && review.fileText != nil)
        review.columns = StatementColumns(date: 0, description: 2, debit: 3, credit: 4)
        #expect(review.error == nil && !review.needsColumns && review.rows.count == 2)
    }

    @Test func choosingAnotherDescriptionColumn() throws {
        let b = try Baseline()
        let review = StatementReview(accountId: b.main.id, store: b.store)
        let csv = "Date,Details,Merchant,Amount\n2026-11-08,POS 4417 2911,CARREFOUR,-45.00\n"
        review.load(csv, named: "s.csv")
        #expect(review.rows.first?.description == "POS 4417 2911")
        var cols = try #require(review.columnsInUse)
        cols.description = 2
        review.columns = cols
        #expect(review.rows.first?.description == "CARREFOUR")
        // Going back to the app's choice forgets it
        review.columns = nil
        #expect(review.rows.first?.description == "POS 4417 2911")
        let again = StatementReview(accountId: b.main.id, store: b.store)
        again.load(csv, named: "s.csv")
        #expect(again.rows.first?.description == "POS 4417 2911")
    }
}
