//
//  TransferWarningTests.swift
//  Nokael Money
//
//  Moving more than an account holds is pointed out, never blocked: money may have arrived unnoticed.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct TransferWarningTests {
    static func eur(_ v: Decimal) -> Money { Money(v, currency: "EUR") }

    let container: ModelContainer
    let store: LedgerStore
    let current: LedgerAccountRecord
    let savings: LedgerAccountRecord
    let card: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 18))!
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.updateSettings { $0.currency = "EUR" }
        try store.addStarterCategories()
        let start = LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        current = try store.createAccount(name: "Current", kind: .bank, opening: Self.eur(100), openingDate: start)
        savings = try store.createAccount(name: "Savings", kind: .savings, opening: Self.eur(0), openingDate: start)
        card = try store.createAccount(name: "Card", kind: .creditCard, opening: Self.eur(0), openingDate: start)
    }

    func form(_ amount: Decimal, from: UUID, to: UUID) -> EntryForm {
        EntryForm(kind: .transfer, amount: Self.eur(amount), accountId: from, toAccountId: to,
                  date: LedgerStoreTests.dubai.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!)
    }

    @Test func movingMoreThanTheAccountHoldsIsPointedOut() throws {
        #expect(form(100, from: current.id, to: savings.id).shortfall(in: store.snapshot) == nil)
        let short = try #require(form(130, from: current.id, to: savings.id).shortfall(in: store.snapshot))
        #expect(short.holds == Self.eur(100) && short.after == Self.eur(-30))
        // A credit card can go further into debt: no warning
        #expect(form(500, from: card.id, to: current.id).shortfall(in: store.snapshot) == nil)
    }

    @Test func editingATransferCountsWhatItAlreadyMoved() throws {
        let id = try store.save(form(80, from: current.id, to: savings.id))
        // Raising it from 80 to 100 still fits the 100 the account had before it
        #expect(form(100, from: current.id, to: savings.id).shortfall(in: store.snapshot, replacing: id) == nil)
        #expect(form(101, from: current.id, to: savings.id).shortfall(in: store.snapshot, replacing: id) != nil)
    }
}
