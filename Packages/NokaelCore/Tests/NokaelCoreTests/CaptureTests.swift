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

    /// Banks end many alerts with "never share your OTP"; that line mustn't hide the purchase
    @Test func readsAlertsThatEndWithASafetyWarning() throws {
        let cases: [(String, Decimal, String, String?)] = [
            ("Your Cr.Card XXX1234 was used for AED45.00 on 27/10/2026 10:15:22 at CARREFOUR,DUBAI-AE. Avl Cr.limit is AED 9,000.00. Never share your card details or OTP with anyone.",
             45, "Carrefour", "1234"),
            ("Your Debit Card XXX5678 was used for AED45.00 at CARREFOUR. Do not share your OTP, PIN or card details with anyone.",
             45, "Carrefour", "5678"),
            ("AED80.00 was spent on your card ending 9999 at LULU. Your available balance is AED300.00. Beware of fraud, we never ask for your OTP.",
             80, "Lulu", "9999"),
        ]
        for (text, amount, merchant, card) in cases {
            let c = try #require(read(text), "\(text)")
            #expect(c.amount == aed(amount) && c.direction == .spent, "\(text)")
            #expect(c.merchant == merchant, "\(c.merchant) for \(text)")
            #expect(c.cardHint == card, "\(text)")
        }
    }

    // MARK: - Around the world

    func read(_ text: String, home: String) -> Capture? { AlertParser.read(text, homeCurrency: home, date: now) }

    @Test func readsAlertsFromOtherCountriesAndLanguages() throws {
        let cases: [(text: String, home: String, amount: Money, merchant: String, direction: Capture.Direction)] = [
            ("Achat de 1.234,56 € chez CARREFOUR avec votre carte ****1234. Ne partagez jamais votre code.", "EUR",
             Money(1234.56, currency: "EUR"), "Carrefour", .spent),
            ("Compra por 45,00 EUR en MERCADONA con tarjeta *5678. No compartas tu código con nadie.", "EUR",
             Money(45, currency: "EUR"), "Mercadona", .spent),
            ("Kartenzahlung 12,50 EUR bei REWE MARKT am 27.10.", "EUR", Money(12.5, currency: "EUR"), "Rewe Markt", .spent),
            ("Compra de R$ 89,90 em PADARIA REAL no cartão final 4321", "BRL", Money(89.9, currency: "BRL"), "Padaria Real", .spent),
            ("You spent $18.40 at TIM HORTONS with your card ending 1111", "CAD", Money(18.4, currency: "CAD"), "Tim Hortons", .spent),
            ("Card purchase of £7.20 at PRET A MANGER", "GBP", Money(7.2, currency: "GBP"), "Pret A Manger", .spent),
            ("¥1,200 used at LAWSON with card ending 2222", "JPY", Money(1200, currency: "JPY"), "Lawson", .spent),
            ("Köp 249 kr på ICA med kort *3333", "SEK", Money(249, currency: "SEK"), "", .spent),
            ("R 350.00 paid at CHECKERS from card ...4444", "ZAR", Money(350, currency: "ZAR"), "Checkers", .spent),
            ("تم شراء بمبلغ ٤٥٫٠٠ درهم لدى كارفور ببطاقتك المنتهية 1234. لا تشارك رمز التحقق مع أحد", "AED",
             Money(45, currency: "AED"), "كارفور", .spent),
            ("Virement reçu de 2 500,00 EUR de ACME SAS. Solde 3 100,00 EUR", "EUR", Money(2500, currency: "EUR"), "", .received),
            ("Purchase of KWD 1.250 at SULTAN CENTER", "KWD", Money(1.25, currency: "KWD"), "Sultan Center", .spent),
        ]
        for c in cases {
            if c.text.hasPrefix("Köp") {
                // Swedish wording isn't in the lists; no verb and no "at", so Apple Intelligence handles it
                #expect(read(c.text, home: c.home) == nil)
                continue
            }
            let got = try #require(read(c.text, home: c.home), "\(c.text)")
            #expect(got.amount == c.amount, "\(got.amount) for \(c.text)")
            #expect(got.direction == c.direction, "\(c.text)")
            if !c.merchant.isEmpty { #expect(got.merchant == c.merchant, "\(got.merchant) for \(c.text)") }
        }
    }

    @Test func theAutomationKeywordFitsTheCountry() {
        #expect(BankSenders.keyword(region: "AE") == "AED")
        #expect(BankSenders.keyword(region: "DE") == "EUR")
        #expect(BankSenders.keyword(region: "JP") == "JPY")
        #expect(BankSenders.keyword(region: "GB") == "£")
    }

    @Test func turnsAwayCodesAndDeclinesInOtherLanguages() {
        #expect(read("Votre code de vérification est 482913. Ne le partagez pas.", home: "EUR") == nil)
        #expect(read("Compra de 30,00 EUR en ZARA rechazada por saldo insuficiente", home: "EUR") == nil)
        #expect(read("Zahlung über 20,00 EUR bei AMAZON abgelehnt", home: "EUR") == nil)
        #expect(read("رمز التحقق الخاص بك هو 4829 لعملية شراء بمبلغ 45 درهم", home: "AED") == nil)
        // A shop name containing "otp" is still a purchase
        #expect(read("Purchase of AED 3,999.00 at LAPTOP WORLD with card ending 1234", home: "AED")?.amount == aed(3999))
    }

    @Test func aLongAccountNumberIsNeitherTheShopNorMissed() throws {
        let c = try #require(read("AED 250.00 withdrawn from acc XXX123456 on 27 Oct 2026. Avl Bal AED 1,000.00"))
        #expect(c.amount == aed(250) && c.merchant.isEmpty && c.cardHint == "3456")
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

    @Test func aGuessedAmountMustBeInTheMessage() {
        #expect(AlertParser.mentions(Money(Decimal(string: "12.345")!, currency: "KWD"), in: "KWD 12.345 spent at Sultan Center"))
        #expect(AlertParser.mentions(Money(Decimal(string: "12.3")!, currency: "KWD"), in: "KWD 12.300 spent"))
        #expect(AlertParser.mentions(Money(45, currency: "AED"), in: "AED 45.00 at Carrefour"))
        #expect(AlertParser.mentions(Money(45, currency: "AED"), in: "AED 45 at Carrefour"))
        #expect(AlertParser.mentions(Money(Decimal(string: "45.5")!, currency: "EUR"), in: "45,50 € bei REWE"))
        #expect(AlertParser.mentions(Money(1500, currency: "JPY"), in: "¥1,500 のご利用"))
        #expect(AlertParser.mentions(Money(Decimal(string: "0.5")!, currency: "USD"), in: "$0.50 at Apple"))
        #expect(AlertParser.mentions(Money(120, currency: "AED"), in: "مبلغ ١٢٠ درهم"))
        #expect(!AlertParser.mentions(Money(Decimal(string: "12.345")!, currency: "KWD"), in: "KWD 12.346 spent"))
        #expect(!AlertParser.mentions(Money(99, currency: "AED"), in: "AED 45.00 at Carrefour"))
    }

    @Test func aTypedEntryMatchesOnTheSameDayAndShop() {
        let typed = entry(nil, 120, "Dewa", minutes: -240)
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 120, "DEWA SMART PAYMENT"), in: [typed]) == typed.id)
        #expect(CaptureMatcher.duplicate(of: capture(.sms, 120, "Etisalat"), in: [typed]) == nil)
    }
}
