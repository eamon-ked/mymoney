//
//  CaptureServiceTests.swift
//  Nokael Money
//
//  Apple Pay, bank SMS and Siri captures against an in-memory store.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct CaptureServiceTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let account: LedgerAccountRecord
    let card: LedgerAccountRecord
    let now = LedgerStoreTests.date(2026, 10, 25)

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = now
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        account = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(5000), openingDate: now)
        card = try store.createAccount(name: "ENBD Visa", kind: .creditCard, opening: Self.aed(0), openingDate: now)
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = account.id }
    }

    func applePay(_ amount: Decimal, _ merchant: String, card: String = "ENBD Visa", minutes: Double = 0) -> Capture {
        Capture(source: .applePay, direction: .spent, amount: Self.aed(amount), merchant: merchant, cardHint: card,
                date: now.addingTimeInterval(minutes * 60), text: "\(card)|\(merchant)|\(amount)")
    }

    @Test func applePaySavesOnceForReview() async throws {
        let first = try await CaptureService.record(applePay(45, "Carrefour"), in: store, isPlus: true)
        let again = try await CaptureService.record(applePay(45, "Carrefour"), in: store, isPlus: true)
        guard case .saved(let id) = first else { Issue.record("not saved: \(first)"); return }
        #expect(again == .merged(id))
        let record = try #require(store.entryRecord(id))
        #expect(record.needsReview && record.source == .applePay && record.cardHint == "ENBD Visa")
        #expect(store.snapshot.balance(account.id) == Self.aed(4955))
    }

    @Test func theBankSMSForAnApplePayTapIsNotCountedTwice() async throws {
        _ = try await CaptureService.record(applePay(45, "Carrefour", minutes: -4), in: store, isPlus: true)
        let sms = try #require(await CaptureService.read(
            message: "Purchase of AED 45.00 at MAF CARREFOUR CITY with card ending 1234", homeCurrency: "AED", date: now))
        let outcome = try await CaptureService.record(sms, in: store, isPlus: true)
        guard case .merged = outcome else { Issue.record("expected merge, got \(outcome)"); return }
        #expect(store.snapshot.entries().filter { $0.kind == .expense }.count == 1)
    }

    @Test func aBankSMSArrivingAgainAfterItsEntryWasDeletedIsSavedAgain() async throws {
        let message = "Purchase of AED 45.00 at MAF CARREFOUR CITY with card ending 1234"
        let sms = try #require(await CaptureService.read(message: message, homeCurrency: "AED", date: now))
        guard case .saved(let first) = try await CaptureService.record(sms, in: store, isPlus: true) else {
            Issue.record("not saved"); return
        }
        try store.void(first)
        let outcome = try await CaptureService.record(sms, in: store, isPlus: true)
        guard case .saved(let second) = outcome else { Issue.record("expected save, got \(outcome)"); return }
        #expect(second != first)
        #expect(store.snapshot.entries().map(\.id).contains(second))
        #expect(store.snapshot.balance(account.id) == Self.aed(4955))
    }

    @Test func theLastCardPurchaseSaysWhatHappened() async throws {
        #expect(store.lastCardPurchase == nil)
        let outcome = try await CaptureService.record(applePay(45, "Carrefour"), in: store, isPlus: false)
        store.noteCardPurchase(card: "ENBD Visa", outcome: outcome.logLine)
        #expect(store.lastCardPurchase?.summary == "On ENBD Visa: not saved, needs Nokael Plus")
        #expect(store.lastBankMessage == nil)
        #expect(CaptureService.Outcome.skipped("There was no amount to save.").logLine == "not saved. There was no amount to save.")
    }

    @Test func aLinkedCardGoesToItsAccount() async throws {
        try store.linkCard("enbd visa ", to: card.id)
        let outcome = try await CaptureService.record(applePay(18, "Starbucks"), in: store, isPlus: true)
        guard case .saved = outcome else { Issue.record("not saved"); return }
        #expect(store.snapshot.balance(card.id) == Self.aed(-18))
        #expect(store.snapshot.balance(account.id) == Self.aed(5000))
    }

    @Test func automaticCaptureNeedsPlusButSiriDoesNot() async throws {
        #expect(try await CaptureService.record(applePay(45, "Carrefour"), in: store, isPlus: false) == .needsPlus)
        let spoken = try #require(AlertParser.spoken("20 at Costa", homeCurrency: "AED", date: now))
        guard case .saved = try await CaptureService.record(spoken, in: store, isPlus: false) else {
            Issue.record("Siri should save without Plus"); return
        }
    }

    @Test func theShopsLastCategoryIsReused() async throws {
        let groceries = store.snapshot.accountRecords.first { $0.name == "Groceries" }!
        try store.post(try EntryFactory.expense(Self.aed(80), from: account.info, category: groceries.info,
                                                date: now.addingTimeInterval(-86400 * 3), memo: "Carrefour"))
        guard case .saved(let id) = try await CaptureService.record(applePay(45, "Carrefour City"), in: store, isPlus: true) else {
            Issue.record("not saved"); return
        }
        let lines = try #require(store.entryRecord(id)).lines.map(\.accountId)
        #expect(lines.contains(groceries.id))
    }

    @Test func foreignCurrencyIsNotSavedAsIfItWereDirhams() async throws {
        let usd = Capture(source: .sms, direction: .spent, amount: Money(20, currency: "USD"), merchant: "Uber", date: now)
        guard case .skipped = try await CaptureService.record(usd, in: store, isPlus: true) else {
            Issue.record("should skip"); return
        }
        #expect(store.snapshot.entries().filter { $0.kind == .expense }.isEmpty)
    }

    @Test func onlyChosenSendersAreRead() throws {
        try store.updateSettings { $0.bankSenders = ["ADCBAlert"] }
        #expect(CaptureService.accepts(sender: "ADCBAlert", settings: store.settings))
        #expect(!CaptureService.accepts(sender: "Careem", settings: store.settings))
        try store.updateSettings { $0.bankSenders = [] }
        #expect(CaptureService.accepts(sender: "Careem", settings: store.settings))
    }

    @Test func editingAnAutomaticEntryReviewsIt() async throws {
        guard case .saved(let id) = try await CaptureService.record(applePay(45, "Carrefour"), in: store, isPlus: true) else {
            Issue.record("not saved"); return
        }
        let transport = store.snapshot.accountRecords.first { $0.name == "Transport" }!
        let replacement = try EntryFactory.expense(Self.aed(45), from: account.info, category: transport.info, date: now, memo: "Carrefour")
        let newId = try store.replace(id, with: replacement)
        let record = try #require(store.entryRecord(newId))
        #expect(!record.needsReview && record.source == .applePay)
    }
}
