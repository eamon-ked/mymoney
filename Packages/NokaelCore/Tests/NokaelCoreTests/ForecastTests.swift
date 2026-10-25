import Foundation
import Testing
@testable import NokaelCore

struct ForecastTests {
    let f = Fixture()
    let cal = Fixture.dubai
    let aed = Fixture.aed
    let today = Fixture.date(2026, 10, 25)

    private func item(_ name: String, _ direction: Direction, _ amount: Decimal, account: UUID? = nil) -> PlannedItem {
        PlannedItem(name: name, direction: direction, amount: aed(amount),
                    schedule: Schedule(start: today, frequency: .monthly(every: 1)), accountId: account)
    }

    private func occ(_ item: PlannedItem, _ y: Int, _ m: Int, _ d: Int, paid: Decimal = 0) -> Occurrence {
        Occurrence(itemId: item.id, dueDate: Fixture.date(y, m, d), expected: item.amount, paid: aed(paid))
    }

    @Test("Bills and income are applied on their dates; the lowest point is found")
    func runningProjection() {
        let rent = item("Rent", .outflow, 6500), salary = item("Salary", .inflow, 18000), phone = item("Phone", .outflow, 280)
        let fc = CashForecaster.forecast(start: aed(8000), items: [rent, salary, phone],
                                         occurrences: [occ(rent, 2026, 10, 28), occ(phone, 2026, 11, 3), occ(salary, 2026, 11, 12)],
                                         spendableAccountIds: [f.current.id], today: today, through: Fixture.date(2026, 11, 30),
                                         calendar: cal)
        #expect(fc.days.map(\.balance) == [aed(1500), aed(1220), aed(19220)])
        #expect(fc.lowest == aed(1220))
        #expect(cal.component(.day, from: fc.lowestDate) == 3)
        #expect(fc.firstShortfall == nil)
        #expect(fc.moneyIn == aed(18000))
        #expect(fc.moneyOut == aed(6780))
    }

    @Test("A shortfall is flagged on the day, even when income lands the same day")
    func shortfall() {
        let rent = item("Rent", .outflow, 6500), salary = item("Salary", .inflow, 18000)
        let fc = CashForecaster.forecast(start: aed(5000), items: [rent, salary],
                                         occurrences: [occ(rent, 2026, 11, 1), occ(salary, 2026, 11, 1)],
                                         spendableAccountIds: [], today: today, through: Fixture.date(2026, 11, 30), calendar: cal)
        #expect(fc.lowest == aed(-1500))
        #expect(cal.component(.day, from: try! #require(fc.firstShortfall)) == 1)
        #expect(fc.end == aed(16500))
    }

    @Test("Paid, part-paid, skipped, overdue and non-spendable items")
    func whatCounts() {
        let rent = item("Rent", .outflow, 6500, account: f.current.id)
        let fromSavings = item("Insurance", .outflow, 900, account: f.savings.id)
        let gym = item("Gym", .outflow, 300)
        var skipped = occ(gym, 2026, 11, 2)
        skipped.skipped = true
        let fc = CashForecaster.forecast(start: aed(10000), items: [rent, fromSavings, gym],
                                         occurrences: [occ(rent, 2026, 10, 20, paid: 2500),   // overdue, part paid
                                                       occ(rent, 2026, 11, 20, paid: 6500),   // already paid
                                                       occ(fromSavings, 2026, 11, 5), skipped],
                                         spendableAccountIds: [f.current.id], today: today, through: Fixture.date(2026, 11, 30),
                                         calendar: cal)
        #expect(fc.days.count == 1)
        let day = fc.days[0]
        #expect(cal.isDate(day.date, inSameDayAs: today))
        #expect(day.events.first?.isOverdue == true)
        #expect(day.balance == aed(6000))
    }
}
