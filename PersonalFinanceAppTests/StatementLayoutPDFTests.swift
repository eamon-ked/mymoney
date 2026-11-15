import Foundation
import Testing
import UIKit
import PDFKit
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

    /// Column names in two languages, each date halfway down its row's lines, a detail line with no money
    /// under a purchase, amounts to three places, a total carried forward, and a page number at the foot
    /// of a page that also holds right-to-left text set in a broken font
    @Test func datesHalfwayDownTheirRowsAndDetailLinesWithNoMoney() async throws {
        var items = [Text(text: "Account Statement TO±©¥ب اâZP¥ا vc¢", x: 40, y: 40)]
        func names(_ texts: [String], y: CGFloat) {
            for (name, x) in zip(texts, [40.0, 100.0, 280.0, 405.0, 472.0, 538.0]) { items.append(Text(text: name, x: x, y: y)) }
        }
        names(["Date", "Transaction", "Reference no", "Debit", "Credit", "Balance"], y: 100)
        names(["التاريخ", "المعاملة", "رقم المرجع", "مدين", "دائن", "الرصيد"], y: 112)
        func figures(_ debit: String, _ credit: String, _ balance: String, y: CGFloat) {
            for (figure, x) in zip([debit, credit, balance], [430.0, 500.0, 570.0]) where !figure.isEmpty {
                items.append(Text(text: figure, x: x, y: y, right: true))
            }
        }
        func lines(_ texts: [String], from y: CGFloat) {
            for (i, text) in texts.enumerated() { items.append(Text(text: text, x: 100, y: y + CGFloat(i) * 9)) }
        }
        lines(["OPENING BALANCE"], from: 128); figures("0.000", "0.000", "5,000.000", y: 128)
        // A purchase, and under it a line of its own about the card
        items += [Text(text: "01/10/2026", x: 40, y: 142), Text(text: "POSB0001aXq", x: 280, y: 142)]
        lines(["Card Purchase"], from: 142); figures("12.000", "0.000", "4,988.000", y: 142)
        lines(["Card ending 1234,"], from: 156); figures("0.000", "0.000", "0.000", y: 156)
        // Three lines, the date beside the middle one
        lines(["Transfer in", "Amina Njeri -", "Family support"], from: 170)
        items += [Text(text: "02/10/2026", x: 40, y: 179), Text(text: "IPPC0002bYr", x: 280, y: 179)]
        figures("0.000", "1,500.000", "6,488.000", y: 179)
        // Four lines, the date between the second and third
        lines(["Bill payment", "Maji Safi Water", "Account 5567", "October"], from: 202)
        items += [Text(text: "03/10/2026", x: 40, y: 215.5), Text(text: "BILL0003cZs", x: 280, y: 215.5)]
        figures("300.500", "0.000", "6,187.500", y: 215.5)
        lines(["Balance carried forward"], from: 243); figures("", "", "6,187.500", y: 243)
        items.append(Text(text: "Page 1 of 2", x: 280, y: 820))

        let (grid, read) = try await read(Self.pdf(items), currency: "AED")
        #expect(grid.first == ["Date", "Transaction", "Reference no", "Debit", "Credit", "Balance"])
        #expect(grid.count == 4)
        #expect(read.map(\.amount) == [money("-12", "AED"), money("1500", "AED"), money("-300.5", "AED")])
        #expect(read.map(\.description) == ["Card Purchase Card ending 1234,", "Transfer in Amina Njeri - Family support",
                                            "Bill payment Maji Safi Water Account 5567 October"])
        let layout = try #require(StatementImport.layout(in: StatementImport.csvText(grid), currency: "AED", calendar: Self.calendar))
        #expect(layout.check == BalanceCheck(rows: 2, addUp: 2))
    }

    /// A PDF written out by hand the way a report server writes one: each cell's text drawn inside
    /// the cell's own clipping box, in a standard font
    static func reportPDF(_ cells: [(text: String, x: Double, y: Double, box: (x: Double, width: Double))]) -> Data {
        var content = ""
        for cell in cells {
            let text = cell.text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
            content += "q \(cell.box.x) \(cell.y - 4) \(cell.box.width) 13 re W n\nBT /F1 8 Tf 0 0 0 rg 300 TL \(cell.x) \(cell.y) Td (\(text)) Tj T* ET\nQ\n"
        }
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 640 860] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
                       "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
                       "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(i + 1) 0 obj\n\(object)\nendobj\n"
        }
        let start = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    /// Amounts that reach the edge of their cells, which PDFKit's own reading mixes up:
    /// the page's drawing instructions give each cell as it was written, and the rows follow their balance
    @Test func amountsThatReachTheEdgeOfTheirCells() async throws {
        let boxes: [(x: Double, width: Double)] = [(15.6, 68), (159.6, 104), (267.6, 140), (411.6, 68), (483.6, 68), (555.6, 68)]
        let lefts = [15.6, 159.6, 267.6]
        func width(_ text: String) -> Double { Double(text.count) * 4.45 }   // digits and marks in 8-point Helvetica, near enough
        var cells: [(text: String, x: Double, y: Double, box: (x: Double, width: Double))] = []
        for (i, name) in ["DATE", "REF NO", "PARTICULARS", "DEBIT", "CREDIT", "BALANCE"].enumerated() {
            cells.append((name, boxes[i].x + (boxes[i].width - width(name) * 1.3) / 2, 620, boxes[i]))   // centred over its column
        }
        let rows = [("03-Apr-2026", "FT0001AAAA\\S01", "CARD PAYMENT - 5567", "1,099.62", "0.00", "8,079.83"),
                    ("04-Apr-2026", "FT0002BBBB", "CASH WITHDRAWAL", "1,100.00", "0.00", "6,979.83"),
                    ("04-Apr-2026", "FT0003CCCC", "SHOP PURCHASE - MAMA NJERI", "100.00", "0.00", "6,879.83"),
                    ("07-Apr-2026", "FT0004DDDD", "SALARY - KAZI LTD", "0.00", "12,500.00", "19,379.83"),
                    ("09-Apr-2026", "FT0005EEEE", "SHOP PURCHASE", "20.02", "0.00", "19,359.81")]
        for (r, row) in rows.enumerated() {
            let y = 581.0 - Double(r) * 22
            for (c, text) in [row.0, row.1, row.2].enumerated() { cells.append((text, lefts[c], y, boxes[c])) }
            // Right-aligned so the last figure touches the box's edge
            for (c, text) in [row.3, row.4, row.5].enumerated() {
                cells.append((text, boxes[c + 3].x + boxes[c + 3].width + 0.8 - width(text), y, boxes[c + 3]))
            }
        }
        cells.append(("SOKO LA JUMLA", 267.6, 581.0 - 2 * 22 - 9, boxes[2]))
        let data = Self.reportPDF(cells)

        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        let drawn = try #require(StatementPDFDrawn.textLines(on: page)).map(\.text)
        for row in rows { #expect(drawn.contains(row.3) && drawn.contains(row.5) && drawn.contains(row.1)) }

        let (grid, read) = try await read(data, currency: "AED")
        #expect(grid.count == 6)
        #expect(read.map(\.amount) == [money("-1099.62", "AED"), money("-1100", "AED"), money("-100", "AED"),
                                       money("12500", "AED"), money("-20.02", "AED")])
        #expect(read[2].description == "SHOP PURCHASE - MAMA NJERI SOKO LA JUMLA")
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
}
