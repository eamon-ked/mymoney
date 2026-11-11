import Foundation
import Testing
@testable import NokaelCore

/// Several bank messages about one movement become one entry; two purchases that look alike stay two
struct CaptureJoinTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    func read(_ text: String, at offset: TimeInterval = 0) throws -> Capture {
        try #require(AlertParser.read(text, homeCurrency: "AED", date: now.addingTimeInterval(offset)))
    }

    /// An entry saved from a message, as the app notes it
    func saved(_ c: Capture, id: UUID = UUID(), memo: String? = nil) -> CapturedEntry {
        CapturedEntry(id: id, date: c.date, amount: c.amount, direction: c.direction, memo: memo ?? c.merchant, source: .sms,
                      reference: c.reference,
                      messages: [.init(shape: c.shape, accountHint: c.accountHint, balance: c.balance)],
                      isTransfer: c.isTransfer)
    }

    let viaApp = "AED210.00 transferred via Example Personal Internet Banking / Mobile App from acc. no. XXX450002 on Nov  9 2026  8:24PM. Avl. bal. AED 31.70."
    let confirmation = "Confirmation recd. from SECOND NATIONAL BANK PJSC: AED 210.00 transferred on 09-Nov-26 to SAMIRA OKELLO has been credited."

    @Test func theAppMessageAndTheConfirmationAreOnePayment() throws {
        let first = try read(viaApp)
        let second = try read(confirmation, at: 8)
        #expect(first.balance == aed(Decimal(string: "31.70")!))
        #expect(second.merchant == "Samira Okello")
        let id = UUID()
        #expect(CaptureMatcher.duplicate(of: second, in: [saved(first, id: id)]) == id)
        // Whichever arrives first
        #expect(CaptureMatcher.duplicate(of: first, in: [saved(second, id: id)]) == id)
    }

    @Test func twoCoffeesWordedAlikeStayTwo() throws {
        let one = try read("Your Cr.Card XXX4417 was used for AED12.00 on 09/11/2026 09:49:16 at COSTA COFFEE,DUBAI-AE.")
        let two = try read("Your Cr.Card XXX4417 was used for AED12.00 on 09/11/2026 09:51:02 at COSTA COFFEE,DUBAI-AE.", at: 120)
        #expect(one.shape == two.shape)
        #expect(CaptureMatcher.duplicate(of: two, in: [saved(one)]) == nil)
    }

    @Test func theBalanceDecides() throws {
        let one = try read("A Cr. transaction of AED 50.00 on your account no. XXX450002 was successful.Available balance is AED80.00.")
        // The same balance from a differently worded message about the same account: one movement
        let same = try read("AED 50.00 has been credited to your account XXX450002. Available balance is AED 80.00.", at: 20)
        #expect(CaptureMatcher.duplicate(of: same, in: [saved(one)]) != nil)
        // Another balance: a second deposit, however it's worded
        let other = try read("AED 50.00 has been credited to your account XXX450002. Available balance is AED 130.00.", at: 20)
        #expect(CaptureMatcher.duplicate(of: other, in: [saved(one)]) == nil)
    }

    @Test func differentAccountsStayTwo() throws {
        let one = try read("AED 50.00 was debited from your account XXX450002. Available balance is AED 10.00.")
        let two = try read("A Dr. transaction of AED 50.00 on your account no. XXX770009 was successful.", at: 30)
        #expect(CaptureMatcher.duplicate(of: two, in: [saved(one)]) == nil)
    }

    @Test func twoShopsWithNothingInCommonStayTwo() throws {
        let one = try read("Purchase of AED 30.00 at LULU HYPERMARKET with card ending 4417")
        let two = try read("AED 30.00 spent at Talabat using your card XX4417 on 09/11", at: 60)
        #expect(one.shape != two.shape)
        #expect(CaptureMatcher.duplicate(of: two, in: [saved(one)]) == nil)
    }

    @Test func thePersonAndTheBanksAppAreOnePayment() throws {
        let person = try read("You have sent AED 150.00 to Samira Okello via instant transfer.")
        let app = try read("AED150.00 transferred via Example Personal Internet Banking / Mobile App from acc. no. XXX450002 on Nov 11 2026 12:57AM. Avl. bal. AED 9.00.", at: 6)
        #expect(app.merchant.isEmpty || !CaptureMatcher.saysWho(app.merchant))
        #expect(CaptureMatcher.duplicate(of: app, in: [saved(person)]) != nil)
        // As if the app's name had been saved for it
        #expect(CaptureMatcher.duplicate(of: person, in: [saved(app, memo: "Example Personal Internet Banking / Mobile App")]) != nil)
    }

    @Test func twoPeopleStayTwo() throws {
        let one = try read("AED 100.00 transferred on 09-Nov-26 to SAMIRA OKELLO has been credited.")
        let two = try read("You have sent AED 100.00 to Daniel Mwangi via instant transfer.", at: 60)
        #expect(CaptureMatcher.duplicate(of: two, in: [saved(one)]) == nil)
    }

    @Test func farApartStayTwo() throws {
        let first = try read(viaApp)
        let second = try read(confirmation, at: 20 * 60)
        #expect(CaptureMatcher.duplicate(of: second, in: [saved(first)]) == nil)
    }

    @Test func entriesWithNoNotedMessageAreNeverJoined() throws {
        let first = try read(viaApp)
        let second = try read(confirmation, at: 8)
        let old = CapturedEntry(id: UUID(), date: first.date, amount: first.amount, direction: first.direction,
                                memo: first.merchant, source: .sms, isTransfer: true)
        #expect(CaptureMatcher.duplicate(of: second, in: [old]) == nil)
    }

    @Test func shapeLeavesOutWhatChanges() {
        let a = AlertParser.shape("AED 12.00 at COSTA on 03 Nov, card XX4417", merchant: "COSTA")
        let b = AlertParser.shape("AED 4.50 at Pret A Manger on 05 Dec, card XX1234", merchant: "Pret A Manger")
        #expect(a == b)
        #expect(!a.contains("costa") && !a.contains("4417"))
    }

    @Test func balancesAreRead() {
        #expect(AlertParser.balanceAfter(in: "Avl. bal. AED 2.89.", homeCurrency: "AED") == aed(Decimal(string: "2.89")!))
        #expect(AlertParser.balanceAfter(in: "was successful.Available balance is AED1,842.28.", homeCurrency: "AED")
                == aed(Decimal(string: "1842.28")!))
        #expect(AlertParser.balanceAfter(in: "Purchase of AED 30.00 at LULU", homeCurrency: "AED") == nil)
    }

    @Test func channelsDontSayWho() {
        #expect(!CaptureMatcher.saysWho("Example Personal Internet Banking / Mobile App"))
        #expect(!CaptureMatcher.saysWho("Domestic Transfer"))
        #expect(!CaptureMatcher.saysWho("Cr."))
        #expect(CaptureMatcher.saysWho("Samira Okello"))
    }
}
