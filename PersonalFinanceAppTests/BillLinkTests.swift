//
//  BillLinkTests.swift
//  Nokael Money
//
//  One bill, one payment: a payment recorded anywhere can settle its bill once,
//  by asking, and unlinking or deleting it puts everything back.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct BillLinkTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

    let container: ModelContainer
    let store: LedgerStore
    let checking: LedgerAccountRecord
    let today = LedgerStoreTests.date(2026, 10, 27)

    /// Today's real situation: rent of 2,500 due today, a 500 buffer, and 2,896.67 left in Checking once rent is spent
    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today.addingTimeInterval(4 * 3600)
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        checking = try store.createAccount(name: "Checking account", kind: .bank, opening: Self.aed(5396.67), openingDate: today)
        try store.updateSettings { $0.onboardingDone = true; $0.bufferMinor = 50000 }
        try store.savePlannedItem(PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(2500),
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: checking.id, categoryId: category("Rent or mortgage").id))
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.name == name }!
    }

    private var totalSpent: Money {
        let s = store.snapshot
        return s.expenseCategories.map { s.budget.spent($0.id, month: s.monthKey) }.sum("AED")
    }

    private var rentBill: Occurrence {
        store.snapshot.occurrences.first { store.snapshot.item(for: $0)?.name == "Rent" && $0.dueDate <= today.addingTimeInterval(86400) }!
    }

    @discardableResult
    private func spend(_ amount: Decimal, on name: String = "Rent or mortgage", memo: String = "Rent or mortgage") throws -> UUID {
        try store.post(EntryFactory.expense(Self.aed(amount), from: checking.info, category: category(name).info,
                                            date: today.addingTimeInterval(3600), memo: memo))
    }

    @Test("Before linking: rent is held back a second time, and the shortfall is shown, not hidden")
    func beforeLinking() throws {
        try spend(2500)
        let result = store.snapshot.safeToSpend()
        #expect(result.amount == Self.aed(-103.33)) // 2,896.67 cash − 2,500 rent again − 500 buffer
        #expect(store.snapshot.billSuggestions.map(\.occurrence.id) == [rentBill.id])
        #expect(rentBill.paid.isZero) // suggesting changes nothing
    }

    @Test("T01: linking the rent already recorded settles the bill without moving money again")
    func linkExisting() throws {
        let entry = try spend(2500)
        let balance = store.snapshot.balance(checking.id)
        try store.match(occurrenceId: rentBill.id, entryId: entry)

        #expect(store.snapshot.balance(checking.id) == balance)
        #expect(store.snapshot.state(of: rentBill) == .paid)
        #expect(store.snapshot.billSuggestions.isEmpty)
        #expect(store.snapshot.entries().count == 1)
        let line = store.snapshot.budget.line(category("Rent or mortgage").id, month: store.snapshot.monthKey)
        #expect(line.spent == Self.aed(2500))
        #expect(line.unpaidBills.isZero)
        // 2,896.67 − 500 buffer: rent isn't taken off a second time
        #expect(store.snapshot.safeToSpend().amount == Self.aed(2396.67))
    }

    @Test("T02/T03: two instalments settle rent; unlinking one reopens it with that much left")
    func partialPayments() throws {
        let first = try spend(1000)
        let second = try spend(1500)
        try store.match(occurrenceId: rentBill.id, entryId: first)
        #expect(store.snapshot.state(of: rentBill) == .partiallyPaid)
        #expect(rentBill.remaining == Self.aed(1500))
        try store.match(occurrenceId: rentBill.id, entryId: second)
        #expect(store.snapshot.state(of: rentBill) == .paid)

        try store.unlink(entryId: first)
        #expect(rentBill.remaining == Self.aed(1000))
        #expect(store.snapshot.entries().count == 2) // the transaction itself is untouched
        // Unlinked on purpose: not suggested straight back
        #expect(store.snapshot.billSuggestions.isEmpty)
    }

    @Test("T04: an unrelated 2,500 from Checking is never offered as rent")
    func unrelated() throws {
        try spend(2500, on: "Shopping", memo: "Sofa")
        #expect(store.snapshot.billSuggestions.isEmpty)
        #expect(rentBill.paid.isZero)
    }

    @Test("T05: Not this bill is remembered across rescans and a fresh store")
    func dismissedStaysDismissed() throws {
        let entry = try spend(2500)
        try store.dismissBillMatch(entryId: entry, occurrenceId: rentBill.id)
        #expect(store.snapshot.billSuggestions.isEmpty)
        let reopened = LedgerStore(context: ModelContext(container), calendar: LedgerStoreTests.dubai, now: { today })
        #expect(reopened.snapshot.billSuggestions.isEmpty)
    }

    @Test("T07: saving the bill's payment twice with the same key records it once")
    func repeatSave() throws {
        let key = UUID()
        let a = try store.pay(occurrenceId: rentBill.id, amount: Self.aed(2500), accountId: checking.id, categoryId: nil, date: today, key: key)
        let b = try store.pay(occurrenceId: rentBill.id, amount: Self.aed(2500), accountId: checking.id, categoryId: nil, date: today, key: key)
        #expect(a == b)
        #expect(store.snapshot.entries().count == 1)
        #expect(rentBill.paid == Self.aed(2500))
    }

    @Test("T08: paying or linking more than is left is refused, never over-settled")
    func overpayment() throws {
        #expect(throws: StoreError.self) {
            try store.pay(occurrenceId: rentBill.id, amount: Self.aed(2600), accountId: checking.id, categoryId: nil, date: today, key: UUID())
        }
        try store.pay(occurrenceId: rentBill.id, amount: Self.aed(2500), accountId: checking.id, categoryId: nil, date: today, key: UUID())
        let extra = try spend(100)
        #expect(throws: StoreError.self) { try store.match(occurrenceId: rentBill.id, entryId: extra) }
        #expect(rentBill.paid == Self.aed(2500))
    }

    @Test("Deleting a linked payment reopens the bill")
    func voidReopens() throws {
        let entry = try spend(2500)
        try store.match(occurrenceId: rentBill.id, entryId: entry)
        try store.void(entry)
        #expect(rentBill.paid.isZero)
        #expect(store.snapshot.state(of: rentBill) == .dueToday)
    }

    @Test("T09: an estimated bill comes back as an estimate when its payment is deleted")
    func estimate() throws {
        try store.savePlannedItem(PlannedItem(name: "DEWA", direction: .outflow, amount: Self.aed(400), isEstimate: true,
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: checking.id, categoryId: category("Utilities").id))
        let dewa = store.snapshot.occurrences.first { store.snapshot.item(for: $0)?.name == "DEWA" }!
        let entry = try store.pay(occurrenceId: dewa.id, amount: Self.aed(352), accountId: checking.id, categoryId: nil,
                                  date: today, key: UUID())
        var now = store.snapshot.occurrences.first { $0.id == dewa.id }!
        #expect(now.expected == Self.aed(352) && !now.isEstimate)
        try store.void(entry)
        now = store.snapshot.occurrences.first { $0.id == dewa.id }!
        #expect(now.expected == Self.aed(400) && now.isEstimate && now.paid.isZero)
    }

    @Test("T11: skip and undo skip")
    func skipAndUndo() throws {
        try store.skip(occurrenceId: rentBill.id)
        let skipped = store.snapshot.occurrences.first { $0.id == rentBill.id }!
        #expect(store.snapshot.state(of: skipped) == .skipped)
        #expect(store.snapshot.safeToSpend().obligations.isEmpty)
        try store.unskip(occurrenceId: skipped.id)
        #expect(store.snapshot.state(of: rentBill) == .dueToday)
    }

    @Test("T06: a card repayment settles the card's bill and adds no spending")
    func cardRepayment() throws {
        let card = try store.createAccount(name: "Mashreq card", kind: .creditCard, opening: Self.aed(-800), openingDate: today)
        try store.savePlannedItem(PlannedItem(name: "Mashreq card payment", direction: .outflow, amount: Self.aed(800),
                                              schedule: Schedule(start: today, frequency: .monthly(every: 1)),
                                              accountId: checking.id, debtId: card.id))
        let bill = store.snapshot.occurrences.first { store.snapshot.item(for: $0)?.debtId == card.id }!
        let spentBefore = totalSpent
        let transfer = try store.post(EntryFactory.transfer(Self.aed(800), from: checking.info, to: card.info, date: today))
        #expect(store.snapshot.billSuggestions.contains { $0.occurrence.id == bill.id })
        try store.match(occurrenceId: bill.id, entryId: transfer)

        #expect(store.snapshot.balance(card.id).isZero)
        #expect(store.snapshot.balance(checking.id) == Self.aed(4596.67))
        #expect(totalSpent == spentBefore)
        #expect(store.snapshot.state(of: store.snapshot.occurrences.first { $0.id == bill.id }!) == .paid)
    }

    @Test("T10: archived accounts are left out of cash, debt and net worth alike")
    func archived() throws {
        let old = try store.createAccount(name: "Old bank", kind: .bank, opening: Self.aed(300), openingDate: today)
        try store.updateAccount(old) { $0.archived = true }
        #expect(store.snapshot.cashAndBank == Self.aed(5396.67))
        #expect(store.snapshot.netWorth.assets == Self.aed(5396.67))
    }
}
