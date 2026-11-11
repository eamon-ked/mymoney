import Testing
import NokaelCore
@testable import PersonalFinanceApp

/// An automation that passes the message (or part of it) as Sender must not get the message ignored
@MainActor
struct SenderTests {
    let text = "Debit Card XX1234 linked to account XX567890 was used for USD12.50 on Nov 11 2026 5:54PM at EXAMPLE SHOP. Available Balance USD 300.00"

    @Test func aRealSenderIsKept() {
        #expect(CaptureService.realSender("ADCBAlert", message: text) == "ADCBAlert")
        #expect(CaptureService.realSender("+971 50 123 4567", message: text) == "+971 50 123 4567")
        #expect(CaptureService.realSender("Example Bank Alerts", message: text) == "Example Bank Alerts")
    }

    @Test func theMessageAsSenderCountsAsNoSender() {
        #expect(CaptureService.realSender(text, message: text) == nil)
        #expect(CaptureService.realSender("Example: " + text, message: text) == nil)
        #expect(CaptureService.realSender("Confirmation recd. from EXAMPLE BANK: USD 90.00 transferred", message: "something else") == nil)
        #expect(CaptureService.realSender("   ", message: text) == nil)
    }

    /// With no sender to go by, a friend's text about money is ignored and says why; the same words from
    /// one of the person's banks are saved
    @Test func aFriendsTextAboutMoneyIsIgnored() async throws {
        let b = try Baseline()
        let friend = await CaptureService.runBankMessage("I sent you AED 100", sender: nil, store: b.store, isPlus: true, useAI: false)
        #expect(friend.capture == nil)
        #expect(friend.trace.steps.last?.detail == IgnoredReason.personal.sentence)
        try b.store.updateSettings { $0.bankSenders = ["ExampleBank"] }
        let bank = await CaptureService.runBankMessage("AED 100 spent at EXAMPLE SHOP", sender: "ExampleBank", store: b.store, isPlus: true, useAI: false)
        #expect(bank.capture != nil)
    }
}
