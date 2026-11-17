//
//  AccountNumberTests.swift
//  Nokael Money
//
//  An account number the person types, always optional, against made-up bank messages and statements.
//  The two accounts share their last four digits, as one customer's accounts at a bank often do.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct AccountNumberTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let calendar = LedgerStoreTests.dubai
    let now = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 18, minute: 0))!

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = now
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        let start = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        current = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(0), openingDate: start)
        savings = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(500), openingDate: start)
        try store.updateSettings { $0.onboardingDone = true; $0.lastUsedAccountId = current.id; $0.localeIdentifier = "en_AE" }
    }

    // Made-up numbers: 5550 1234 640001 and 5550 1234 870001
    let moneyOut = "AED20.00 transferred via Mobile App from acc. no. XXX870001 on Nov  3 2026  5:03PM. Avl. bal. AED 480.00."
    let moneyIn = "A Cr. transaction of AED 20.00 on your account no. XXX640001 was successful.Available balance is AED20.00."

    func run(_ message: String, at minute: Int) async -> CaptureService.Run {
        let arrived = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 17, minute: minute))!
        let at = LedgerStore(context: container.mainContext, calendar: calendar, now: { arrived })
        return await CaptureService.runBankMessage(message, sender: "BankAlert", store: at, isPlus: true, useAI: false)
    }

    var posted: [EntryRecord] { store.snapshot.entryRecords.filter { $0.status == .posted && $0.kind != .openingBalance } }

    @Test func typedDigitsAreKeptAndShortOnesRefused() throws {
        #expect(AccountNumber.normalized("5550-1234 640001") == "55501234640001")
        #expect(AccountNumber.normalized("AE07 0331 2345 6789") == "07033123456789")
        #expect(AccountNumber.normalized("001") == nil)
        try store.setAccountNumber(current.id, typed: "5550 1234 640001")
        #expect(store.account(current.id)?.accountNumber == "55501234640001")
        try store.setAccountNumber(current.id, typed: nil)
        #expect(store.account(current.id)?.accountNumber == nil)
    }

    @Test func aTypedNumberSendsEachMessageToItsAccount() async throws {
        try store.setAccountNumber(current.id, typed: "5550 1234 640001")
        try store.setAccountNumber(savings.id, typed: "870001")
        _ = await run(moneyOut, at: 3)
        _ = await run(moneyIn, at: 3)
        // Both accounts known: the two messages are one move between them, with nothing to ask
        #expect(posted.count == 1 && posted[0].kind == .transfer && !posted[0].needsReview)
        #expect(store.snapshot.balance(current.id) == Self.aed(20) && store.snapshot.balance(savings.id) == Self.aed(480))
    }

    @Test func fourSharedDigitsAreNotEnoughToTell() async throws {
        try store.setAccountNumber(current.id, typed: "0001")
        #expect(store.accountNumberClashes("0001", for: savings.id).map(\.id) == [current.id])
        #expect(store.accountNumberClashes("870001", for: savings.id).map(\.id) == [current.id])
        try store.setAccountNumber(savings.id, typed: "0001")
        _ = await run(moneyOut, at: 3)
        let saved = try #require(posted.first)
        // Never a guess between two accounts that both end in 0001
        #expect(saved.needsReview && saved.reviewReason?.contains("870001") == true)
        // Six digits each tell them apart
        #expect(store.accountNumberClashes("640001", for: current.id).map(\.id) == [savings.id])
        try store.setAccountNumber(savings.id, typed: "870001")
        try store.setAccountNumber(current.id, typed: "640001")
        #expect(store.accountNumberClashes("640001", for: current.id).isEmpty)
        #expect(store.accountMatching(digits: "870001") == savings.id && store.accountMatching(digits: "640001") == current.id)
    }

    @Test func endingsShownAreLongEnoughToTellApart() {
        #expect(AccountNumber.shortEnding("55501234640001", among: ["55501234870001"]) == "640001")
        #expect(AccountNumber.shortEnding("55501234640001", among: ["99998888"]) == "0001")
        #expect(AccountNumber.shortEnding("640001", among: []) == "0001")
        // Even when six digits are shared, as many more as it takes
        #expect(AccountNumber.shortEnding("55501234640001", among: ["55501299640001"]) == "4640001")
    }

    @Test func typingTheNumbersLaterJoinsTheTwoMessages() async throws {
        _ = await run(moneyOut, at: 3)
        _ = await run(moneyIn, at: 3)
        // Unknown digits: both guessed onto the last used account, each with a question
        #expect(posted.count == 2 && posted.allSatisfy(\.needsReview))
        try store.setAccountNumber(savings.id, typed: "870001")
        try store.setAccountNumber(current.id, typed: "5550 1234 640001")
        #expect(posted.count == 1 && posted[0].kind == .transfer && !posted[0].needsReview)
        #expect(store.snapshot.balance(current.id) == Self.aed(20) && store.snapshot.balance(savings.id) == Self.aed(480))
    }

    @Test func answeringWhoseDigitsTheyAreSettlesTheQuestion() async throws {
        _ = await run(moneyOut, at: 3)
        _ = await run(moneyIn, at: 3)
        try store.linkAccount(digits: "870001", to: savings.id)
        try store.linkAccount(digits: "640001", to: current.id)
        #expect(posted.count == 1 && posted[0].kind == .transfer && !posted[0].needsReview)
        #expect(store.snapshot.balance(savings.id) == Self.aed(480))
    }

    // MARK: - Statements

    func post(_ memo: String, _ amount: Decimal, day: Int, category: String = "Groceries") throws -> UUID {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
        let s = store.snapshot
        if amount > 0 {
            let c = try #require(s.incomeCategories.first)
            return try store.post(EntryFactory.income(Self.aed(amount), to: current.info, category: c.info, date: date, memo: memo, key: UUID()))
        }
        let c = try #require(s.expenseCategories.first { $0.name == category })
        return try store.post(EntryFactory.expense(Self.aed(-amount), from: current.info, category: c.info, date: date, memo: memo, key: UUID()))
    }

    @Test func aStatementPointsOutWhatItDoesntShowAndLeavesPendingPaymentsAlone() throws {
        _ = try post("SALARY", 1000, day: 1)
        _ = try post("GROCER SHOP", -100, day: 2)
        let twice = try post("Moved to savings", -20, day: 2)
        _ = try post("TAXI", -10, day: 3)
        // A card payment saved from a message on the statement's last day: the bank hasn't posted it yet
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        let card = try EntryFactory.expense(Self.aed(21.5), from: current.info, category: groceries.info,
                                            date: now.addingTimeInterval(-3600), memo: "Hypermarket", key: UUID())
        let pending = try store.postCaptured(card, source: .sms, cardHint: "0785", needsReview: false)

        let review = StatementReview(accountId: current.id, store: store)
        review.load("Account Number:,5550 1234 640001\nDate,Description,Amount,Balance\n01/11/2026,SALARY,1000.00,1000.00\n02/11/2026,GROCER SHOP,-100.00,900.00\n03/11/2026,TAXI,-10.00,890.00\n",
                    named: "statement.csv")
        #expect(review.error == nil && review.inbox.isEmpty)
        let gaps = try #require(review.gaps)
        #expect(gaps.waiting == [pending] && gaps.missing == [twice])
        // Only the real mistake is left in the difference, not the payment waiting to post
        let check = try #require(review.closingCheck)
        #expect(check.calculated == Self.aed(870) && check.difference == Self.aed(20))
        review.delete(twice)
        #expect(review.closingCheck?.matches == true && review.gaps?.missing.isEmpty == true)
        review.add()
        // The statement's number is saved for the account, with the label and number in separate cells
        #expect(store.account(current.id)?.accountNumber == "55501234640001")
    }

    @Test func matchingTheStatementNeverCorrectsAwayAPendingPayment() throws {
        _ = try post("SALARY", 1000, day: 1)
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        let card = try EntryFactory.expense(Self.aed(21.5), from: current.info, category: groceries.info,
                                            date: now.addingTimeInterval(-3600), memo: "Hypermarket", key: UUID())
        let pending = try store.postCaptured(card, source: .sms, cardHint: "0785", needsReview: false)
        let review = StatementReview(accountId: current.id, store: store)
        // The statement is 5 short of the app: a real difference, besides the pending payment
        review.load("Date,Description,Amount,Balance\n01/11/2026,SALARY,1000.00,1000.00\n03/11/2026,FEE,-5.00,995.00\n", named: "s.csv")
        review.targets = Dictionary(uniqueKeysWithValues: review.inbox.map { ($0.id, .category(groceries.id)) })
        review.add()
        #expect(review.closingCheck?.matches == true)
        // Adding the fee row closed the gap; the pending payment was never corrected away
        #expect(store.snapshot.balance(current.id) == Self.aed(1000 - 5 - 21.5))
        #expect(store.entryRecord(pending)?.cleared != .reconciled)
    }

    @Test func aStatementForAnotherNumberIsPointedOut() throws {
        try store.setAccountNumber(current.id, typed: "55501234640001")
        let review = StatementReview(accountId: current.id, store: store)
        review.load("Account Number:,55501234870001\nDate,Description,Amount,Balance\n01/11/2026,SALARY,1000.00,1000.00\n", named: "s.csv")
        #expect(review.numberMismatch?.contains("••870001") == true && review.numberMismatch?.contains("••640001") == true)
    }
}
