//
//  BankCaptureTests.swift
//  Nokael Money
//
//  Bank alerts the whole way through, against an in-memory store: which account
//  they go to, what counts as the same movement, offers, reversals, transfers
//  between your own accounts, the step-by-step log, and backups keeping it all.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct BankCaptureTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let main: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let now = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12, minute: 30))!

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = now
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        main = try store.createAccount(name: "Main account", kind: .bank, opening: Self.aed(5000), openingDate: now.addingTimeInterval(-86400 * 30))
        savings = try store.createAccount(name: "Account …0001", kind: .savings, opening: Self.aed(1000), openingDate: now.addingTimeInterval(-86400 * 30))
        try store.setAccountNumber(main.id, "70345126730001")
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = savings.id; $0.localeIdentifier = "en_AE" }
    }

    func run(_ message: String, sender: String? = "ADCBAlert", plus: Bool = true, dryRun: Bool = false) async -> CaptureService.Run {
        await CaptureService.runBankMessage(message, sender: sender, store: store, isPlus: plus, dryRun: dryRun, useAI: false)
    }

    var posted: [EntryRecord] { store.snapshot.entryRecords.filter { $0.status == .posted && $0.kind != .openingBalance } }

    /// The automation runs twice for one message, the second time with the message as Sender:
    /// the second run is read now, and must find the first entry rather than save it again
    @Test func theSameMessageRunTwiceWithTheMessageAsSenderSavesOnce() async throws {
        let text = "Debit Card XX4417 linked to account XX730001 was used for AED45.00 on Nov 3 2026 12:22PM at EXAMPLE SHOP, AE. Available Balance AED 525.19"
        let first = await run(text, sender: nil)
        let second = await run(text, sender: CaptureService.realSender(text, message: text))
        guard case .saved(let id) = first.outcome else { Issue.record("first wasn't saved"); return }
        #expect(second.outcome == .merged(id) || second.outcome == .joined(id))
        #expect(posted.filter { $0.memo.localizedCaseInsensitiveContains("example shop") }.count == 1)
    }

    @Test func aPurchaseGoesToTheAccountItNamesNotTheLastOneUsed() async throws {
        let r = await run("Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 on 03/11/2026 12:22:05 at CARREFOUR,ABU DHABI-AE. Avl.Bal.AED525.19")
        guard case .saved(let id)? = r.outcome else { Issue.record("not saved: \(r.trace.steps)"); return }
        let record = try #require(store.entryRecord(id))
        #expect(record.lines.contains { $0.accountId == main.id })
        #expect(record.reviewReason == nil)
        let minute = LedgerStoreTests.dubai.component(.minute, from: record.date)
        #expect(minute == 22)
        #expect(r.trace.steps.map(\.mark) == [.done, .done, .done, .done])
    }

    @Test func anAccountItCantTellIsSavedButAsked() async throws {
        let r = await run("AED 60.00 has been debited from your account XXX777777 at TALABAT on 03/11/2026")
        guard case .saved(let id)? = r.outcome, let record = store.entryRecord(id) else { Issue.record("not saved"); return }
        #expect(record.needsReview && record.reviewReason == "Which of your accounts is ••777777?")
        #expect(record.cardHint == "account 777777")
        // Once the person says which, later ones go there by themselves
        try store.linkCard(record.cardHint!, to: savings.id)
        let next = await run("AED 20.00 has been debited from your account XXX777777 at CAFE on 03/11/2026")
        guard case .saved(let second)? = next.outcome else { Issue.record("not saved"); return }
        #expect(store.entryRecord(second)?.lines.contains { $0.accountId == savings.id } == true)
        #expect(store.entryRecord(second)?.reviewReason == nil)
    }

    @Test func separatePurchasesStaySeparateAndRetriesDont() async throws {
        let first = "Your debit card XXX4417 linked to acc. XXX730001 was used for AED30.00 on 03/11/2026 12:01:10 at E& DIGITAL"
        let second = "Your debit card XXX4417 linked to acc. XXX730001 was used for AED30.00 on 03/11/2026 12:03:44 at E& DIGITAL"
        _ = await run(first)
        let again = await run(first)
        let other = await run(second)
        guard case .merged? = again.outcome, case .saved? = other.outcome else {
            Issue.record("retry \(String(describing: again.outcome)), second \(String(describing: other.outcome))"); return
        }
        #expect(posted.filter { $0.kind == .expense }.count == 2)
    }

    @Test func theSameWordsWithNoDateOnAnotherDayAreANewPurchase() async throws {
        let text = "AED 30.00 spent on card XXX4417 at TALABAT"
        let today = await run(text)
        let calendar = LedgerStoreTests.dubai
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let later = LedgerStore(context: container.mainContext, calendar: calendar, now: { tomorrow })
        let next = await CaptureService.runBankMessage(text, sender: "ADCBAlert", store: later, isPlus: true, useAI: false)
        guard case .saved(let a)? = today.outcome, case .saved(let b)? = next.outcome else { Issue.record("not both saved"); return }
        #expect(a != b)
    }

    @Test func offersAndCodesAreTurnedAwayWithTheReason() async throws {
        let offer = await run("Get up to 10% cashback on AED 500 spends with your ADCB card. T&C apply.")
        #expect(offer.outcome == .skipped("No purchase or deposit in that message."))
        #expect(offer.trace.steps.last?.detail == IgnoredReason.promotion.sentence)
        let stranger = await run("AED 45.00 at CARREFOUR", sender: "Careem")
        #expect(stranger.trace.steps.isEmpty == false)
        try store.updateSettings { $0.bankSenders = ["ADCBAlert"] }
        let ignored = await run("AED 45.00 at CARREFOUR", sender: "Careem")
        #expect(ignored.outcome == nil && ignored.trace.steps.first?.mark == .failed)
        #expect(posted.filter { $0.memo.contains("Carrefour") }.count == 1)
    }

    @Test func withoutPlusTheLogSaysSo() async throws {
        let r = await run("AED 45.00 spent on card XXX4417 at NOON", plus: false)
        #expect(r.outcome == .needsPlus)
        #expect(r.trace.steps.map(\.mark) == [.done, .done, .failed, .notReached])
        #expect(store.captureTraces.first?.steps == r.trace.steps)
    }

    @Test func theTestShowsEveryStepAndSavesNothing() async throws {
        let r = await run("Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 at CARREFOUR", dryRun: true)
        #expect(r.trace.steps.count == 4)
        #expect(r.trace.steps.last?.detail.hasPrefix("To Main account in") == true)
        #expect(posted.isEmpty)
        #expect(store.captureTraces.isEmpty)
    }

    @Test func aReversalRemovesTheUncheckedChargeOnce() async throws {
        let charge = "Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 on 03/11/2026 10:00:00 at CARREFOUR"
        _ = await run(charge)
        let back = await run("Reversal of AED45.00 for CARREFOUR has been credited to your card XXX4417")
        guard case .reversed? = back.outcome else { Issue.record("expected reversal, got \(String(describing: back.outcome))"); return }
        #expect(posted.isEmpty)
        #expect(store.snapshot.balance(main.id) == Self.aed(5000))
        // The original alert arriving again isn't saved a second time
        let retried = await run(charge)
        guard case .merged? = retried.outcome else { Issue.record("re-saved after reversal"); return }
        #expect(posted.isEmpty)
    }

    @Test func aTransferBetweenYourOwnAccountsIsOneTransfer() async throws {
        try store.linkAccount(digits: "240001", to: savings.id)
        let out = await run("AED1,000.00 has been transferred from your account XXX730001 to account XXX240001 on 03/11/2026. Ref 49051225550")
        guard case .saved(let id)? = out.outcome else { Issue.record("not saved: \(out.trace.steps)"); return }
        #expect(store.entryRecord(id)?.kind == .transfer)
        let into = await run("AED1,000.00 has been credited to your account XXX240001 from account XXX730001. Ref 49051225550")
        // The other bank's half joins the transfer already saved
        switch into.outcome {
        case .merged?, .joined?: break
        default: Issue.record("saved twice: \(String(describing: into.outcome))"); return
        }
        let s = store.snapshot
        #expect(s.balance(main.id) == Self.aed(4000) && s.balance(savings.id) == Self.aed(2000))
        #expect(posted.count == 1)
    }

    @Test func aTransferToSomeoneAsksWhereItWent() async throws {
        let r = await run("AED150.00 has been transferred from your account XXX730001 to SARA AHMED on 03/11/2026. Ref 41235832494")
        guard case .saved(let id)? = r.outcome, let record = store.entryRecord(id) else { Issue.record("not saved"); return }
        #expect(record.kind == .expense && record.reference == "41235832494")
        #expect(record.reviewReason == "Was this sent to someone, or moved to another of your accounts?")
        #expect(record.lines.contains { $0.accountId == store.peopleCategory.id })
    }

    @Test func oneSMSJoinsAWalletTapOnlyOnce() async throws {
        let tap = Capture(source: .applePay, direction: .spent, amount: Self.aed(45), merchant: "Carrefour", cardHint: "ADCB Debit",
                          date: now.addingTimeInterval(-240), text: "ADCB Debit|Carrefour|45")
        try store.linkCard("ADCB Debit", to: main.id)
        _ = await CaptureService.runCardPurchase(tap, store: store, isPlus: true)
        let sms = await run("Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 at MAF CARREFOUR")
        let another = await run("Your debit card XXX4417 linked to acc. XXX730001 was used for AED45.00 on 03/11/2026 12:29:00 at MAF CARREFOUR CITY")
        guard case .merged? = sms.outcome, case .saved? = another.outcome else {
            Issue.record("sms \(String(describing: sms.outcome)), another \(String(describing: another.outcome))"); return
        }
        #expect(posted.count == 2)
    }

    @Test func backupsKeepHowEntriesArrivedAndLinkedCards() async throws {
        let r = await run("AED150.00 has been transferred from your account XXX730001 to SARA AHMED. Ref 41235832494")
        try store.linkCard("ADCB Debit", to: main.id)
        guard case .saved(let id)? = r.outcome else { Issue.record("not saved"); return }
        let data = try store.backupData()
        try store.restore(try LedgerStore.readBackup(data))
        let record = try #require(store.entryRecord(id))
        #expect(record.source == .sms && record.needsReview && record.reference == "41235832494")
        #expect(record.reviewReason != nil && record.cardHint == "account 730001")
        #expect(store.linkedAccount(forCard: "adcb debit") == main.id)
    }

    @Test func aStatementImportIsAllOrNothing() throws {
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2800),
                               schedule: Schedule(start: now.addingTimeInterval(86400 * 2), frequency: .monthly(every: 1)),
                               accountId: main.id, categoryId: store.snapshot.expenseCategories.first!.id)
        try store.savePlannedItem(rent)
        let occ = try #require(store.snapshot.occurrences.first)
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        let rows = [
            LedgerStore.ImportedRow(date: now, memo: "Carrefour", amount: Self.aed(-150), target: .category(groceries.id), key: UUID()),
            // More than the bill: refused, so nothing from this import may stay
            LedgerStore.ImportedRow(date: now, memo: "Rent", amount: Self.aed(-9000), target: .bill(occ.id), key: UUID()),
        ]
        #expect(throws: (any Error).self) { try store.importRows(rows, into: main.id) }
        #expect(posted.isEmpty)
        #expect(store.snapshot.balance(main.id) == Self.aed(5000))
        #expect(!store.hasImportedStatement(into: main.id))
    }

    @Test func aCategoryWithABillKeepsTheRestOfItsBudgetInSafeToSpend() throws {
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        try store.updateAccount(groceries) { $0.reserveInSafeToSpend = true }
        try store.setAllocation(Self.aed(1000), categoryId: groceries.id, month: store.snapshot.monthKey)
        let box = PlannedItem(name: "Veg box", direction: .outflow, amount: Self.aed(200),
                              schedule: Schedule(start: now.addingTimeInterval(86400 * 2), frequency: .monthly(every: 1)),
                              accountId: main.id, categoryId: groceries.id)
        try store.savePlannedItem(box)
        let s = store.snapshot.safeToSpend(through: store.snapshot.endOfDay(now.addingTimeInterval(86400 * 10)))
        #expect(s.categoryReservationsTotal == Self.aed(800))
        #expect(s.obligations.map(\.amount).contains(Self.aed(200)))
    }

    /// Alerts in ADCB's wording with made-up details, over two days, each saved once to the account they name
    @Test func adcbStyleAlertsSaveOnceEach() async throws {
        let adcb = try store.createAccount(name: "ADCB", kind: .bank, opening: Self.aed(500), openingDate: now.addingTimeInterval(-86400 * 30))
        try store.setAccountNumber(adcb.id, "12345560001")
        let calendar = LedgerStoreTests.dubai
        let alerts: [(String, DateComponents)] = [
            ("AED100.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  6 2026 10:38AM. Avl. bal. AED 7.01.",
             DateComponents(year: 2026, month: 11, day: 6, hour: 10, minute: 38)),
            ("A Cr. transaction of AED 100.00 on your account no. XXX560001 was successful.Available balance is AED107.51.",
             DateComponents(year: 2026, month: 11, day: 6, hour: 19, minute: 20)),
            ("AED100.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  6 2026  7:33PM. Avl. bal. AED 106.51.",
             DateComponents(year: 2026, month: 11, day: 6, hour: 19, minute: 33)),
            ("A Cr. transaction of AED 150.00 on your account no. XXX560001 was successful.Available balance is AED334.52.",
             DateComponents(year: 2026, month: 11, day: 7, hour: 13, minute: 0)),
            ("AED300.00 transferred via ADCB Personal Internet Banking / Mobile App from acc. no. XXX560001 on Nov  7 2026  2:12PM. Avl. bal. AED 34.02.",
             DateComponents(year: 2026, month: 11, day: 7, hour: 14, minute: 12)),
        ]
        for (text, when) in alerts {
            let arrived = calendar.date(from: when)!
            let at = LedgerStore(context: container.mainContext, calendar: calendar, now: { arrived })
            for _ in 0..<2 { // the automation running twice must not save twice
                _ = await CaptureService.runBankMessage(text, sender: "ADCBAlert", store: at, isPlus: true, useAI: false)
            }
        }
        let saved = posted.filter { $0.lines.contains { $0.accountId == adcb.id } }
        #expect(saved.count == 5)
        // Seen on the day of the last alert: the store's own "today" is before them
        let after = LedgerStore(context: container.mainContext, calendar: calendar, now: { calendar.date(from: alerts.last!.1)! })
        #expect(after.snapshot.balance(adcb.id) == Self.aed(250)) // 500 - 100 + 100 - 100 + 150 - 300
        let out = saved.filter { $0.kind == .expense }
        #expect(out.count == 3 && out.allSatisfy { $0.reviewReason == "Was this sent to someone, or moved to another of your accounts?" })
        let times = out.map { calendar.dateComponents([.day, .hour, .minute], from: $0.date) }.map { "\($0.day!) \($0.hour!):\($0.minute!)" }
        #expect(Set(times) == ["6 10:38", "6 19:33", "7 14:12"])
        #expect(saved.filter { $0.kind == .income }.count == 2)
    }
}
