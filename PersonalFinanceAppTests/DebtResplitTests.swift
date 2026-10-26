//
//  DebtResplitTests.swift
//  Nokael Money
//
//  A loan payment recorded with estimated interest can take the bank's figures.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct DebtResplitTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    @Test func bankInterestReplacesTheEstimate() throws {
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = LedgerStoreTests.date(2026, 10, 26)
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Checking", kind: .bank, opening: Self.aed(10000), openingDate: today)
        let loan = try store.createAccount(name: "Construction loan", kind: .loan, opening: Self.aed(-373000), openingDate: today)

        let id = try store.payDebt(loan.id, from: bank.id, amount: Self.aed(5781), interest: Self.aed(1554.92), fees: Self.aed(0),
                                   date: today, key: UUID())
        let record = try #require(store.snapshot.entryRecords.first { $0.id == id })
        let parts = try #require(store.debtPaymentParts(record))
        #expect(parts.total == Self.aed(5781) && parts.principal == Self.aed(4226.08) && parts.interest == Self.aed(1554.92))

        let newId = try store.resplitDebtPayment(id, interest: Self.aed(1400), fees: Self.aed(25))
        #expect(store.snapshot.owed(loan.id) == Self.aed(373000 - 4356))
        #expect(store.snapshot.balance(bank.id) == Self.aed(10000 - 5781))
        let fresh = try #require(store.snapshot.entryRecords.first { $0.id == newId })
        let after = try #require(store.debtPaymentParts(fresh))
        #expect(after.interest == Self.aed(1400) && after.fees == Self.aed(25) && after.principal == Self.aed(4356))
    }

    @Test func importedInstalmentIsSplitNotMovedWhole() throws {
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = LedgerStoreTests.date(2026, 10, 26)
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Checking", kind: .bank, opening: Self.aed(12089.73), openingDate: today)
        let loan = try store.createAccount(name: "Construction loan", kind: .loan, opening: Self.aed(-373000), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(5781), dueDay: nil), for: loan.id, paidFrom: nil)

        let memo = "LOANRECOVERY-EMI:11392149P022001"
        #expect(StatementImport.loan(for: memo, loans: [(loan.id, loan.name)]) == loan.id)
        _ = try store.importRows([.init(date: today, memo: memo, amount: Self.aed(-5781), target: .transfer(loan.id), key: UUID())],
                                 into: bank.id)

        #expect(store.snapshot.balance(bank.id) == Self.aed(6308.73))
        let interest = DebtCalculator.monthlyInterest(owed: Self.aed(373000), annualRateBps: 500)
        #expect(interest == Self.aed(1554.17))
        #expect(store.snapshot.owed(loan.id) == Self.aed(373000) - (Self.aed(5781) - interest))
    }

    @Test func deletedImportedRowCanBeImportedAgain() throws {
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = LedgerStoreTests.date(2026, 10, 26)
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Checking", kind: .bank, opening: Self.aed(12089.73), openingDate: today)
        let loan = try store.createAccount(name: "Construction loan", kind: .loan, opening: Self.aed(-248787.39), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 750, monthlyPayment: Self.aed(5781), dueDay: nil), for: loan.id, paidFrom: nil)
        let row = LedgerStore.ImportedRow(date: today, memo: "LOANRECOVERY-EMI:11392149P022001", amount: Self.aed(-5781),
                                          target: .transfer(loan.id), key: UUID())

        #expect(try store.importRows([row], into: bank.id) == 1)
        #expect(try store.importRows([row], into: bank.id) == 0)
        let first = try #require(store.snapshot.entries().first { $0.kind == .debtPayment })
        let parts = try #require(store.debtPaymentParts(first))
        #expect(parts.interest == Self.aed(1554.92) && parts.principal == Self.aed(4226.08))

        try store.void(first.id)
        #expect(store.snapshot.balance(bank.id) == Self.aed(12089.73))
        #expect(try store.importRows([row], into: bank.id) == 1)
        #expect(store.snapshot.balance(bank.id) == Self.aed(6308.73))
        #expect(store.snapshot.owed(loan.id) == Self.aed(248787.39 - 4226.08))
    }

    @Test func paidInstalmentLeavesNothingInItsBudget() throws {
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = LedgerStoreTests.date(2026, 10, 20)
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Checking", kind: .bank, opening: Self.aed(12089.73), openingDate: today)
        let loan = try store.createAccount(name: "Construction loan", kind: .loan, opening: Self.aed(-248787.39), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 750, monthlyPayment: Self.aed(5781), dueDay: 26), for: loan.id, paidFrom: bank.id)
        let interest = store.interestCategory
        let month = store.snapshot.monthKey
        try store.setAllocation(Self.aed(5781), categoryId: interest.id, month: month)

        // Before paying: the bill holds the 5,781 back once, not again for the budget
        let before = store.snapshot.safeToSpend()
        #expect(before.obligations.map(\.amount).sum("AED") == Self.aed(5781))
        #expect(before.categoryReservations.allSatisfy { $0.sourceIds != [interest.id] })

        let occ = try #require(store.snapshot.upcomingBills(days: 45).first)
        try store.pay(occurrenceId: occ.id, amount: Self.aed(5781), accountId: bank.id, categoryId: nil,
                      date: LedgerStoreTests.date(2026, 10, 26), key: UUID())

        let line = store.snapshot.budget.line(interest.id, month: month)
        #expect(line.spent == Self.aed(5781))
        #expect(line.remaining == Self.aed(0))
        #expect(store.snapshot.owed(loan.id) == Self.aed(248787.39 - 4226.08))
    }

    @Test func unplannedInstalmentIsPlannedWhenPaidNotOverspent() throws {
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = LedgerStoreTests.date(2026, 10, 20)
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        let bank = try store.createAccount(name: "Checking", kind: .bank, opening: Self.aed(12089.73), openingDate: today)
        let loan = try store.createAccount(name: "Construction loan", kind: .loan, opening: Self.aed(-248787.39), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 750, monthlyPayment: Self.aed(5781), dueDay: 26), for: loan.id, paidFrom: nil)
        let row = LedgerStore.ImportedRow(date: LedgerStoreTests.date(2026, 10, 26), memo: "LOAN INSTALMENT", amount: Self.aed(-5781),
                                          target: .transfer(loan.id), key: UUID())
        _ = try store.importRows([row], into: bank.id)

        let interest = store.interestCategory
        let line = store.snapshot.budget.line(interest.id, month: store.snapshot.monthKey)
        #expect(line.allocated == Self.aed(5781))
        #expect(line.spent == Self.aed(5781))
        #expect(line.remaining == Self.aed(0))
    }
}
