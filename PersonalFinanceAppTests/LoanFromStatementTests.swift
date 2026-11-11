//
//  LoanFromStatementTests.swift
//  Nokael Money
//
//  A statement's loan instalments start a loan in one tap: the payments go to it
//  rather than spending, its monthly bill comes from them, and Home asks once for
//  what's still owed.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct LoanFromStatementTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 11, 2)
    /// Kept for as long as the store uses it
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        bank = try store.addAccount(name: "Current", kind: .bank, balance: Self.aed(20000), openingDate: today)
    }

    private let csv = """
        Date,Description,Amount
        26/09/2026,LOANRECOVERY-EMI:70345126P022001,-5781.00
        26/10/2026,LOANRECOVERY-EMI:70345126P022001,-5781.00
        27/10/2026,ZZ UNKNOWN SHOP,-20.00
        """

    @Test func readsTheLoansReference() {
        #expect(StatementImport.isInstalment("LOANRECOVERY-EMI:70345126P022001"))
        #expect(StatementImport.isInstalment("MORTGAGE INSTALMENT 0042"))
        #expect(!StatementImport.isInstalment("PUR CARREFOUR 4417"))
        #expect(StatementImport.loanReference("LOANRECOVERY-EMI:70345126P022001") == "70345126P022001")
        #expect(StatementImport.loanReference("LoanRecovery-EMI") == nil)
    }

    @Test func anInstalmentStartsALoanToFinishOnHome() throws {
        let review = StatementReview(accountId: bank.id, store: store)
        review.load(csv, named: "october.csv")
        let loanRows = review.inbox.filter { review.loanRows.contains($0.id) }
        #expect(loanRows.count == 2)
        #expect(loanRows.allSatisfy { review.targets[$0.id] == nil && review.prompt(for: $0) == "Which loan?" })

        review.addLoan(for: loanRows[0])
        let loan = try #require(store.snapshot.unfinishedLoans.first)
        #expect(loan.name == "Loan …2001")
        #expect(loanRows.allSatisfy { review.targets[$0.id] == .transfer(loan.id) })
        for row in review.inbox where review.targets[row.id] == nil { review.targets[row.id] = .category(store.loanCategory.id) }
        review.add()

        let s = store.snapshot
        // The payments left the bank but aren't spending, and the loan isn't below nothing owed
        #expect(s.balance(bank.id) == Self.aed(20000 - 11562 - 20))
        #expect(s.balance(loan.id).isZero)
        #expect(s.budget.spent(store.loanCategory.id, month: "2026-10") == Self.aed(20))
        // The latest payment is its bill, next on the 26th
        let item = try #require(s.paymentItem(for: loan.id))
        #expect(item.amount == Self.aed(5781) && item.accountId == bank.id)
        #expect(loan.debtTerms?.dueDay == 26)
        #expect(HomeTask.all(s).contains { $0.id == "finishLoan-\(loan.id)" })

        try store.finishLoan(loan.id, name: "Construction", owed: Self.aed(244561.31), annualRateBps: 750)
        let after = store.snapshot
        #expect(after.owed(loan.id) == Self.aed(244561.31))
        // Both instalments are loan payments now, each with its month's interest out
        let payments = after.entries(touching: loan.id).filter { $0.kind == .debtPayment }
        #expect(payments.count == 2)
        #expect(payments.allSatisfy { $0.entry.amount(on: bank.id) == Self.aed(-5781) && $0.entry.amount(on: loan.id)! < Self.aed(5781) })
        #expect(after.unfinishedLoans.isEmpty)
        #expect(after.account(loan.id)?.name == "Construction")
        #expect(after.account(loan.id)?.debtTerms?.annualRateBps == 750)
        #expect(after.paymentItem(for: loan.id)?.accountId == bank.id)
        #expect(after.paymentItem(for: loan.id)?.name == "Construction payment")
        #expect(!HomeTask.all(after).contains { if case .finishLoan = $0 { true } else { false } })
    }

    @Test func owedEnteredAnotherWayFinishesTheLoan() throws {
        let loan = try store.addUnfinishedLoan(name: "Loan …2001", openingDate: LedgerStoreTests.date(2026, 10, 26))
        try store.post(EntryFactory.transfer(Self.aed(5781), from: bank.info, to: loan.info, date: LedgerStoreTests.date(2026, 10, 26)))
        try store.startLoan(loan.id, payments: [(LedgerStoreTests.date(2026, 10, 26), Self.aed(5781))], paidFrom: bank.id)
        #expect(store.snapshot.unfinishedLoans.count == 1)
        // Rate and payment's "Owed when added"
        try store.correctOpeningBalance(loan.id, to: Self.aed(248787.39).negated)
        #expect(store.snapshot.unfinishedLoans.isEmpty)
        #expect(store.settings.unfinishedLoans.isEmpty)
        #expect(!HomeTask.all(store.snapshot).contains { $0.id == "finishLoan-\(loan.id)" })

        // Then the rate: the payment made before is split, a month's interest at 7.5% out of it
        let terms = try #require(store.account(loan.id)?.debtTerms)
        try store.saveDebtTerms(DebtTerms(annualRateBps: 750, monthlyPayment: terms.monthlyPayment, dueDay: terms.dueDay),
                                for: loan.id, paidFrom: bank.id)
        let s = store.snapshot
        #expect(s.owed(loan.id) == Self.aed(244561.31))
        let payment = try #require(s.entries(touching: loan.id).first { $0.kind == .debtPayment })
        #expect(payment.entry.amount(on: loan.id) == Self.aed(4226.08))
        // Done once: saving again changes nothing
        try store.tidyLoanPayments()
        #expect(store.snapshot.owed(loan.id) == Self.aed(244561.31))
    }

    @Test func anExistingLoanStillTakesItsInstalments() throws {
        let loan = try store.addAccount(name: "Construction", kind: .loan, balance: Self.aed(250000), openingDate: today)
        let review = StatementReview(accountId: bank.id, store: store)
        review.load(csv, named: "october.csv")
        #expect(review.loanRows.isEmpty)
        #expect(review.inbox.filter { review.targets[$0.id] == .transfer(loan.id) }.count == 2)
    }

    @Test func homesLoanFindingCanStartTheLoan() throws {
        let finding = StatementFinding(kind: .loan, name: "Loan", amount: Self.aed(5781), nextDate: LedgerStoreTests.date(2026, 11, 26))
        try store.saveFindings([finding])
        try store.acceptFindingAsLoan(finding, accountId: bank.id)
        let s = store.snapshot
        let loan = try #require(s.unfinishedLoans.first)
        #expect(s.statementFindings.isEmpty)
        #expect(s.paymentItem(for: loan.id)?.amount == Self.aed(5781))
        #expect(s.items.filter { $0.direction == .outflow }.count == 1)
    }
}
