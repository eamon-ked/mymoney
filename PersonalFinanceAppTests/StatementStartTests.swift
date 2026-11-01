//
//  StatementStartTests.swift
//  Nokael Money
//
//  A statement as the starting point: its rows aren't counted on top of a
//  balance typed later, money with people stays out of spending, and what it
//  shows about pay and bills waits on Home to be confirmed.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct StatementStartTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 11, 2)
    /// Kept for as long as the store uses it
    let container: ModelContainer
    let store: LedgerStore

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.kind.isCategory && $0.name == name }!
    }

    /// Statement rows from 20 Oct to 1 Nov that add up to +173.96
    private func importRows(into id: UUID) throws {
        let rows: [(Int, Int, String, Decimal, String)] = [
            (10, 20, "B/O ACME LOGISTICS", 356, "Other income"),
            (10, 26, "SALARY", 12000, "Salary"),
            (10, 27, "PUR CARREFOUR", -12182.04, "Groceries")
        ]
        let picks = rows.map { m, d, memo, amount, cat in
            LedgerStore.ImportedRow(date: LedgerStoreTests.date(2026, m, d), memo: memo, amount: Self.aed(amount),
                                    target: .category(category(cat).id), key: UUID())
        }
        _ = try store.importRows(picks, into: id)
    }

    @Test func statementOpeningReplacesABalanceTypedLater() throws {
        let bank = try store.addAccount(name: "Main account", kind: .bank, balance: Self.aed(300), openingDate: today)
        try importRows(into: bank.id)
        #expect(store.snapshot.balance(bank.id) == Self.aed(473.96), "Counted twice before the fix")

        let changed = try store.anchorOpening(bank.id, statementOpening: Self.aed(2.23), firstDay: LedgerStoreTests.date(2026, 10, 20))
        #expect(changed)
        #expect(store.snapshot.balance(bank.id) == Self.aed(176.19))
        // Already anchored: nothing more to do
        #expect(try !store.anchorOpening(bank.id, statementOpening: Self.aed(2.23), firstDay: LedgerStoreTests.date(2026, 10, 20)))
    }

    @Test func withoutAStatementOpeningTheTypedBalanceStands() throws {
        let bank = try store.addAccount(name: "Main account", kind: .bank, balance: Self.aed(300), openingDate: today)
        try importRows(into: bank.id)
        try store.anchorOpening(bank.id, statementOpening: nil, firstDay: LedgerStoreTests.date(2026, 10, 20))
        #expect(store.snapshot.balance(bank.id) == Self.aed(300))
        let opening = try #require(store.openingEntry(for: bank.id))
        #expect(opening.date <= LedgerStoreTests.date(2026, 10, 20))
    }

    @Test func anAccountAddedAtNothingStartsFromTheStatement() throws {
        let bank = try store.addAccount(name: "Main account", kind: .bank, balance: .zero("AED"), openingDate: today)
        try importRows(into: bank.id)
        try store.anchorOpening(bank.id, statementOpening: Self.aed(2.23), firstDay: LedgerStoreTests.date(2026, 10, 20))
        #expect(store.snapshot.balance(bank.id) == Self.aed(176.19))
    }

    @Test func moneyWithPeopleIsLeftOutOfTotals() throws {
        let sent = store.peopleCategory
        let received = store.fromPeopleCategory
        #expect(sent.isTransferCategory && received.isTransferCategory && received.kind == .income)
        let s = store.snapshot
        #expect(!s.spendingCategoryInfos.contains { $0.id == sent.id })
        #expect(!s.earningCategoryInfos.contains { $0.id == received.id })
        #expect(s.spendingCategoryInfos.contains { $0.id == category("Groceries").id })
        #expect(s.peopleCategoryInfos.sent.contains { $0.id == sent.id })
    }

    @Test func statementFindingsWaitOnHome() throws {
        let bank = try store.addAccount(name: "Main account", kind: .bank, balance: Self.aed(1000), openingDate: today)
        let pay = StatementFinding(kind: .pay, name: "Salary", amount: Self.aed(12000), nextDate: LedgerStoreTests.date(2026, 11, 26))
        let loan = StatementFinding(kind: .loan, name: "Loan", amount: Self.aed(5781), nextDate: LedgerStoreTests.date(2026, 11, 26))
        try store.saveFindings([pay, loan])
        #expect(store.snapshot.statementFindings.count == 2)
        #expect(HomeTask.all(store.snapshot).contains { $0.id == "finding-\(pay.id)" })
        // With pay found, Home doesn't also ask for a payday
        #expect(!HomeTask.all(store.snapshot).contains { $0.id == "setUp-payday" })

        try store.acceptFinding(pay, accountId: bank.id)
        #expect(store.snapshot.nextIncomeDate != nil)
        try store.dismissFinding(loan)
        #expect(store.snapshot.statementFindings.isEmpty)
        // A later import of the same statement doesn't ask again
        try store.saveFindings([loan])
        #expect(store.snapshot.statementFindings.isEmpty)
    }

    @Test func homeAsksForPaydayAndBillsUntilThere() throws {
        _ = try store.addAccount(name: "Main account", kind: .bank, balance: Self.aed(1000), openingDate: today)
        let ids = HomeTask.all(store.snapshot).map(\.id)
        #expect(ids.contains("setUp-payday") && ids.contains("setUp-bills"))
        try store.updateSettings { $0.dismissedFindings.append("setUp-payday") }
        #expect(!HomeTask.all(store.snapshot).map(\.id).contains("setUp-payday"))
    }
}
