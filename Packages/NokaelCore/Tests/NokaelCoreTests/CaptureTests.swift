import Foundation
import Testing
@testable import NokaelCore

struct CaptureTests {
    let aed = Fixture.aed
    let now = Fixture.date(2026, 10, 26, 14)

    func read(_ text: String) -> Capture? { AlertParser.read(text, homeCurrency: "AED", date: now) }

    // MARK: - Reading alerts

    @Test func readsUAEPurchaseAlerts() throws {
        let cases: [(String, Decimal, String, String?)] = [
            ("Purchase of AED 45.00 at CARREFOUR CITY with your Credit Card ending 1234 on 26/10/2026. Avl Cr. Limit is AED 12,000.00",
             45, "Carrefour City", "1234"),
            ("Your ADCB Debit Card XXX5678 was used for AED1,250.50 at NOON.COM on 26-Oct-2026. Avl bal AED 8,431.20",
             1250.5, "Noon.Com", "5678"),
            ("AED 32.75 spent on Card **9012 at Talabat. Available balance AED 2,100.00.", 32.75, "Talabat", "9012"),
            ("Dear Customer, AED 120.00 has been debited from your account ending with 4321 at DEWA SMART PAYMENT.",
             120, "Dewa Smart Payment", "4321"),
            ("Transaction of 89.00 AED at Starbucks Mall of the Emirates using card ending in 7788", 89, "Starbucks Mall", "7788"),
            ("Payment of AED 500.00 to Etisalat was successful from a/c ...3344", 500, "Etisalat", "3344"),
        ]
        for (text, amount, merchant, card) in cases {
            let c = try #require(read(text), "\(text)")
            #expect(c.amount == aed(amount), "\(text)")
            #expect(c.direction == .spent, "\(text)")
            #expect(c.merchant.hasPrefix(merchant), "\(c.merchant) for \(text)")
            #expect(c.cardHint == card, "\(text)")
            #expect(c.source == .sms)
        }
    }

    @Test func readsMoneyComingIn() throws {
        let salary = try #require(read("Your a/c XXXX1122 has been credited with AED 20,000.00 from ACME LLC SALARY on 25/10. Avl bal AED 21,500.00"))
        #expect(salary.direction == .received)
        #expect(salary.amount == aed(20000))
        #expect(salary.merchant.hasPrefix("Acme"))

        let refund = try #require(read("Refund of AED 99.50 from Amazon.ae has been credited to your card ending 1234"))
        #expect(refund.direction == .received)
        #expect(refund.amount == aed(99.5))
    }

    @Test func prefersTheHomeCurrencyWhenAbroad() throws {
        let c = try #require(read("Purchase of USD 20.00 (AED 73.46) at APPLE.COM/BILL with card ending 1234"))
        #expect(c.amount == aed(73.46))
        let foreign = try #require(read("Purchase of USD 20.00 at Uber with card ending 1234"))
        #expect(foreign.amount == Money(20, currency: "USD"))
    }

    @Test func ignoresCodesDeclinesBalancesAndOffers() {
        #expect(read("Your OTP for purchase of AED 45.00 at Noon is 482913. Do not share it with anyone.") == nil)
        #expect(read("Transaction of AED 300.00 at Sharaf DG was declined due to insufficient balance.") == nil)
        #expect(read("Your available balance is AED 4,500.00 as of 26/10/2026.") == nil)
        #expect(read("Get 10% cashback! Apply now for our Platinum card.") == nil)
        #expect(read("Your credit card payment of AED 1,200.00 is due on 05/11/2026.") == nil)
    }

    @Test func readsLocalCurrencyNames() throws {
        let c = try #require(read("Dhs 15.50 spent at ENOC with card ending 4455"))
        #expect(c.amount == aed(15.5))
        let inr = try #require(AlertParser.read("Rs.450.00 debited from a/c XX1234 at SWIGGY", homeCurrency: "INR", date: now))
        #expect(inr.amount == Money(450, currency: "INR"))
    }

    @Test func readsWhatWasSaidToSiri() throws {
        let a = try #require(AlertParser.spoken("45 at Carrefour", homeCurrency: "AED", date: now))
        #expect(a.amount == aed(45) && a.merchant == "Carrefour" && a.direction == .spent && a.source == .siri)
        let b = try #require(AlertParser.spoken("spent 120.50 dirhams on electricity", homeCurrency: "AED", date: now))
        #expect(b.amount == aed(120.5) && b.merchant == "Electricity")
        let c = try #require(AlertParser.spoken("got 500 from Sam", homeCurrency: "AED", date: now))
        #expect(c.direction == .received && c.merchant == "Sam")
        #expect(AlertParser.spoken("lunch at the mall", homeCurrency: "AED", date: now) == nil)
    }

    // MARK: - Senders

    @Test func matchesBankSenders() {
        #expect(BankSenders.matches("ADCBAlert", any: ["ADCBAlert"]))
        #expect(BankSenders.matches("adcb-alert", any: ["ADCBAlert"]))
        #expect(BankSenders.matches("AD-HDFCBK", any: ["HDFCBK"]))
        #expect(!BankSenders.matches("Careem", any: ["ADCBAlert", "FAB"]))
        #expect(!BankSenders.matches("", any: ["FAB"]))
        #expect(BankSenders.banks(region: "AE").contains { $0.name == "Emirates NBD" })
        #expect(BankSenders.keyword(region: "AE") == "AED")
    }

    // MARK: - Duplicates

    func capture(_ source: Capture.Source, _ amount: Decimal, _ merchant: String, minutes: Double = 0) -> Capture {
        Capture(source: source, direction: .spent, amount: aed(amount), merchant: merchant, date: now.addingTimeInterval(minutes * 60))
    }

    func entry(_ source: Capture.Source?, _ amount: Decimal, _ memo: String, minutes: Double = 0) -> CapturedEntry {
        CapturedEntry(id: UUID(), date: now.addingTimeInterval(minutes * 60), amount: aed(amount), direction: .spent,
                      memo: memo, source: source)
    }

    @Test func applePayAndTheBankSMSAreOnePurchase() {
        let tap = entry(.applePay, 45, "Carrefour", minutes: -3)
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 45, "MAF CARREFOUR CITY"), in: [tap]) == tap.id)
        // Same amount an hour later is another purchase
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 45, "Carrefour", minutes: 60), in: [tap]) == nil)
        // A different amount is never the same purchase
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 46, "Carrefour"), in: [tap]) == nil)
    }

    @Test func sameSourceNeedsTheSameShop() {
        let coffee = entry(.applePay, 18, "Starbucks", minutes: -2)
        #expect(CaptureMatcher.duplicate(of: capture(.applePay, 18, "Starbucks"), in: [coffee]) == coffee.id)
        #expect(CaptureMatcher.duplicate(of: capture(.applePay, 18, "Tim Hortons"), in: [coffee]) == nil)
    }

    @Test func aTypedEntryMatchesOnTheSameDayAndShop() {
        let typed = entry(nil, 120, "Dewa", minutes: -240)
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 120, "DEWA SMART PAYMENT"), in: [typed]) == typed.id)
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 120, "Etisalat"), in: [typed]) == nil)
    }
}
