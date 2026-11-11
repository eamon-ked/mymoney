//
//  MatchingAndPeriodTests.swift
//  Nokael Money
//
//  Recording a bank alert as a move between your own accounts never removes an unrelated deposit;
//  a skipped payday doesn't end the Safe to Spend period; a category's bill that falls after the
//  chosen period stays held back. In euros, so nothing here leans on one country's setup.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct MatchingAndPeriodTests {
    static func eur(_ v: Decimal) -> Money { Money(v, currency: "EUR") }
    let today = LedgerStoreTests.date(2026, 11, 8)
    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord
    let savings: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.updateSettings { $0.currency = "EUR"; $0.localeIdentifier = "fr_FR"; $0.onboardingDone = true }
        try store.addStarterCategories()
        current = try store.createAccount(name: "Compte courant", kind: .bank, opening: Self.eur(2000), openingDate: today.addingTimeInterval(-86400 * 5))
        savings = try store.createAccount(name: "Livret", kind: .savings, opening: Self.eur(500), openingDate: today.addingTimeInterval(-86400 * 5))
    }

    private var salary: LedgerAccountRecord { store.snapshot.incomeCategories.first { $0.name == "Salary" }! }

    /// Money out from the current account, saved from an alert as money sent to someone
    private func sentAlert(_ amount: Decimal) throws -> UUID {
        try store.postCaptured(EntryFactory.expense(Self.eur(amount), from: current.info, category: store.peopleCategory.info,
                                                    date: today, memo: "Virement emis"),
                               source: .sms, cardHint: nil, needsReview: true, reference: nil, reviewReason: nil)
    }

    // MARK: - Recording a move between your own accounts

    @Test func payOfTheSameAmountIsNeverTakenForTheOtherHalf() throws {
        let pay = try store.post(EntryFactory.income(Self.eur(100), to: savings.info, category: salary.info, date: today, memo: "Salaire"))
        let out = try sentAlert(100)
        try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(pay)?.status == .posted)
        #expect(store.snapshot.balance(savings.id) == Self.eur(700))
        #expect(store.snapshot.balance(current.id) == Self.eur(1900))
    }

    @Test func aDepositYouEnteredYourselfIsKept() throws {
        let gift = try store.post(EntryFactory.income(Self.eur(100), to: savings.info, category: store.fromPeopleCategory.info,
                                                      date: today, memo: "From Mum"))
        let out = try sentAlert(100)
        try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(gift)?.status == .posted)
        #expect(store.snapshot.balance(savings.id) == Self.eur(700))
    }

    @Test func anAlertThePersonAlreadyCheckedIsKept() throws {
        let checked = try store.postCaptured(EntryFactory.income(Self.eur(100), to: savings.info, category: store.fromPeopleCategory.info,
                                                                 date: today, memo: "Virement recu"),
                                             source: .sms, cardHint: nil, needsReview: false, reference: nil, reviewReason: nil)
        let out = try sentAlert(100)
        try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(checked)?.status == .posted)
    }

    @Test func theOtherBanksUncheckedAlertIsStillFoldedIn() throws {
        let arrived = try store.postCaptured(EntryFactory.income(Self.eur(100), to: savings.info, category: store.fromPeopleCategory.info,
                                                                 date: today, memo: "Virement recu"),
                                             source: .sms, cardHint: nil, needsReview: true, reference: nil, reviewReason: nil)
        let out = try sentAlert(100)
        let id = try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(arrived)?.status == .void)
        #expect(store.entryRecord(id)?.kind == .transfer)
        #expect(store.snapshot.balance(savings.id) == Self.eur(600))
    }

    @Test func twoLookalikesWithoutAReferenceAreBothKept() throws {
        func arrival() throws -> UUID {
            try store.postCaptured(EntryFactory.income(Self.eur(100), to: savings.info, category: store.fromPeopleCategory.info,
                                                       date: today, memo: "Virement recu"),
                                   source: .sms, cardHint: nil, needsReview: true, reference: nil, reviewReason: nil)
        }
        let a = try arrival(), b = try arrival()
        let out = try sentAlert(100)
        #expect(store.transferTwin(of: try #require(store.entryRecord(out)), in: savings.id) == nil)
        try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(a)?.status == .posted && store.entryRecord(b)?.status == .posted)
    }

    @Test func aSharedReferenceStillFindsTheOtherHalf() throws {
        let arrived = try store.post(EntryFactory.income(Self.eur(100), to: savings.info, category: store.fromPeopleCategory.info,
                                                         date: today, memo: "VIR 88412093 RECU"))
        let out = try store.post(EntryFactory.expense(Self.eur(100), from: current.info, category: store.peopleCategory.info,
                                                      date: today, memo: "VIR 88412093 EMIS"))
        try store.recordAsTransfer(out, other: savings.id)
        #expect(store.entryRecord(arrived)?.status == .void)
        #expect(store.snapshot.balance(savings.id) == Self.eur(600))
    }

    // MARK: - Skipped paydays

    @Test func aSkippedPaydayDoesNotEndTheSafeToSpendPeriod() throws {
        let payday = LedgerStoreTests.date(2026, 11, 12)
        try store.setUpSalary(Self.eur(3000), every: .monthly(every: 1), nextPayday: payday)
        let skipped = try #require(store.snapshot.occurrences.first { store.snapshot.calendar.isDate($0.dueDate, inSameDayAs: payday) })
        try store.skip(occurrenceId: skipped.id)
        let s = store.snapshot
        let next = try #require(s.nextIncomeDate)
        #expect(s.calendar.component(.month, from: next) == 12)
        #expect(s.defaultPeriodEnd > payday)
        #expect(PaydayPlan.make(s).nextPayday.map { s.calendar.component(.month, from: $0) } != 11)
    }

    // MARK: - A category's bills and the chosen period

    @Test func aBillAfterTheChosenPeriodStaysHeldInItsCategory() throws {
        let groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
        try store.updateAccount(groceries) { $0.reserveInSafeToSpend = true }
        try store.setAllocation(Self.eur(500), categoryId: groceries.id, month: store.snapshot.monthKey)
        let box = PlannedItem(name: "Panier bio", direction: .outflow, amount: Self.eur(200),
                              schedule: Schedule(start: LedgerStoreTests.date(2026, 11, 25), frequency: .monthly(every: 1)),
                              accountId: current.id, categoryId: groceries.id)
        try store.savePlannedItem(box)
        let s = store.snapshot
        let week = s.safeToSpend(through: s.endOfDay(LedgerStoreTests.date(2026, 11, 15)))
        let month = s.safeToSpend(through: s.endOfDay(LedgerStoreTests.date(2026, 11, 30)))
        // Within the week the bill isn't due, so the category keeps its money
        #expect(week.obligationsTotal.isZero)
        #expect(week.categoryReservationsTotal == Self.eur(500))
        // Through the month it's held back once, as a bill
        #expect(month.obligationsTotal == Self.eur(200))
        #expect(month.categoryReservationsTotal == Self.eur(300))
        #expect(week.amount == month.amount)
    }
}
