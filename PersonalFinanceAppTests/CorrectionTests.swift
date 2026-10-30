//
//  CorrectionTests.swift
//  Nokael Money
//
//  Fixing a mistake: the amount a loan or account was added with, and the
//  amount, account or date of a payment already recorded.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct CorrectionTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 10, 26)
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let car: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(20000), openingDate: today)
        car = try store.createAccount(name: "Car loan", kind: .loan, opening: Self.aed(-36000), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(1850), dueDay: 28), for: car.id, paidFrom: bank.id)
    }

    @discardableResult
    private func payCar(_ amount: Decimal, interest: Decimal) throws -> UUID {
        try store.payDebt(car.id, from: bank.id, amount: Self.aed(amount), interest: Self.aed(interest), fees: Self.aed(0),
                          date: today, key: UUID())
    }

    @Test func fixingWhatALoanStartedAt() throws {
        try payCar(1850, interest: 150)
        #expect(store.snapshot.owed(car.id) == Self.aed(34300))

        // Typed 36,000; it was really 63,000
        try store.correctOpeningBalance(car.id, to: Self.aed(-63000))
        let s = store.snapshot
        #expect(s.owed(car.id) == Self.aed(61300))
        #expect(s.balance(bank.id) == Self.aed(20000 - 1850))
        // The payment and its budget are untouched
        #expect(s.budget.spent(store.loanCategory.id, month: s.monthKey) == Self.aed(1850))
        // The original stays in the history, replaced
        let opening = try #require(store.openingEntry(for: car.id))
        #expect(opening.entry.amount(on: car.id) == Self.aed(-63000))
        #expect(opening.replacesId != nil)
    }

    @Test func aLoanCantStartBelowWhatsBeenPaidOffIt() throws {
        try payCar(1850, interest: 150)
        #expect(throws: StoreError.self) { try store.correctOpeningBalance(car.id, to: Self.aed(-1000)) }
        #expect(store.snapshot.owed(car.id) == Self.aed(34300))
    }

    @Test func aBankAccountsStartingBalanceToo() throws {
        try store.correctOpeningBalance(bank.id, to: Self.aed(25000))
        #expect(store.snapshot.balance(bank.id) == Self.aed(25000))
        try store.correctOpeningBalance(bank.id, to: Self.aed(0))
        #expect(store.snapshot.balance(bank.id).isZero)
        #expect(store.openingEntry(for: bank.id) == nil)
    }

    @Test func editingAPaymentsAmount() throws {
        let id = try payCar(1850, interest: 150)
        try store.editDebtPayment(id, from: bank.id, amount: Self.aed(1900), interest: Self.aed(150), fees: Self.aed(0), date: today)
        let s = store.snapshot
        #expect(s.owed(car.id) == Self.aed(36000 - 1750))
        #expect(s.balance(bank.id) == Self.aed(20000 - 1900))
        #expect(s.entryRecords.filter { $0.kind == .debtPayment && $0.status == .posted }.count == 1)
        #expect(s.budget.spent(store.loanCategory.id, month: s.monthKey) == Self.aed(1900))
    }

    @Test func editingAPaymentsAccountAndDate() throws {
        let card = try store.createAccount(name: "Savings", kind: .savings, opening: Self.aed(5000), openingDate: today)
        let id = try payCar(1850, interest: 150)
        let earlier = LedgerStoreTests.date(2026, 10, 20)
        let newId = try store.editDebtPayment(id, from: card.id, amount: Self.aed(1850), interest: Self.aed(150),
                                              fees: Self.aed(0), date: earlier)
        let s = store.snapshot
        #expect(s.balance(bank.id) == Self.aed(20000))
        #expect(s.balance(card.id) == Self.aed(5000 - 1850))
        #expect(store.entryRecord(newId)?.date == earlier)
    }

    @Test func aPaymentCantBeEditedToMoreThanWasOwed() throws {
        let id = try payCar(1850, interest: 150)
        #expect(throws: StoreError.self) {
            try store.editDebtPayment(id, from: bank.id, amount: Self.aed(40000), interest: Self.aed(0), fees: Self.aed(0), date: today)
        }
        // Paying off exactly what was owed before it is fine
        try store.editDebtPayment(id, from: bank.id, amount: Self.aed(36000), interest: Self.aed(0), fees: Self.aed(0), date: today)
        #expect(store.snapshot.owed(car.id).isZero)
    }
}
