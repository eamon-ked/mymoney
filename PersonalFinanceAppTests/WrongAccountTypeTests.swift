//
//  WrongAccountTypeTests.swift
//  Nokael Money
//
//  A loan saved as a bank account, with a bank statement imported into it:
//  what's owed showed as money to spend. Changing the type and moving the
//  statement back puts both right, and an EMI filed as spending becomes a
//  loan payment.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct WrongAccountTypeTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 10, 30)
    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord
    let loan: LedgerAccountRecord
    let emiId: UUID

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        current = try store.createAccount(name: "Current account", kind: .bank, opening: Self.aed(0), openingDate: today)
        // The mistake: "Construction loan" added with the bank account form, 248,787.39 as money held
        loan = try store.createAccount(name: "Construction loan", kind: .bank, opening: Self.aed(248_787.39), openingDate: today)
        let categories = store.snapshot.expenseCategories
        let salary = try #require(store.snapshot.incomeCategories.first { $0.name == "Salary" })
        let transport = try #require(categories.first { $0.name == "Transport" })
        let fees = store.interestCategory
        // Then the current account's statement imported into it
        let day = LedgerStoreTests.date(2026, 10, 24)
        try store.post(EntryFactory.income(Self.aed(12000), to: loan.info, category: salary.info, date: day, memo: "SALARY"))
        try store.post(EntryFactory.expense(Self.aed(2500), from: loan.info, category: transport.info, date: day, memo: "TRF OUT"))
        emiId = try store.post(EntryFactory.expense(Self.aed(5781), from: loan.info, category: fees.info, date: day,
                                                    memo: "LOANRECOVERY-EMI"))
    }

    @Test func theMistakeCountsTheLoanAsMoney() {
        // What the phone showed: the loan's 248,787 added to safe-to-spend
        let s = store.snapshot
        #expect(s.balance(loan.id) == Self.aed(248_787.39 + 12000 - 2500 - 5781))
        #expect(s.safeToSpend().spendableTotal.isPositive)
    }

    @Test func changingTheTypeMakesItOwedAndMovesTheStatement() throws {
        try store.changeAccountType(loan.id, to: .loan, movingEntriesTo: current.id)
        let s = store.snapshot
        let fixed = try #require(s.account(loan.id))
        #expect(fixed.kind == .loan)
        #expect(!fixed.spendable)
        #expect(!fixed.onBudget)
        #expect(s.owed(loan.id) == Self.aed(248_787.39))
        // The statement belongs to the current account
        #expect(s.balance(current.id) == Self.aed(12000 - 2500 - 5781))
        #expect(s.safeToSpend().spendableTotal == Self.aed(12000 - 2500 - 5781))
        // Nothing lost: the originals are replaced, not deleted
        #expect(store.movableEntries(of: loan.id, to: nil).isEmpty)
        #expect(s.entries(touching: current.id).filter { $0.replacesId != nil }.count == 3)
        #expect(store.settings.lastUsedAccountId != loan.id)
    }

    @Test func theEMIBecomesALoanPayment() throws {
        try store.changeAccountType(loan.id, to: .loan, movingEntriesTo: current.id)
        let movedEMI = try #require(store.snapshot.entries(touching: current.id).first { $0.memo == "LOANRECOVERY-EMI" })
        try store.recordAsDebtPayment(movedEMI.id, debt: loan.id, from: current.id, amount: Self.aed(5781),
                                      interest: Self.aed(1200), fees: Self.aed(0), date: movedEMI.date)
        let s = store.snapshot
        #expect(s.owed(loan.id) == Self.aed(248_787.39 - 4581))
        #expect(s.balance(current.id) == Self.aed(12000 - 2500 - 5781))
        #expect(store.entryRecord(movedEMI.id)?.status == .void)
        let payment = try #require(s.entries(touching: loan.id).first { $0.kind == .debtPayment })
        #expect(store.debtPaymentParts(payment)?.interest == Self.aed(1200))
    }

    @Test func keepingTheEntriesStillFlipsTheBalance() throws {
        try store.changeAccountType(loan.id, to: .loan)
        // Added with 248,787.39 owed; the statement rows stay on it
        #expect(store.snapshot.owed(loan.id) == Self.aed(248_787.39 - 12000 + 2500 + 5781))
    }

    @Test func refusesToShowNothingOwed() throws {
        let small = try store.createAccount(name: "Small", kind: .bank, opening: Self.aed(100), openingDate: today)
        let salary = try #require(store.snapshot.incomeCategories.first { $0.name == "Salary" })
        try store.post(EntryFactory.income(Self.aed(5000), to: small.info, category: salary.info, date: today))
        #expect(throws: StoreError.self) { try store.changeAccountType(small.id, to: .loan) }
        #expect(store.snapshot.account(small.id)?.kind == .bank)
    }

    @Test func aBankAccountTypeChangeKeepsTheBalance() throws {
        try store.changeAccountType(current.id, to: .savings)
        #expect(store.snapshot.account(current.id)?.kind == .savings)
        #expect(store.snapshot.balance(current.id).isZero)
    }
}
