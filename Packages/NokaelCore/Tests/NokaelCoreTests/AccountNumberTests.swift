import Foundation
import Testing
@testable import NokaelCore

/// Made-up numbers that share their last four digits, as one customer's accounts at a bank often do
struct AccountNumberTests {
    let numbers: [(id: String, number: String)] = [("current", "55501234640001"), ("savings", "55501234870001")]

    @Test func everyDigitBothSidesShowIsCompared() {
        #expect(AccountNumber.match("870001", in: numbers) == "savings")
        #expect(AccountNumber.match("XXX640001", in: numbers) == "current")
        #expect(AccountNumber.match("0001", in: numbers) == nil)
        #expect(AccountNumber.match("990001", in: numbers) == nil)
        // A short number typed for one account still fits a message showing more digits
        #expect(AccountNumber.match("55501234870001", in: [(id: "savings", number: "870001")]) == "savings")
    }

    @Test func clashesAreNumbersThatCantBeToldApart() {
        #expect(AccountNumber.clashes("0001", with: numbers).count == 2)
        #expect(AccountNumber.clashes("640001", with: numbers) == ["current"])
        #expect(AccountNumber.clashes("12", with: numbers).isEmpty)
    }

    @Test func aStatementNumberInTheNextCellIsFound() {
        let csv = "Account Statement\nAccount Number:,55501234870001 AED\nDate,Description,Amount\n01/11/2026,SALARY,10.00\n"
        #expect(StatementImport.accountNumber(in: csv) == "55501234870001")
        #expect(StatementImport.accountNumber(in: "Account Number: 55501234870001\nDate,Description,Amount\n") == "55501234870001")
    }

    @Test func gapsSplitWhatsNotPostedYetFromWhatsMissing() {
        let cal = Fixture.dubai
        func day(_ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }
        let ids = (0..<7).map { _ in UUID() }
        let aed = { (v: Decimal) in Money(v, currency: "AED") }
        let entries = [
            StatementGaps.Candidate(id: ids[0], date: day(5), size: aed(-100), automatic: false, cardPurchase: false), // on the statement
            StatementGaps.Candidate(id: ids[1], date: day(15), size: aed(20), automatic: true, cardPurchase: false),  // saved twice
            StatementGaps.Candidate(id: ids[2], date: day(15, 17), size: aed(-21.5), automatic: true, cardPurchase: true), // card, not posted yet
            StatementGaps.Candidate(id: ids[3], date: day(16, 13), size: aed(69), automatic: true, cardPurchase: false), // last day, after it
            StatementGaps.Candidate(id: ids[4], date: day(10), size: aed(-30), automatic: true, cardPurchase: true),  // old card payment
            // On the last day, but the same 20 that day is already on the statement: saved twice
            StatementGaps.Candidate(id: ids[5], date: day(16, 9), size: aed(-20), automatic: false, cardPurchase: false),
            StatementGaps.Candidate(id: ids[6], date: day(16, 10), size: aed(20), automatic: true, cardPurchase: false),
        ]
        let gaps = StatementGaps.find(entries, matched: [ids[0], ids[5]], firstDay: day(1), lastDay: day(16), calendar: cal)
        #expect(gaps.waiting == [ids[2], ids[3]])
        #expect(gaps.missing == [ids[4], ids[1], ids[6]])
    }
}
