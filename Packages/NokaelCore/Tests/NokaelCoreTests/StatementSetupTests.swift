import Foundation
import Testing
@testable import NokaelCore

/// Statements as a starting point: their balances, what they show about pay and bills,
/// and money with people. Names are made up; the shape follows a real UAE bank export.
struct StatementSetupTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return c
    }()

    let uae = """
    "Account Number: 11392149920001 AED",
    "Statement Period: From 20/10/2026 to 01/11/2026",
    "Opening Balance: 2.23 AED",
    "Closing Balance: 176.19 AED",
    Posting Date,Value Date,Reference No,Description,Debit Amount,Credit Amount,Balance
    "20/10/2026 16:07:19","20/10/2026","P1","736668522 B/O ACMEDELIVERYLOGISTICSLLC","0.00","5","7.23",
    "26/10/2026 09:00:00","26/10/2026","S1","SALARY","0.00","12000","12007.23",
    "26/10/2026 09:05:00","26/10/2026","L1","LOANRECOVERY-EMI:11392149P022001","5781","0.00","6226.23",
    "29/10/2026 10:00:00","29/10/2026","T1","41421369215MBTRFAED1000.00@11392149810001","1000","0.00","5226.23",
    "31/10/2026 23:48:34","31/10/2026","P2","743378734 B/O Jane Doe","0.00","30","5256.23",
    "01/11/2026 12:54:34","01/11/2026","T2","41587896180 MBTRF AED5080.04 TRF OUT TO john smith","5080.04","0.00","176.19",
    """

    @Test func readsOpeningAndClosingLines() throws {
        let b = try #require(StatementImport.balances(in: uae, currency: "AED", calendar: calendar))
        #expect(b.opening == Money(Decimal(string: "2.23")!, currency: "AED"))
        #expect(b.closing == Money(Decimal(string: "176.19")!, currency: "AED"))
        #expect(calendar.component(.day, from: b.firstDay) == 20)
        #expect(calendar.component(.day, from: b.lastDay) == 1)
        #expect(StatementImport.currency(in: uae) == "AED")
    }

    @Test func worksOutBalancesFromTheBalanceColumn() throws {
        // A UK-style export: newest first, one signed amount, a running balance, nothing above the header
        let uk = """
        Date,Description,Amount,Balance
        03/11/2026,TESCO STORES 2231,-23.40,976.60
        02/11/2026,STANDING ORDER LOAN REPAYMENT,-250.00,1000.00
        01/11/2026,SALARY ACME LTD,1250.00,1250.00
        """
        let b = try #require(StatementImport.balances(in: uk, currency: "GBP", calendar: calendar))
        #expect(b.opening == .zero("GBP"))
        #expect(b.closing == Money(Decimal(string: "976.60")!, currency: "GBP"))
        #expect(StatementImport.currency(in: uk) == nil)
    }

    @Test func namesTheOtherOwnAccountNotTheReference() {
        let row = "41421369215MBTRFAED1000.00@11392149810001"
        #expect(StatementImport.otherOwnAccount(in: row, ownNumber: "11392149920001") == "11392149810001")
        #expect(StatementImport.isOwnAccountTransfer(row, ownNumber: "11392149920001"))
        #expect(StatementImport.otherOwnAccount(in: "41031133397 MBTRF AED350 TRF OUT TO john smith", ownNumber: "11392149920001") == nil)
    }

    @Test func noBalancesWhenTheFileHasNone() {
        let plain = "Date,Description,Amount\n2026-10-01,Coffee,-5\n2026-10-02,Lunch,-12"
        #expect(StatementImport.balances(in: plain, currency: "USD", calendar: calendar) == nil)
    }

    @Test func findsPayAndTheLoan() throws {
        let rows = try StatementImport.read(uae, currency: "AED", calendar: calendar)
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let found = StatementInsights.findings(rows, today: today, calendar: calendar)
        let pay = try #require(found.first { $0.kind == .pay })
        #expect(pay.amount == Money(12000, currency: "AED"))
        #expect(calendar.component(.day, from: pay.nextDate) == 26)
        #expect(calendar.component(.month, from: pay.nextDate) == 11)
        let loan = try #require(found.first { $0.kind == .loan })
        #expect(loan.amount == Money(5781, currency: "AED"))
        // One month of a statement shows no repeating bills, and money to people is never one
        #expect(!found.contains { $0.kind == .bill })
    }

    @Test func billsRepeatAcrossMonths() {
        let day = { (m: Int, d: Int) in self.calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }
        let rows = [
            StatementRow(id: 1, date: day(9, 3), description: "DU MOBILE POSTPAID", amount: Money(-150, currency: "AED")),
            StatementRow(id: 2, date: day(10, 3), description: "DU MOBILE POSTPAID", amount: Money(-150, currency: "AED")),
            StatementRow(id: 3, date: day(10, 5), description: "CARREFOUR CITY", amount: Money(-80, currency: "AED"))
        ]
        let found = StatementInsights.findings(rows, today: day(10, 20), calendar: calendar)
        #expect(found.count == 1)
        #expect(found.first?.kind == .bill)
        #expect(found.first?.amount == Money(150, currency: "AED"))
        #expect(found.first.map { calendar.component(.month, from: $0.nextDate) } == 11)
    }

    @Test func moneyFromPeopleIsNotPay() {
        #expect(CategoryRules.isFromPeople("743378734 B/O Jane Doe"))
        #expect(CategoryRules.isFromPeople("737073125 B/O ZIINA PAYMENT LLC - CLIENT MONEY"))
        #expect(CategoryRules.isFromPeople("FASTER PAYMENT FROM J SMITH"))
        // Businesses and pay aren't
        #expect(!CategoryRules.isFromPeople("736668522 B/O ACMEDELIVERYLOGISTICSLLC"))
        #expect(!CategoryRules.isFromPeople("736668522 B/O NOKAELDASHLOGISTICSFORDELIVER"))
        #expect(!CategoryRules.isFromPeople("INWARD REMITTANCE FROM ACME TRADING LLC"))
        #expect(!CategoryRules.isFromPeople("SALARY"))
        // A person filed as Salary once doesn't stay there; an employer the person chose does
        #expect(!CategoryRules.historyFits(categoryName: "Salary", description: "743378734 B/O Jane Doe", income: true))
        #expect(CategoryRules.historyFits(categoryName: "Salary", description: "B/O ACME TRADING LLC", income: true))
        #expect(CategoryRules.historyFits(categoryName: "Groceries", description: "B/O Jane Doe", income: false))
    }
}
