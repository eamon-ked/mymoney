import Foundation
import Testing
@testable import NokaelCore

/// Alerts in ADCB's wording with made-up details, read without Apple Intelligence
struct BankAlertWordingTests {
    let cal = Fixture.dubai
    let arrived = Fixture.dubai.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 14, minute: 13))!

    func capture(_ text: String) throws -> Capture {
        try #require(AlertParser.examine(text, homeCurrency: "AED", date: arrived, calendar: cal).capture, "\(text)")
    }

    @Test func anOnlineBankingTransferIsMoneyOutWithItsTime() throws {
        let c = try capture("AED300.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  7 2026  2:12PM. Avl. bal. AED 34.02.")
        #expect(c.direction == .spent && c.isTransfer && c.amount == Money(300, currency: "AED"))
        #expect(c.accountHint == "560001" && c.otherAccountHint == nil && c.cardHint == nil)
        let p = cal.dateComponents([.day, .hour, .minute], from: c.date)
        #expect(c.dateFromMessage && p.day == 7 && p.hour == 14 && p.minute == 12)
        let morning = try capture("AED100.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  6 2026 10:38AM. Avl. bal. AED 7.01.")
        #expect(cal.dateComponents([.hour, .minute], from: morning.date) == DateComponents(hour: 10, minute: 38))
    }

    @Test func aCrTransactionIsMoneyIn() throws {
        let c = try capture("A Cr. transaction of AED 150.00 on your account no. XXX560001 was successful.Available balance is AED334.52.")
        #expect(c.direction == .received && c.amount == Money(150, currency: "AED") && !c.isTransfer)
        #expect(c.accountHint == "560001" && !c.dateFromMessage)
        let out = try capture("A Dr. transaction of AED 20.00 on your account no. XXX560001 was successful.")
        #expect(out.direction == .spent)
    }
}
