//
//  AIEngineTests.swift
//  Nokael Money
//
//  Which model answers: Apple's cloud model only for Plus, only when it's
//  switched on and can answer now; everything else runs on the iPhone.
//

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceApp

@MainActor
struct AIEngineTests {

    @Test("Plus, switched on and the cloud ready: the cloud model answers")
    func plusGetsCloud() {
        #expect(AppleIntelligence.engine(plus: true, cloudOn: true, cloud: .ready) == .cloud)
    }

    @Test("Free users, the switch off, today's limit used, offline or iOS 26: on the iPhone")
    func everythingElseOnDevice() {
        #expect(AppleIntelligence.engine(plus: false, cloudOn: true, cloud: .ready) == .onDevice)
        #expect(AppleIntelligence.engine(plus: true, cloudOn: false, cloud: .ready) == .onDevice)
        #expect(AppleIntelligence.engine(plus: true, cloudOn: true, cloud: .limitReached) == .onDevice)
        #expect(AppleIntelligence.engine(plus: true, cloudOn: true, cloud: .unavailable) == .onDevice)
        #expect(AppleIntelligence.engine(plus: true, cloudOn: true, cloud: .needsNewerIOS) == .onDevice)
    }

    @Test("The cloud model's full picture has the money, the bills and how the app works, within its budget")
    func fullContext() throws {
        let container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { Date() })
        DemoData.load(into: store)
        let text = FinanceDigest(store.snapshot).fullContext
        #expect(text.count <= FinanceDigest.fullContextBudget)
        #expect(text.contains("Safe to spend"))
        #expect(text.contains("Transactions in the last 90 days"))
        #expect(text.contains("How the Nokael Money app works"))
    }

    @Test("Searching finds groceries even when the model fills in the category differently")
    func searchIsForgiving() throws {
        let container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { Date() })
        DemoData.load(into: store)
        let digest = FinanceDigest(store.snapshot)
        #expect(digest.search(text: "groceries", category: "Food and groceries", days: 30) != "No matching transactions.")
        #expect(digest.search(text: nil, category: "Groceries", days: nil) != "No matching transactions.")
        #expect(digest.budget(monthKey: nil).contains("Groceries"))
    }
}
