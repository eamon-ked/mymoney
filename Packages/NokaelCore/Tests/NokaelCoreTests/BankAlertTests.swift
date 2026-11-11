import Foundation
import Testing
@testable import NokaelCore

/// Alerts in the wording UAE banks such as ADCB use, read without Apple Intelligence: what moved, which way,
/// on which card or account, with which reference and on which day.
struct BankAlertTests {
    let aed = Fixture.aed
    let cal = Fixture.dubai
    /// When the messages arrive: 3 November 2026, 12:30
    let arrived = Fixture.dubai.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12, minute: 30))!

    func read(_ text: String, home: String = "AED", monthFirst: Bool = false) -> AlertReading {
        AlertParser.examine(text, homeCurrency: home, date: arrived, calendar: cal, monthFirst: monthFirst)
    }

    func capture(_ text: String) throws -> Capture { try #require(read(text).capture, "\(text)") }

    func parts(_ date: Date) -> DateComponents { cal.dateComponents([.year, .month, .day, .hour, .minute], from: date) }

    @Test func aDebitCardPurchaseNamesTheCardTheAccountAndTheTime() throws {
        let c = try capture("Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 on 03/11/2026 12:22:05 at CARREFOUR,ABU DHABI-AE. Avl.Bal.AED525.19. Never share your OTP.")
        #expect(c.amount == aed(45) && c.direction == .spent && !c.isTransfer)
        #expect(c.merchant == "Carrefour")
        #expect(c.cardHint == "4417" && c.accountHint == "730001")
        #expect(parts(c.date).hour == 12 && parts(c.date).minute == 22 && c.dateFromMessage)
    }

    @Test func aCreditCardPurchaseWithTheMonthWritten() throws {
        let c = try capture("Your Cr.Card XXX1234 was used for AED1,250.50 on Nov  2 2026 09:15PM at NOON.COM. Avl Cr.limit is AED 9,000.00")
        #expect(c.amount == aed(1250.5) && c.cardHint == "1234" && c.accountHint == nil)
        let p = parts(c.date)
        #expect(p.month == 11 && p.day == 2 && p.hour == 21 && p.minute == 15)
    }

    @Test func moneyInFromSomeoneIsIncomeIntoThatAccount() throws {
        let c = try capture("AED300.00 has been credited to your account XXX730001 on 03/11/2026 from SAMUEL OTIENO BARASA. Ref No. 43361448434. Avl.Bal AED825.19")
        #expect(c.direction == .received && c.amount == aed(300))
        #expect(c.accountHint == "730001" && c.cardHint == nil)
        #expect(c.reference == "43361448434")
        #expect(c.merchant.hasPrefix("Samuel Otieno Barasa"))
    }

    @Test func moneyOutByTransferIsATransferWithItsReference() throws {
        let c = try capture("AED150.00 has been transferred from your account XXX240001 to SAMUEL OTIENO BARASA on 02/11/2026. Ref 41235832494")
        #expect(c.direction == .spent && c.isTransfer && c.amount == aed(150))
        #expect(c.accountHint == "240001" && c.reference == "41235832494")
        #expect(parts(c.date).day == 2 && parts(c.date).hour == 12)
    }

    @Test func aTransferToAnotherOfYourAccountsNamesBoth() throws {
        let c = try capture("AED1,000.00 has been transferred from your account XXX730001 to account XXX240001 on 03/11/2026. Ref 49051225550")
        #expect(c.isTransfer && c.direction == .spent)
        #expect(c.accountHint == "730001" && c.otherAccountHint == "240001")
        let into = try capture("AED500.00 has been transferred to your account XXX491234 from account XXX812222")
        #expect(into.direction == .received && into.accountHint == "491234" && into.otherAccountHint == "812222")
    }

    @Test func statementStyleWordingReadsToo() throws {
        let out = try capture("43361448434 MBTRF AED300.00 TRF OUT TO SAMUEL OTIENO BARASA")
        #expect(out.direction == .spent && out.isTransfer && out.reference == "43361448434")
        let into = try capture("43361448434 MBTRF B/O SAMUEL OTIENO BARASA AED300.00")
        #expect(into.direction == .received && into.reference == "43361448434")
    }

    @Test func offersAreTurnedAwayButRealCashbackIsKept() throws {
        #expect(read("Get up to 10% cashback on AED 500 spends with your ADCB card. T&C apply. Visit www.adcb.com") == .ignored(.promotion))
        #expect(read("Win AED 1,000,000! Apply now for a personal loan at 5.99%") == .ignored(.promotion))
        #expect(read("Enjoy an exclusive offer: AED 100 off at NOON with ADCB cards") == .ignored(.promotion))
        let back = try capture("Cashback of AED 25.00 has been credited to your card XXX1234")
        #expect(back.direction == .received && back.amount == aed(25))
    }

    @Test func noticesCodesAndDeclinesSayWhy() {
        #expect(read("Your OTP for the transaction of AED 45.00 at NOON is 482913") == .ignored(.oneTimeCode))
        #expect(read("Your purchase of AED 45.00 at NOON was declined due to insufficient balance") == .ignored(.declined))
        #expect(read("Your credit card payment of AED 2,000.00 is due on 15/11/2026") == .ignored(.notice))
        #expect(read("Hello, your card is ready to collect") == .ignored(.noAmount))
    }

    @Test func aReversalIsMoneyBack() throws {
        let c = try capture("Reversal of AED45.00 for CARREFOUR has been credited to your card XXX4417")
        #expect(c.isReversal && c.direction == .received && c.amount == aed(45) && c.cardHint == "4417")
        let refund = try capture("Refund of AED 120.00 from NOON.COM credited to your Cr.Card XXX1234 on 01/11/2026")
        #expect(refund.isReversal && refund.direction == .received)
    }

    @Test func datesAreOnlyBelievedWhenTheyCouldBeThePurchase() {
        // Day first unless the phone writes the month first
        let dayFirst = AlertParser.transactionDate(in: "on 02/11/2026", arrived: arrived, calendar: cal)
        #expect(dayFirst.map(parts)?.day == 2)
        let monthFirst = AlertParser.transactionDate(in: "on 11/02/2026", arrived: arrived, calendar: cal, monthFirst: true)
        #expect(monthFirst.map(parts)?.day == 2 && monthFirst.map(parts)?.month == 11)
        // A due date in the future, or something from months ago, isn't the purchase date
        #expect(AlertParser.transactionDate(in: "due on 25/11/2026", arrived: arrived, calendar: cal) == nil)
        #expect(AlertParser.transactionDate(in: "since 01/06/2026", arrived: arrived, calendar: cal) == nil)
        // Today without a time keeps the time it arrived
        #expect(AlertParser.transactionDate(in: "on 03/11/2026", arrived: arrived, calendar: cal) == arrived)
        // An amount is not a date
        #expect(AlertParser.transactionDate(in: "AED 12.10 at CAFE", arrived: arrived, calendar: cal) == nil)
        // "30/12" arriving on 2 January is last December
        let january = cal.date(from: DateComponents(year: 2027, month: 1, day: 2, hour: 9))!
        let december = AlertParser.transactionDate(in: "PUR 30/12 CAFE", arrived: january, calendar: cal)
        #expect(december.map(parts)?.year == 2026)
    }

    @Test func alertsInOtherCountriesStillRead() throws {
        let euro = try #require(AlertParser.examine("Kartenzahlung 12,50 EUR bei REWE am 02.11.2026 mit Karte ****4455", homeCurrency: "EUR",
                                                    date: arrived, calendar: cal).capture)
        #expect(euro.amount == Money(12.5, currency: "EUR") && euro.cardHint == "4455" && parts(euro.date).day == 2)
        let rupees = try #require(AlertParser.examine("INR 2,500.00 debited from A/c XX1234 on 02-Nov-26 to VPA shop@upi Ref 431212345678",
                                                      homeCurrency: "INR", date: arrived, calendar: cal).capture)
        #expect(rupees.accountHint == "1234" && rupees.reference == "431212345678" && parts(rupees.date).day == 2)
    }
}

struct AmountCheckTests {
    let en = Locale(identifier: "en_AE")
    let de = Locale(identifier: "de_DE")

    @Test func typedAmountsFollowThePhonesDecimalMark() {
        #expect(MoneyFormat.parse("12,50", currency: "EUR", locale: de)?.minorUnits == 1250)
        #expect(MoneyFormat.parse("1.250,50", currency: "EUR", locale: de)?.minorUnits == 125050)
        #expect(MoneyFormat.parse("1.500", currency: "EUR", locale: de)?.minorUnits == 150000)
        #expect(MoneyFormat.parse("1,500", currency: "AED", locale: en)?.minorUnits == 150000)
        #expect(MoneyFormat.parse("12,50", currency: "AED", locale: en)?.minorUnits == 1250)
        #expect(MoneyFormat.parse("1 250,5", currency: "EUR", locale: de)?.minorUnits == 125050)
        #expect(MoneyFormat.parse("1'250.50", currency: "CHF", locale: en)?.minorUnits == 125050)
        #expect(MoneyFormat.parse("AED 45", currency: "AED", locale: en)?.minorUnits == 4500)
        #expect(MoneyFormat.parse("٤٥٫٥٠", currency: "AED", locale: en)?.minorUnits == 4550)
    }

    @Test func amountsAreNeverRoundedOrAbsurd() {
        // Too many decimals for the currency is a mistake to fix, not something to round away
        #expect(MoneyFormat.parse("12.345", currency: "AED", locale: en) == nil)
        #expect(MoneyFormat.parse("12.345", currency: "KWD", locale: en)?.minorUnits == 12345)
        #expect(MoneyFormat.parse("1500.5", currency: "JPY", locale: en) == nil)
        #expect(MoneyFormat.parse("1500", currency: "JPY", locale: en)?.minorUnits == 1500)
        #expect(MoneyFormat.parse("12.50.3", currency: "AED", locale: en) == nil)
        #expect(MoneyFormat.parse("99999999999999", currency: "AED", locale: en) == nil)
        #expect(Money.exact(Decimal(string: "45.10")!, currency: "AED")?.minorUnits == 4510)
        #expect(Money.exact(Decimal(string: "45.105")!, currency: "AED") == nil)
        #expect(Money.spoken(12.3, currency: "AED")?.minorUnits == 1230)
        #expect(Money.spoken(1500, currency: "JPY")?.minorUnits == 1500)
        #expect(Money.spoken(.infinity, currency: "AED") == nil)
    }
}
