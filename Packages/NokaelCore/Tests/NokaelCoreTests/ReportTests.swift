import Foundation
import Testing
@testable import NokaelCore

struct ReportTests {
    let f = Fixture()
    let cal = Fixture.dubai
    let aed = Fixture.aed

    private func ledger() throws -> Ledger {
        let sep = Fixture.date(2026, 9, 10), oct = Fixture.date(2026, 10, 10)
        return f.ledger([
            try EntryFactory.openingBalance(aed(5000), for: f.current, equity: f.equity, date: Fixture.date(2026, 9, 1)),
            try EntryFactory.openingBalance(aed(-30000), for: f.carLoan, equity: f.equity, date: Fixture.date(2026, 9, 1)),
            try EntryFactory.income(aed(18000), to: f.current, category: f.salary, date: sep),
            try EntryFactory.expense(aed(1200), from: f.current, category: f.groceries, date: sep),
            try EntryFactory.income(aed(18000), to: f.current, category: f.salary, date: oct),
            try EntryFactory.expense(aed(900), from: f.current, category: f.groceries, date: oct),
            try EntryFactory.expense(aed(6500), from: f.current, category: f.rent, date: oct),
            // Neither a transfer nor loan principal is spending; the interest is
            try EntryFactory.transfer(aed(2000), from: f.current, to: f.savings, date: oct),
            try EntryFactory.debtPayment(principal: aed(850), interest: aed(150), fees: aed(0), from: f.current,
                                         debt: f.carLoan, interestCategory: f.interest, date: oct)
        ])
    }

    @Test("A month's income, spending and what was left; transfers and principal excluded")
    func monthTotals() throws {
        let r = Reports.month("2026-10", ledger: try ledger(), expenseCategories: [f.groceries, f.rent, f.transport, f.interest],
                              incomeCategories: [f.salary], calendar: cal)
        #expect(r.totals.income == aed(18000))
        #expect(r.totals.spending == aed(7550))
        #expect(r.totals.leftOver == aed(10450))
        #expect(r.previous.spending == aed(1200))
        #expect(r.spending.map(\.name) == ["Rent", "Groceries", "Interest & fees"]) // no activity: Transport left out
        let groceries = try #require(r.spending.first { $0.name == "Groceries" })
        #expect(groceries.change == aed(-300))
    }

    @Test func plannedAmountsComeFromTheBudget() throws {
        let l = try ledger()
        let budget = Budget(ledger: l, categories: [BudgetCategory(id: f.groceries.id, name: "Groceries", group: "", policy: .rollover)],
                            allocations: [Allocation(categoryId: f.groceries.id, month: "2026-10", amount: aed(1500))], calendar: cal)
        let r = Reports.month("2026-10", ledger: l, expenseCategories: [f.groceries], incomeCategories: [], budget: budget, calendar: cal)
        #expect(r.spending.first?.planned == aed(1500))
    }

    @Test func trendIsOldestFirst() throws {
        let t = Reports.trend(endingAt: "2026-10", count: 3, ledger: try ledger(), expenseCategories: [f.groceries, f.rent, f.interest],
                              incomeCategories: [f.salary], calendar: cal)
        #expect(t.map(\.month) == ["2026-08", "2026-09", "2026-10"])
        #expect(t.map(\.spending) == [aed(0), aed(1200), aed(7550)])
        #expect(t[1].savingsRate == Double(16800) / 18000)
        #expect(t[0].savingsRate == nil)
    }
}
