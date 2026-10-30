import Foundation
import Testing
@testable import NokaelCore

struct RecurrenceTests {
    let cal = Fixture.dubai

    @Test func monthlyOnThe31stClampsAndReturns() {
        let s = Schedule(start: Fixture.date(2026, 1, 31), frequency: .monthly(every: 1))
        let days = RecurrenceEngine.dates(for: s, from: Fixture.date(2026, 1, 1), through: Fixture.date(2026, 4, 30), calendar: cal)
            .map { cal.component(.day, from: $0) }
        #expect(days == [31, 28, 31, 30])
    }

    @Test func weeklyQuarterlyYearlyAndCustom() {
        let start = Fixture.date(2026, 1, 1)
        let through = Fixture.date(2026, 12, 31)
        #expect(RecurrenceEngine.dates(for: Schedule(start: start, frequency: .weekly(every: 2)), from: start, through: Fixture.date(2026, 1, 31), calendar: cal).count == 3)
        #expect(RecurrenceEngine.dates(for: Schedule(start: start, frequency: .quarterly), from: start, through: through, calendar: cal).count == 4)
        #expect(RecurrenceEngine.dates(for: Schedule(start: start, frequency: .annually), from: start, through: through, calendar: cal).count == 1)
        #expect(RecurrenceEngine.dates(for: Schedule(start: start, frequency: .everyDays(10)), from: start, through: Fixture.date(2026, 1, 31), calendar: cal).count == 4)
    }

    @Test func occurrenceStates() {
        var occ = Occurrence(itemId: UUID(), dueDate: Fixture.date(2026, 10, 28), expected: Fixture.aed(2800))
        #expect(occ.state(today: Fixture.date(2026, 10, 25), calendar: cal) == .scheduled)
        #expect(occ.state(today: Fixture.date(2026, 10, 28, 18), calendar: cal) == .dueToday)
        #expect(occ.state(today: Fixture.date(2026, 10, 30), calendar: cal) == .overdue)
        occ.recordPayment(entryId: UUID(), amount: Fixture.aed(1000))
        #expect(occ.state(today: Fixture.date(2026, 10, 30), calendar: cal) == .partiallyPaid)
        #expect(occ.remaining == Fixture.aed(1800))
    }

    @Test func matchingTheSamePaymentTwiceCountsOnce() {
        var occ = Occurrence(itemId: UUID(), dueDate: Fixture.date(2026, 10, 28), expected: Fixture.aed(500))
        let entry = UUID()
        occ.recordPayment(entryId: entry, amount: Fixture.aed(500))
        occ.recordPayment(entryId: entry, amount: Fixture.aed(500))
        #expect(occ.paid == Fixture.aed(500))
    }

    @Test func estimatesSettleAtTheRealAmount() {
        var occ = Occurrence(itemId: UUID(), dueDate: Fixture.date(2026, 10, 28), expected: Fixture.aed(400), isEstimate: true)
        occ.recordPayment(entryId: UUID(), amount: Fixture.aed(437))
        #expect(occ.expected == Fixture.aed(437))
        #expect(!occ.isEstimate)
        #expect(occ.remaining.isZero)
    }

    @Test("BILL-05: editing the schedule never rewrites paid occurrences")
    func editingFutureKeepsHistory() {
        var item = PlannedItem(name: "Rent", direction: .outflow, amount: Fixture.aed(2800),
                               schedule: Schedule(start: Fixture.date(2026, 9, 28), frequency: .monthly(every: 1)))
        var occs = OccurrencePlanner.regenerate(item, existing: [], from: Fixture.date(2026, 9, 1), through: Fixture.date(2026, 12, 31), calendar: cal)
        #expect(occs.count == 4)
        occs[0].recordPayment(entryId: UUID(), amount: Fixture.aed(2800)) // September paid
        let octoberId = occs[1].id

        item.amount = Fixture.aed(3000)
        let rebuilt = OccurrencePlanner.regenerate(item, existing: occs, from: Fixture.date(2026, 10, 1), through: Fixture.date(2026, 12, 31), calendar: cal)
        #expect(rebuilt.count == 4)
        #expect(rebuilt[0].expected == Fixture.aed(2800))   // paid history unchanged
        #expect(rebuilt[1].expected == Fixture.aed(3000))   // future follows the edit
        #expect(rebuilt[1].id == octoberId)                 // same-day occurrence keeps its id
    }
}

struct BudgetTests {
    let f = Fixture()
    let cal = Fixture.dubai
    let oct = "2026-10"
    let nov = "2026-11"

    private func budget(_ entries: [Entry], _ allocations: [Allocation], groceriesPolicy: RolloverPolicy = .rollover) -> Budget {
        Budget(ledger: f.ledger(entries),
               categories: [BudgetCategory(id: f.groceries.id, name: "Groceries", group: "Essentials", policy: groceriesPolicy),
                            BudgetCategory(id: f.transport.id, name: "Transport", group: "Essentials"),
                            BudgetCategory(id: f.rent.id, name: "Rent", group: "Essentials")],
               allocations: allocations, calendar: cal)
    }

    private func opening(_ amount: Decimal, _ account: AccountInfo? = nil) throws -> Entry {
        try EntryFactory.openingBalance(Fixture.aed(amount), for: account ?? f.current, equity: f.equity, date: Fixture.date(2026, 10, 1))
    }

    @Test("Bills count as planned in their category, before and after they're paid")
    func billsArePlanned() throws {
        func withRent(_ entries: [Entry], paid: Decimal) -> Budget {
            let b = budget(entries, [])
            return Budget(ledger: b.ledger, categories: b.categories, allocations: [], calendar: cal,
                          bills: [BudgetBill(categoryId: f.rent.id, month: oct, amount: Fixture.aed(2800), unpaid: Fixture.aed(2800 - paid)),
                                  BudgetBill(categoryId: f.rent.id, month: nov, amount: Fixture.aed(2800), unpaid: Fixture.aed(2800))])
        }
        // Not paid yet: planned, not yet spent, and out of what's left to plan
        let unpaid = withRent([try opening(12000)], paid: 0).line(f.rent.id, month: oct)
        #expect(unpaid.planned == Fixture.aed(2800))
        #expect(unpaid.unpaidBills == Fixture.aed(2800))
        #expect(unpaid.remaining == Fixture.aed(2800))
        #expect(unpaid.withoutBills.isZero)
        #expect(withRent([try opening(12000)], paid: 0).availableToAllocate(month: oct) == Fixture.aed(9200))

        // Paid: spent, nothing left, and nothing carried into November
        let paidEntries = [try opening(12000),
                           try EntryFactory.expense(Fixture.aed(2800), from: f.current, category: f.rent, date: Fixture.date(2026, 10, 1))]
        let paid = withRent(paidEntries, paid: 2800)
        #expect(paid.line(f.rent.id, month: oct).remaining.isZero)
        #expect(paid.availableToAllocate(month: oct) == Fixture.aed(9200))
        #expect(paid.line(f.rent.id, month: nov).carriedIn.isZero)
        #expect(paid.line(f.rent.id, month: nov).remaining == Fixture.aed(2800))

        // Planning it by hand doesn't count it twice
        let byHand = Budget(ledger: paid.ledger, categories: paid.categories,
                            allocations: [Allocation(categoryId: f.rent.id, month: oct, amount: Fixture.aed(2800))], calendar: cal,
                            bills: paid.bills)
        #expect(byHand.line(f.rent.id, month: oct).fromBills.isZero)
        #expect(byHand.availableToAllocate(month: oct) == Fixture.aed(9200))
    }

    @Test("BUD-01: allocating creates no account transaction")
    func allocatingIsAPlan() throws {
        let b = budget([try opening(12000)], [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(2000))])
        #expect(b.ledger.balance(of: f.current.id) == Fixture.aed(12000))
        #expect(b.availableToAllocate(month: oct) == Fixture.aed(10000))
    }

    @Test("BUD-02: an expense updates exactly its category")
    func expenseHitsOneCategory() throws {
        let b = budget([try opening(12000),
                        try EntryFactory.expense(Fixture.aed(85), from: f.current, category: f.groceries, date: Fixture.date(2026, 10, 5))],
                       [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(600)),
                        Allocation(categoryId: f.transport.id, month: oct, amount: Fixture.aed(300))])
        #expect(b.line(f.groceries.id, month: oct).remaining == Fixture.aed(515))
        #expect(b.line(f.transport.id, month: oct).remaining == Fixture.aed(300))
        #expect(b.availableToAllocate(month: oct) == Fixture.aed(11100))
    }

    @Test("BUD-03: moving 200 between categories conserves totals")
    func moveConservesTotals() throws {
        let allocations = [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(600))]
        let b = budget([try opening(5000)], allocations)
        let before = b.availableToAllocate(month: oct)
        let moved = budget([try opening(5000)], allocations + (try b.move(Fixture.aed(200), from: f.groceries.id, to: f.transport.id, month: oct)))
        #expect(moved.availableToAllocate(month: oct) == before)
        #expect(moved.line(f.groceries.id, month: oct).remaining == Fixture.aed(400))
        #expect(moved.line(f.transport.id, month: oct).remaining == Fixture.aed(200))
    }

    @Test("CAT-03: moving more than is left needs explicit resolution")
    func moveBeyondAvailableNeedsConfirmation() throws {
        let b = budget([try opening(5000)], [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(100))])
        #expect(throws: BudgetError.exceedsAvailable(available: Fixture.aed(100))) {
            try b.move(Fixture.aed(150), from: f.groceries.id, to: f.transport.id, month: oct)
        }
        #expect((try? b.move(Fixture.aed(150), from: f.groceries.id, to: f.transport.id, month: oct, allowOverdraw: true))?.count == 2)
    }

    @Test("BUD-04: overspending shows the category and amount")
    func overspending() throws {
        let b = budget([try opening(5000),
                        try EntryFactory.expense(Fixture.aed(120), from: f.card, category: f.groceries, date: Fixture.date(2026, 10, 9))],
                       [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(100))])
        let line = b.line(f.groceries.id, month: oct)
        #expect(line.isOverspent)
        #expect(line.remaining == Fixture.aed(-20))
    }

    @Test("Spending with no budget lowers money not planned yet; it's never added back")
    func unbudgetedSpendingIsGone() throws {
        let b = budget([try opening(5000),
                        try EntryFactory.expense(Fixture.aed(400), from: f.current, category: f.transport, date: Fixture.date(2026, 10, 9))],
                       [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(1000)),
                        Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(0))])
        // 4,600 left in the account, 1,000 of it planned for groceries
        #expect(b.line(f.transport.id, month: oct).remaining == Fixture.aed(-400))
        #expect(b.availableToAllocate(month: oct) == Fixture.aed(3600))
    }

    @Test("QA-11 / BUD-05: a new month follows each category's rollover policy")
    func newMonthRollover() throws {
        let entries = [try opening(5000),
                       try EntryFactory.expense(Fixture.aed(300), from: f.current, category: f.groceries, date: Fixture.date(2026, 10, 9)),
                       try EntryFactory.expense(Fixture.aed(50), from: f.current, category: f.transport, date: Fixture.date(2026, 10, 9))]
        let allocations = [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(500)),
                           Allocation(categoryId: f.transport.id, month: oct, amount: Fixture.aed(200))]
        let rolling = budget(entries, allocations)
        #expect(rolling.line(f.groceries.id, month: nov).carriedIn == Fixture.aed(200))
        #expect(rolling.line(f.groceries.id, month: nov).remaining == Fixture.aed(200))

        let fresh = budget(entries, allocations, groceriesPolicy: .reset)
        #expect(fresh.line(f.groceries.id, month: nov).remaining.isZero)
        // Groceries' unspent 200 returns to the pool in November
        #expect(fresh.availableToAllocate(month: nov) == rolling.availableToAllocate(month: nov) + Fixture.aed(200))
    }

    @Test func futureAllocationsReduceAvailableNow() throws {
        let b = budget([try opening(1000)], [Allocation(categoryId: f.groceries.id, month: nov, amount: Fixture.aed(300))])
        #expect(b.availableToAllocate(month: oct) == Fixture.aed(700))
    }

    @Test func transfersBetweenBudgetAccountsAreNeutral() throws {
        let base = [try opening(1000), try opening(0, f.savings)]
        let before = budget(base, []).availableToAllocate(month: oct)
        let after = budget(base + [try EntryFactory.transfer(Fixture.aed(400), from: f.current, to: f.savings, date: Fixture.date(2026, 10, 3))], [])
        #expect(after.availableToAllocate(month: oct) == before)
    }

    @Test func copyLastMonthsPlan() throws {
        let b = budget([try opening(1000)], [Allocation(categoryId: f.groceries.id, month: oct, amount: Fixture.aed(500))])
        #expect(b.copyPlan(from: oct, to: nov) == [Allocation(categoryId: f.groceries.id, month: nov, amount: Fixture.aed(500))])
    }

    @Test func monthKeysStepAcrossYears() {
        #expect(BudgetMonth.adding(1, to: "2026-12", calendar: cal) == "2027-01")
        #expect(BudgetMonth.adding(-1, to: "2026-01", calendar: cal) == "2025-12")
    }
}

struct SafeToSpendTests {
    let f = Fixture()
    let cal = Fixture.dubai
    let today = Fixture.date(2026, 10, 25)
    let monthEnd = Fixture.date(2026, 10, 31, 23)

    private func calc(_ entries: [Entry], items: [PlannedItem] = [], occurrences: [Occurrence] = [],
                      reserves: [Reserve] = [], reservations: [CategoryReservation] = [], buffer: Decimal = 950,
                      confirmed: Bool = true) -> SafeToSpendCalculator {
        let ledger = f.ledger(entries)
        let lastConfirmed = confirmed ? Dictionary(uniqueKeysWithValues: f.all.map { ($0.id, today) }) : [:]
        return SafeToSpendCalculator(ledger: ledger, items: items, occurrences: occurrences, reserves: reserves,
                                     categoryReservations: reservations, buffer: Fixture.aed(buffer),
                                     lastConfirmed: lastConfirmed, calendar: cal)
    }

    private var rentItem: PlannedItem {
        PlannedItem(name: "Rent", direction: .outflow, amount: Fixture.aed(2800),
                    schedule: Schedule(start: Fixture.date(2026, 10, 28), frequency: .monthly(every: 1)),
                    accountId: f.current.id, categoryId: f.rent.id)
    }

    private var loanItem: PlannedItem {
        PlannedItem(name: "Loan payment", direction: .outflow, amount: Fixture.aed(1400),
                    schedule: Schedule(start: Fixture.date(2026, 10, 30), frequency: .monthly(every: 1)), accountId: f.current.id)
    }

    private func occurrences(for items: [PlannedItem]) -> [Occurrence] {
        items.flatMap { OccurrencePlanner.regenerate($0, existing: [], from: Fixture.date(2026, 10, 1), through: Fixture.date(2026, 12, 31), calendar: cal) }
    }

    private func opening() throws -> Entry {
        try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 1))
    }

    @Test("Spec example: 12,000 − 4,200 − 2,000 − 950 = 4,850")
    func specExample() throws {
        let items = [rentItem, loanItem]
        let s = calc([try opening()], items: items, occurrences: occurrences(for: items),
                     reserves: [Reserve(name: "Emergency fund", amount: Fixture.aed(2000), accountId: f.current.id)])
            .calculate(today: today, periodEnd: monthEnd)
        #expect(s.amount == Fixture.aed(4850))
        #expect(s.obligationsTotal == Fixture.aed(4200))
        #expect(s.statuses == [.reliable])
        #expect(s.obligations.map(\.label) == ["Rent", "Loan payment"])
    }

    @Test("QA-04: reserving savings leaves the account unchanged")
    func qa04Reserve() throws {
        let entries = [try opening()]
        let reserve = Reserve(name: "Emergency fund", amount: Fixture.aed(2000), accountId: f.current.id)
        let s = calc(entries, reserves: [reserve], buffer: 0).calculate(today: today, periodEnd: monthEnd)
        #expect(f.ledger(entries).balance(of: f.current.id) == Fixture.aed(12000))
        #expect(s.reservesTotal == Fixture.aed(2000))
        #expect(s.amount == Fixture.aed(10000))
    }

    @Test("SAFE-04: a reserve on a non-spendable account isn't subtracted")
    func reserveOnSavingsAccount() throws {
        let s = calc([try opening()], reserves: [Reserve(name: "Holiday", amount: Fixture.aed(3000), accountId: f.savings.id)], buffer: 0)
            .calculate(today: today, periodEnd: monthEnd)
        #expect(s.amount == Fixture.aed(12000))
    }

    @Test("QA-05: paying a reserved bill doesn't subtract it twice")
    func qa05PayBill() throws {
        let items = [rentItem]
        var occs = occurrences(for: items)
        let before = calc([try opening()], items: items, occurrences: occs).calculate(today: today, periodEnd: monthEnd).amount

        let payment = try EntryFactory.expense(Fixture.aed(2800), from: f.current, category: f.rent,
                                               date: Fixture.date(2026, 10, 26), occurrenceId: occs[0].id)
        occs[0].recordPayment(entryId: payment.id, amount: Fixture.aed(2800))
        let after = calc([try opening(), payment], items: items, occurrences: occs).calculate(today: Fixture.date(2026, 10, 26), periodEnd: monthEnd)
        #expect(after.amount == before)
        #expect(after.obligations.isEmpty)
    }

    @Test("QA-06 / SAFE-02: expected salary doesn't change today's money")
    func qa06ExpectedSalary() throws {
        let entries = [try opening()]
        let salary = PlannedItem(name: "Salary", direction: .inflow, amount: Fixture.aed(18000),
                                 schedule: Schedule(start: Fixture.date(2026, 10, 27), frequency: .monthly(every: 1)), accountId: f.current.id)
        let withSalary = calc(entries, items: [salary], occurrences: occurrences(for: [salary]))
        let without = calc(entries)
        #expect(withSalary.calculate(today: today, periodEnd: monthEnd).amount == without.calculate(today: today, periodEnd: monthEnd).amount)
        #expect(f.ledger(entries).balance(of: f.current.id) == Fixture.aed(12000))

        // Only the projection includes it, and says so
        let projection = withSalary.project(today: today, to: monthEnd)
        #expect(projection.amount == Fixture.aed(12000 - 950 + 18000))
        #expect(projection.expectedIncome.first?.detail == "Expected")
        #expect(!projection.assumptions.isEmpty)
    }

    @Test("SAFE-01: transfers between owned spendable accounts don't change it")
    func transfersAreNeutral() throws {
        let base = [try opening(), try EntryFactory.openingBalance(Fixture.aed(500), for: f.second, equity: f.equity, date: Fixture.date(2026, 10, 1))]
        let before = calc(base).calculate(today: today, periodEnd: monthEnd).amount
        let after = calc(base + [try EntryFactory.transfer(Fixture.aed(1000), from: f.current, to: f.second, date: Fixture.date(2026, 10, 20))])
            .calculate(today: today, periodEnd: monthEnd).amount
        #expect(before == after)
    }

    @Test("QA-14: missing inputs give an incomplete status, not a number")
    func qa14Incomplete() {
        let empty = SafeToSpendCalculator(ledger: Ledger(accounts: [f.equity, f.groceries], entries: [], currency: "AED"),
                                          items: [], occurrences: [], reserves: [], buffer: Fixture.aed(0), calendar: cal)
        let s = empty.calculate(today: today, periodEnd: monthEnd)
        #expect(s.amount == nil)
        #expect(s.statuses == [.incompleteSetup])
    }

    @Test func staleAndEstimatedAreDisclosed() throws {
        var bill = rentItem
        bill.isEstimate = true
        let s = calc([try opening()], items: [bill], occurrences: occurrences(for: [bill]), confirmed: false)
            .calculate(today: today, periodEnd: monthEnd)
        #expect(s.statuses.contains(.estimated))
        #expect(s.statuses.contains { if case .stale = $0 { return true } else { return false } })
    }

    @Test func shortfallIsExplainedNotAnOverdraft() throws {
        let entries = [try EntryFactory.openingBalance(Fixture.aed(1000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 1))]
        let rent = rentItem
        let s = calc(entries, items: [rent], occurrences: occurrences(for: [rent]), buffer: 0)
            .calculate(today: today, periodEnd: monthEnd)
        #expect(s.amount == Fixture.aed(-1800))
        #expect(s.statuses.contains(.shortfall))
    }

    @Test func categoryCoveredByABillIsntReservedTwice() throws {
        let rent = rentItem
        let s = calc([try opening()], items: [rent], occurrences: occurrences(for: [rent]),
                     reservations: [CategoryReservation(categoryId: f.rent.id, name: "Rent", remaining: Fixture.aed(2800)),
                                    CategoryReservation(categoryId: f.groceries.id, name: "Groceries", remaining: Fixture.aed(600))],
                     buffer: 0)
            .calculate(today: today, periodEnd: monthEnd)
        #expect(s.categoryReservations.map(\.label) == ["Groceries"])
        #expect(s.amount == Fixture.aed(12000 - 2800 - 600))
    }
}

struct ReconciliationTests {
    let f = Fixture()

    @Test("REC-01..03: differences are found, and fixing one needs a reason")
    func reconcile() throws {
        let ledger = f.ledger([
            try EntryFactory.openingBalance(Fixture.aed(1000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 1)),
            try EntryFactory.expense(Fixture.aed(40), from: f.current, category: f.groceries, date: Fixture.date(2026, 10, 3))
        ])
        let check = Reconciler.check(ledger: ledger, accountId: f.current.id, statementDate: Fixture.date(2026, 10, 10),
                                     statementBalance: Fixture.aed(955))
        #expect(check.calculated == Fixture.aed(960))
        #expect(check.difference == Fixture.aed(-5))
        #expect(check.unreconciled.count == 2)
        #expect(throws: LedgerError.reasonRequired) {
            try Reconciler.adjustment(for: check, account: f.current, equity: f.equity, reason: "")
        }
        let fix = try #require(try Reconciler.adjustment(for: check, account: f.current, equity: f.equity, reason: "Bank fee"))
        #expect(fix.kind == .reconciliation)
        #expect(f.ledger(ledger.entries + [fix]).balance(of: f.current.id, asOf: Fixture.date(2026, 10, 10)) == Fixture.aed(955))
    }
}

struct JourneyTests {
    let f = Fixture()
    let cal = Fixture.dubai

    @Test("QA-09: editing a posted expense recalculates balances and budget")
    func qa09Edit() throws {
        let opening = try EntryFactory.openingBalance(Fixture.aed(1000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 1))
        var original = try EntryFactory.expense(Fixture.aed(50), from: f.current, category: f.groceries, date: Fixture.date(2026, 10, 5))
        let allocations = [Allocation(categoryId: f.groceries.id, month: "2026-10", amount: Fixture.aed(300))]
        // An edit voids the original and posts a replacement, keeping history
        original.status = .void
        let replacement = try EntryFactory.expense(Fixture.aed(60), from: f.current, category: f.transport, date: Fixture.date(2026, 10, 5))
        let ledger = f.ledger([opening, original, replacement])
        let budget = Budget(ledger: ledger, categories: [BudgetCategory(id: f.groceries.id, name: "Groceries", group: "Essentials"),
                                                         BudgetCategory(id: f.transport.id, name: "Transport", group: "Essentials")],
                            allocations: allocations, calendar: cal)
        #expect(ledger.balance(of: f.current.id) == Fixture.aed(940))
        #expect(budget.line(f.groceries.id, month: "2026-10").remaining == Fixture.aed(300))
        #expect(budget.line(f.transport.id, month: "2026-10").spent == Fixture.aed(60))
        #expect(ledger.entries.count == 3) // the original is kept, voided
    }

    @Test("Journey A: first salary and first budget")
    func journeyA() throws {
        let today = Fixture.date(2026, 10, 25)
        // 1. Current account with 12,000
        let entries = [try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 20))]
        // 2. Monthly salary expected on the 27th
        let salary = PlannedItem(name: "Salary", direction: .inflow, amount: Fixture.aed(18000),
                                 schedule: Schedule(start: Fixture.date(2026, 10, 27), frequency: .monthly(every: 1)), accountId: f.current.id)
        // 3. Rent and loan payment schedules
        let rent = PlannedItem(name: "Rent", direction: .outflow, amount: Fixture.aed(2800),
                               schedule: Schedule(start: Fixture.date(2026, 10, 28), frequency: .monthly(every: 1)),
                               accountId: f.current.id, categoryId: f.rent.id)
        let loan = PlannedItem(name: "Loan payment", direction: .outflow, amount: Fixture.aed(1400),
                               schedule: Schedule(start: Fixture.date(2026, 10, 30), frequency: .monthly(every: 1)), accountId: f.current.id)
        let items = [salary, rent, loan]
        let occs = items.flatMap { OccurrencePlanner.regenerate($0, existing: [], from: Fixture.date(2026, 10, 1), through: Fixture.date(2026, 12, 31), calendar: cal) }
        // 4. Reserve 2,000 for an emergency fund
        let reserve = Reserve(name: "Emergency fund", amount: Fixture.aed(2000), accountId: f.current.id)
        // 5. Spending capacity from actual balances only
        let calculator = SafeToSpendCalculator(ledger: f.ledger(entries), items: items, occurrences: occs, reserves: [reserve],
                                               buffer: Fixture.aed(950),
                                               lastConfirmed: Dictionary(uniqueKeysWithValues: f.all.map { ($0.id, Fixture.date(2026, 10, 20)) }),
                                               calendar: cal)
        let s = calculator.calculate(today: today, periodEnd: Fixture.date(2026, 10, 31, 23))
        #expect(s.amount == Fixture.aed(4850))
        #expect(s.isReliable)
        // 6. Allocate flexible spending
        let allocations = [Allocation(categoryId: f.groceries.id, month: "2026-10", amount: Fixture.aed(1500)),
                           Allocation(categoryId: f.transport.id, month: "2026-10", amount: Fixture.aed(500)),
                           Allocation(categoryId: f.rent.id, month: "2026-10", amount: Fixture.aed(2800))]
        let budget = Budget(ledger: f.ledger(entries),
                            categories: [f.groceries, f.transport, f.rent].map { BudgetCategory(id: $0.id, name: $0.name, group: "Essentials") },
                            allocations: allocations, calendar: cal)
        // 7. Reliable balances and money still available to allocate
        #expect(budget.availableToAllocate(month: "2026-10") == Fixture.aed(12000 - 4800))
        #expect(f.ledger(entries).netWorth().total == Fixture.aed(12000))
    }

    @Test("Journey B: buy groceries")
    func journeyB() throws {
        let opening = try EntryFactory.openingBalance(Fixture.aed(12000), for: f.current, equity: f.equity, date: Fixture.date(2026, 10, 20))
        let allocations = [Allocation(categoryId: f.groceries.id, month: "2026-10", amount: Fixture.aed(1500))]
        let categories = [BudgetCategory(id: f.groceries.id, name: "Groceries", group: "Essentials")]
        let reservations: (Budget) -> [CategoryReservation] = { b in
            [CategoryReservation(categoryId: f.groceries.id, name: "Groceries", remaining: b.line(f.groceries.id, month: "2026-10").remaining)]
        }
        let today = Fixture.date(2026, 10, 25)
        let end = Fixture.date(2026, 10, 31, 23)

        let beforeLedger = f.ledger([opening])
        let beforeBudget = Budget(ledger: beforeLedger, categories: categories, allocations: allocations, calendar: cal)
        let beforeSafe = SafeToSpendCalculator(ledger: beforeLedger, items: [], occurrences: [], reserves: [],
                                               categoryReservations: reservations(beforeBudget), buffer: Fixture.aed(0), calendar: cal)
            .calculate(today: today, periodEnd: end).amount

        // Add → Expense, AED 85, Groceries, from the current account
        let spend = try EntryFactory.expense(Fixture.aed(85), from: f.current, category: f.groceries, date: today)
        let ledger = f.ledger([opening, spend])
        let budget = Budget(ledger: ledger, categories: categories, allocations: allocations, calendar: cal)
        let safe = SafeToSpendCalculator(ledger: ledger, items: [], occurrences: [], reserves: [],
                                         categoryReservations: reservations(budget), buffer: Fixture.aed(0), calendar: cal)
            .calculate(today: today, periodEnd: end).amount

        #expect(ledger.balance(of: f.current.id) == Fixture.aed(11915))                    // account −85
        #expect(budget.line(f.groceries.id, month: "2026-10").remaining == Fixture.aed(1415)) // groceries −85
        #expect(safe == beforeSafe)  // already reserved for groceries, so not deducted twice
    }
}
