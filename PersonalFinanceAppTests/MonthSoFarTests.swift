//
//  MonthSoFarTests.swift
//  Nokael Money
//
//  The line under Safe to spend: exact figures from the ledger, compared with
//  the same point last month, and nothing when there's nothing to say.
//

import Foundation
import NokaelCore
import SwiftData
import Testing
@testable import PersonalFinanceApp

struct MonthSoFarTests {
    private func aed(_ value: Int64) -> Money { Money(minorUnits: value * 100, currency: "AED") }

    @Test("Less, more, or about the same as this time last month")
    func comparesWithLastMonth() {
        #expect(MonthSoFar(spent: aed(800), lastMonth: aed(1000), biggest: "Groceries").sentence
                == "You've spent \(aed(800).compact), \(aed(200).compact) less than this time last month.")
        #expect(MonthSoFar(spent: aed(1200), lastMonth: aed(1000), biggest: nil).sentence
                == "You've spent \(aed(1200).compact), \(aed(200).compact) more than this time last month.")
        #expect(MonthSoFar(spent: aed(1040), lastMonth: aed(1000), biggest: nil).sentence
                == "You've spent \(aed(1040).compact), about the same as this time last month.")
    }

    @Test("No last month to compare with: the total and where most of it went")
    func firstMonth() {
        #expect(MonthSoFar(spent: aed(500), lastMonth: nil, biggest: "Groceries").sentence
                == "You've spent \(aed(500).compact), most of it on Groceries.")
    }

    @Test("Nothing spent this month or last: no line at all")
    func nothingToSay() {
        #expect(MonthSoFar(spent: aed(0), lastMonth: nil, biggest: nil).sentence == nil)
        #expect(MonthSoFar(spent: aed(0), lastMonth: aed(300), biggest: nil).sentence
                == "Nothing spent yet. By now last month it was \(aed(300).compact).")
    }

    @Test("Built from the demo ledger, the total matches Reports' spending so far")
    @MainActor func matchesTheLedger() throws {
        let container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { Date() })
        DemoData.load(into: store)
        let snapshot = store.snapshot
        let soFar = MonthSoFar(snapshot)
        let categories = snapshot.accountRecords.filter { $0.kind == .expense }.map(\.info)
        let month = Reports.totals(snapshot.monthKey, ledger: snapshot.ledger, expenseCategories: categories,
                                   incomeCategories: [], calendar: snapshot.calendar, loanCategories: snapshot.loanCategories)
        // Demo entries are all dated today or earlier, so so-far equals the whole month
        #expect(soFar.spent == month.spending)
        #expect(soFar.sentence != nil)
    }
}
