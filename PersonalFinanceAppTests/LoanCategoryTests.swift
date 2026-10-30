//
//  LoanCategoryTests.swift
//  Nokael Money
//
//  Several loans can share one budget category, payments count in full in
//  Budget and Reports, and a category shows what went into it.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct LoanCategoryTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 10, 26)
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let car: LedgerAccountRecord
    let personal: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.createAccount(name: "Current", kind: .bank, opening: Self.aed(20000), openingDate: today)
        car = try store.createAccount(name: "Car loan", kind: .loan, opening: Self.aed(-36000), openingDate: today)
        personal = try store.createAccount(name: "Personal loan", kind: .loan, opening: Self.aed(-12000), openingDate: today)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 500, monthlyPayment: Self.aed(1850), dueDay: 28), for: car.id, paidFrom: bank.id)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 650, monthlyPayment: Self.aed(900), dueDay: 28), for: personal.id, paidFrom: bank.id)
    }

    private var month: String { store.snapshot.monthKey }

    private func pay(_ loan: LedgerAccountRecord, _ amount: Decimal, interest: Decimal) throws {
        try store.payDebt(loan.id, from: bank.id, amount: Self.aed(amount), interest: Self.aed(interest), fees: Self.aed(0),
                          date: today, key: UUID())
    }

    @Test func twoLoansShareOneCategory() throws {
        let loans = try store.createCategory(name: "Loans", kind: .expense, group: "Bills")
        try store.setLoanCategory(loans.id, for: car.id)
        try store.setLoanCategory(loans.id, for: personal.id)
        var s = store.snapshot
        #expect(Set(s.loans(in: loans.id).map(\.id)) == [car.id, personal.id])
        // Both instalments are planned there
        #expect(s.budget.line(loans.id, month: month).planned == Self.aed(2750))

        try pay(personal, 900, interest: 65)
        s = store.snapshot
        #expect(s.budget.spent(loans.id, month: month) == Self.aed(900))
        #expect(s.owed(personal.id) == Self.aed(12000 - 835))
        #expect(s.owed(car.id) == Self.aed(36000))
        #expect(s.budget.spent(store.loanCategory.id, month: month).isZero)
    }

    @Test func aLoanWithNoCategoryStaysInLoanPayments() throws {
        try pay(car, 1850, interest: 150)
        let s = store.snapshot
        #expect(s.loanCategories[car.id] == store.loanCategory.id)
        #expect(s.budget.spent(store.loanCategory.id, month: month) == Self.aed(1850))
    }

    @Test func movingALoanTakesItsPaymentsAlong() throws {
        try pay(car, 1850, interest: 150)
        let loans = try store.createCategory(name: "Loans", kind: .expense, group: "Bills")
        try store.setLoanCategory(loans.id, for: car.id)
        let s = store.snapshot
        #expect(s.budget.spent(loans.id, month: month) == Self.aed(1850))
        #expect(s.budget.spent(store.loanCategory.id, month: month).isZero)
        #expect(s.owed(car.id) == Self.aed(36000 - 1700))

        // And back again
        try store.setLoanCategory(nil, for: car.id)
        #expect(store.snapshot.budget.spent(store.loanCategory.id, month: month) == Self.aed(1850))
    }

    @Test func renamingLoanPaymentsDoesNotMakeAnother() throws {
        let original = store.loanCategory
        original.name = "Instalments"
        let again = store.loanCategory
        #expect(again.id == original.id)
        #expect(store.snapshot.expenseCategories.filter { $0.name == "Loan payments" }.isEmpty)
    }

    @Test func aPaymentWithNoInterestStillCounts() throws {
        try pay(personal, 900, interest: 0)
        let s = store.snapshot
        #expect(s.budget.spent(store.loanCategory.id, month: month) == Self.aed(900))
        let report = Reports.month(month, ledger: s.ledger, expenseCategories: s.expenseCategories.map(\.info),
                                   incomeCategories: [], calendar: s.calendar, loanCategories: s.loanCategories)
        #expect(report.totals.spending == Self.aed(900))
    }

    @Test func reportsCountTheWholeLoanPayment() throws {
        try pay(car, 1850, interest: 150)
        try pay(personal, 900, interest: 65)
        let s = store.snapshot
        let report = Reports.month(month, ledger: s.ledger, expenseCategories: s.expenseCategories.map(\.info),
                                   incomeCategories: [], calendar: s.calendar, loanCategories: s.loanCategories)
        #expect(report.totals.spending == Self.aed(2750))
        #expect(report.spending.first { $0.categoryId == store.loanCategory.id }?.amount == Self.aed(2750))
    }

    @Test func breakdownShowsEachLoanAndEachShop() throws {
        try pay(personal, 900, interest: 65)
        let s0 = store.snapshot
        let parts = s0.breakdown(store.loanCategory.id, month: month)
        #expect(parts.map(\.name) == ["Personal loan", "Car loan"])
        #expect(parts[0].amount == Self.aed(900))
        #expect(parts[0].detail == "\(Self.aed(65).compact) interest")
        #expect(parts[1].amount.isZero)
        #expect(parts[1].detail?.hasPrefix("Due ") == true)

        let groceries = try #require(s0.expenseCategories.first { $0.name == "Groceries" })
        for (amount, shop) in [(260, "Carrefour"), (178.5, "Spinneys"), (40, "carrefour")] as [(Decimal, String)] {
            try store.post(try EntryFactory.expense(Self.aed(amount), from: bank.info, category: groceries.info, date: today, memo: shop))
        }
        let shops = store.snapshot.breakdown(groceries.id, month: month)
        #expect(shops.map(\.name) == ["Carrefour", "Spinneys"])
        #expect(shops[0].amount == Self.aed(300) && shops[0].detail == "2 times")
    }

    @Test func backupKeepsEachLoansCategory() throws {
        // Records are replaced by a restore, so keep the ids
        let loansId = try store.createCategory(name: "Loans", kind: .expense, group: "Bills").id
        let carId = car.id
        try store.setLoanCategory(loansId, for: carId)
        let backup = try LedgerStore.readBackup(try store.backupData())
        try store.setLoanCategory(nil, for: carId)
        try store.restore(backup)
        #expect(store.snapshot.loanCategories[carId] == loansId)
    }
}
