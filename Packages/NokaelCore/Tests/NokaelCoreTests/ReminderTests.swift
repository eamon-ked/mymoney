import Foundation
import Testing
@testable import NokaelCore

struct ReminderTests {
    let cal = Fixture.dubai
    let aed = Fixture.aed
    let now = Fixture.date(2026, 10, 26, 10)

    func bill(_ name: String, _ amount: Decimal) -> PlannedItem {
        PlannedItem(name: name, direction: .outflow, amount: aed(amount),
                    schedule: Schedule(start: Fixture.date(2026, 10, 1), frequency: .monthly(every: 1)))
    }

    @Test func remindsTheChosenDaysBeforeAtTheChosenHour() {
        let rent = bill("Rent", 5000)
        let occ = Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000))
        let plan = ReminderPlanner.plan(items: [rent], occurrences: [occ], daysBefore: [rent.id: 3],
                                        now: now, hour: 9, calendar: cal)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == Fixture.date(2026, 10, 29, 9))
        #expect(plan[0].amount == aed(5000))
        #expect(plan[0].daysBefore == 3)
    }

    @Test func leavesOutPaidSkippedPastIncomeAndSwitchedOff() {
        let rent = bill("Rent", 5000)
        let gym = bill("Gym", 300)
        let salary = PlannedItem(name: "Salary", direction: .inflow, amount: aed(20000),
                                 schedule: Schedule(start: Fixture.date(2026, 10, 1), frequency: .monthly(every: 1)))
        let occurrences = [
            Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000), paid: aed(5000)),
            Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 12, 1), expected: aed(5000), skipped: true),
            // Reminder time (two days before at 9) already passed this morning
            Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 10, 28), expected: aed(5000)),
            Occurrence(itemId: gym.id, dueDate: Fixture.date(2026, 11, 5), expected: aed(300)),
            Occurrence(itemId: salary.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(20000)),
        ]
        let plan = ReminderPlanner.plan(items: [rent, gym, salary], occurrences: occurrences,
                                        daysBefore: [gym.id: -1], now: now, hour: 9, calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test func partlyPaidRemindsForWhatsLeftAndKeepsTheSoonest() {
        let card = bill("Card", 2000)
        let occurrences = (1...5).map { m in
            Occurrence(itemId: card.id, dueDate: cal.date(byAdding: .month, value: m, to: Fixture.date(2026, 10, 15))!, expected: aed(2000),
                       paid: m == 1 ? aed(500) : nil)
        }
        let plan = ReminderPlanner.plan(items: [card], occurrences: occurrences, daysBefore: [card.id: 0],
                                        now: now, hour: 8, limit: 2, calendar: cal)
        #expect(plan.map(\.fireDate) == [Fixture.date(2026, 11, 15, 8), Fixture.date(2026, 12, 15, 8)])
        #expect(plan[0].amount == aed(1500))
    }
}
