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
}
