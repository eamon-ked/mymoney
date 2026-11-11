//
//  MessageJoinTests.swift
//  Nokael Money
//
//  Banks send two or three messages about one payment. They become one entry,
//  and everything the app did with them can be looked at, undone or changed.
//  Names and numbers are made up; the wording follows real alerts.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct MessageJoinTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let main: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let now = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 20, minute: 30))!

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = now
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        main = try store.createAccount(name: "Main account", kind: .bank, opening: Self.aed(5000), openingDate: now.addingTimeInterval(-86400 * 30))
        savings = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(1000), openingDate: now.addingTimeInterval(-86400 * 30))
        try store.setAccountNumber(main.id, "70345126730001")
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = main.id; $0.localeIdentifier = "en_AE" }
    }

    func run(_ message: String, plus: Bool = true) async -> CaptureService.Run {
        await CaptureService.runBankMessage(message, sender: nil, store: store, isPlus: plus, useAI: false)
    }

    /// What Edit details does when the person changes the account of a spending entry
    @discardableResult
    func move(_ id: UUID, to account: LedgerAccountRecord) throws -> UUID {
        let r = try #require(store.entryRecord(id))
        let category = try #require(r.lines.compactMap { store.account($0.accountId) }.first { $0.kind.isCategory })
        let amount = Money(minorUnits: r.lines.first { $0.minorUnits > 0 }!.minorUnits, currency: "AED")
        let e = try EntryFactory.expense(amount, from: account.info, category: category.info, date: r.date, memo: r.memo, key: UUID())
        return try store.replace(id, with: e)
    }

    var posted: [EntryRecord] { store.snapshot.entryRecords.filter { $0.status == .posted && $0.kind != .openingBalance } }

    let viaApp = "AED210.00 transferred via Example Personal Internet Banking / Mobile App from acc. no. XXX730001 on Nov  9 2026  8:24PM. Avl. bal. AED 31.70."
    let confirmation = "Confirmation recd. from SECOND NATIONAL BANK PJSC: AED 210.00 transferred on 09-Nov-26 to SAMIRA OKELLO has been credited."

    // MARK: - Joining

    @Test func theAppMessageAndTheConfirmationBecomeOneEntry() async throws {
        let first = await run(viaApp)
        guard case .saved(let id)? = first.outcome else { Issue.record("first: \(first.trace.steps)"); return }
        let second = await run(confirmation)
        guard case .joined(let joined)? = second.outcome else { Issue.record("second: \(second.trace.steps)"); return }
        #expect(joined == id)
        #expect(posted.count == 1)
        let record = try #require(store.entryRecord(id))
        #expect(record.memo == "Samira Okello")
        #expect(record.needsReview && record.reviewReason == LedgerStore.joinedMessagesReason)
        #expect(second.trace.joined == true && second.trace.steps.last?.detail.contains("Joined") == true)
        #expect(store.captureTraces(forEntry: id).count == 2)
    }

    @Test func aJoinedMessageCanBeMadeItsOwnPaymentAndUndone() async throws {
        _ = await run(viaApp)
        _ = await run(confirmation)
        let joined = try #require(store.captureTraces.first { $0.joined == true })
        let separate = try await CaptureService.saveOnItsOwn(joined, in: store)
        #expect(posted.count == 2)
        let record = try #require(store.entryRecord(separate))
        #expect(record.needsReview)
        #expect(record.lines.contains { $0.minorUnits == -21000 })
        // The record now points at the new entry and isn't joined any more
        let after = try #require(store.captureTraces.first { $0.id == joined.id })
        #expect(after.joined == nil && after.entryId == separate)
        try CaptureService.undoSaveOnItsOwn(separate, trace: joined, in: store)
        #expect(posted.count == 1)
        #expect(store.captureTraces.first { $0.id == joined.id }?.joined == true)
    }

    @Test func aMoveBetweenYourAccountsFromThreeMessagesIsOneTransfer() async throws {
        let debit = "AED 117.00 plus applicable charges was Debited from your account XXXXXX240001 on 2026-11-09. Available balance is AED 27.50."
        let credit = "A Cr. transaction of AED 117.00 on your account no. XXX730001 was successful.Available balance is AED5,117.00."
        let channel = "Your fund transfer of AED 117.00 via Domestic Transfer has been processed. Ref 25-23305598."
        let out = await run(debit)
        guard case .saved(let outId)? = out.outcome else { Issue.record("debit: \(out.trace.steps)"); return }
        #expect(store.entryRecord(outId)?.reviewReason == "Which of your accounts is ••240001?")
        _ = await run(credit)
        // The account for ••240001 isn't known yet, so nothing is joined behind the person's back
        #expect(posted.count == 2)
        // The person moves it to Savings and says ••240001 is always Savings
        let current = try move(outId, to: savings)
        #expect(store.currentEntryId(from: outId) == current)
        try store.linkCard(LedgerStore.accountLinkKey("240001"), to: savings.id)
        let transfers = posted.filter { $0.kind == .transfer }
        #expect(transfers.count == 1, "\(posted.map { ($0.kind, $0.memo) })")
        #expect(posted.count == 1)
        // The bank's third message joins that move
        let third = await run(channel)
        guard case .joined? = third.outcome else { Issue.record("third: \(third.trace.steps)"); return }
        #expect(posted.count == 1)
    }

    @Test func theSameMoveWhenTheBanksMessageComesFirst() async throws {
        _ = await run("Your fund transfer of AED 117.00 via Domestic Transfer has been processed. Ref 25-23305598.")
        let out = await run("AED 117.00 plus applicable charges was Debited from your account XXXXXX240001 on 2026-11-09. Available balance is AED 27.50.")
        guard case .joined? = out.outcome else { Issue.record("debit: \(out.trace.steps)"); return }
        _ = await run("A Cr. transaction of AED 117.00 on your account no. XXX730001 was successful.Available balance is AED5,117.00.")
        #expect(posted.count == 2)
        // Saying ••240001 is Savings moves the joined entry there and makes the pair one move
        try store.linkCard(LedgerStore.accountLinkKey("240001"), to: savings.id)
        #expect(posted.count == 1, "\(posted.map { ($0.kind, $0.memo) })")
        let move = try #require(posted.first)
        #expect(move.kind == .transfer)
        #expect(move.lines.contains { $0.accountId == savings.id && $0.minorUnits == -11700 })
        #expect(move.lines.contains { $0.accountId == main.id && $0.minorUnits == 11700 })
    }

    @Test func twoMessagesWithDifferentBalancesAreTwoPayments() async throws {
        _ = await run("A Cr. transaction of AED 50.00 on your account no. XXX730001 was successful.Available balance is AED80.00.")
        let second = await run("AED 50.00 has been credited to your account XXX730001. Available balance is AED 130.00.")
        guard case .saved? = second.outcome else { Issue.record("second: \(second.trace.steps)"); return }
        #expect(posted.count == 2)
    }

    @Test func theAIsMadeUpNamesAreRefused() {
        let message = "A Cr. transaction of AED 334.39 on your account no. XXX560001 was successful."
        #expect(!CaptureService.believableName("Cr.", in: message))
        #expect(!CaptureService.believableName("X", in: "Debited from your account XXXXXX000001"))
        #expect(!CaptureService.believableName("Talabat", in: message))
        #expect(CaptureService.believableName("Samira Okello", in: confirmation))
    }

    // MARK: - Reviewing and changing

    @Test func aMessageNotSavedWithoutPlusCanBeAddedLater() async throws {
        let r = await run(confirmation, plus: false)
        #expect(posted.isEmpty)
        let trace = try #require(store.captureTraces.first { $0.id == r.trace.id } ?? store.captureTraces.first)
        #expect(trace.read != nil)
        let id = try await CaptureService.saveOnItsOwn(trace, in: store)
        #expect(posted.map(\.id) == [id])
        #expect(store.entryRecord(id)?.needsReview == true)
        // Adding it again from the same record doesn't save it twice
        let again = try #require(store.captureTraces.first { $0.entryId == id })
        #expect(store.currentEntryId(from: again.entryId!) == id)
    }

    @Test func olderRecordsAreReadFromTheirReadLine() throws {
        let read = try #require(CaptureTrace.Read(line: "Spent AED 150.00 to Daniel Mwangi · transfer · account ••560001 · 11 Nov 2026 at 00:57",
                                                  arrived: now, currency: "AED"))
        #expect(read.spent && read.amount == Self.aed(150))
        #expect(read.name == "Daniel Mwangi" && read.isTransfer && read.accountHint == "560001")
        #expect(CaptureTrace.Read(line: "No amount with a currency was found in it.", arrived: now, currency: "AED") == nil)
    }

    @Test func aMaybeTheSameEntryCanBeJoinedOrKept() async throws {
        // An entry saved from a message before records kept what messages looked like
        let entry = try EntryFactory.expense(Self.aed(80), from: main.info, category: store.peopleCategory.info,
                                             date: now.addingTimeInterval(-120), memo: "Sent to people", key: UUID())
        let old = try store.postCaptured(entry, source: .sms, cardHint: nil, needsReview: false)
        let r = await run("You have sent AED 80.00 to Daniel Mwangi via instant transfer.")
        guard case .saved(let id)? = r.outcome else { Issue.record("\(r.trace.steps)"); return }
        #expect(store.entryRecord(id)?.reviewReason?.hasPrefix("Maybe the same as") == true)
        try CaptureService.confirmSame(id, as: old, in: store)
        #expect(posted.map(\.id) == [old])
        // Undo brings it back
        try store.restore(id)
        try CaptureService.keepSeparate(id, in: store)
        #expect(posted.count == 2 && store.entryRecord(id)?.needsReview == false)
    }

    @Test func deletedEntriesCanBeRestoredButNotOnesChangedSince() async throws {
        let r = await run(viaApp)
        guard case .saved(let id)? = r.outcome else { return }
        try store.void(id)
        #expect(posted.isEmpty)
        try store.restore(id)
        #expect(posted.map(\.id) == [id])
        try move(id, to: savings)
        #expect(throws: StoreError.self) { try store.restore(id) }
    }

    @Test func aMoveBetweenAccountsCanGoBackToTwoEntries() async throws {
        let out = await run("AED 300.00 was debited from your account XXX730001 towards transfer. Available balance is AED 4,700.00.")
        guard case .saved(let outId)? = out.outcome else { Issue.record("\(out.trace.steps)"); return }
        let into = try EntryFactory.income(Self.aed(300), to: savings.info, category: store.fromPeopleCategory.info,
                                           date: now, memo: "From people", key: UUID())
        _ = try store.postCaptured(into, source: .sms, cardHint: nil, needsReview: true)
        let transfer = try store.recordAsTransfer(outId, other: savings.id)
        #expect(posted.count == 1 && posted.first?.kind == .transfer)
        let halves = try store.unpairTransfer(transfer)
        #expect(halves.count == 2 && posted.count == 2 && !posted.contains { $0.kind == .transfer })
        try store.repairTransfer(transfer, halves: halves)
        #expect(posted.count == 1 && posted.first?.kind == .transfer)
    }

    @Test func clearingRecordsKeepsEntries() async throws {
        _ = await run(viaApp)
        try store.clearCaptureTraces()
        #expect(store.captureTraces.isEmpty)
        #expect(posted.count == 1)
    }
}
