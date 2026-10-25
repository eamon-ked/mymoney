import Foundation
import Testing
@testable import NokaelCore

struct GoalTests {
    let cal = Fixture.dubai
    let aed = Fixture.aed
    let today = Fixture.date(2026, 10, 25)

    @Test func monthlyAmountToReachTheDate() {
        // 6,000 left by the end of March: Oct, Nov, Dec, Jan, Feb, Mar
        let p = GoalCalculator.progress(saved: aed(4000), target: aed(10000), targetDate: Fixture.date(2027, 3, 31),
                                        today: today, calendar: cal)
        #expect(p.remaining == aed(6000))
        #expect(p.fraction == 0.4)
        #expect(p.status == .needsPerMonth(aed(1000), months: 6))
    }

    @Test func monthlyAmountRoundsUpToTheFils() {
        let p = GoalCalculator.progress(saved: aed(0), target: aed(1000), targetDate: Fixture.date(2026, 12, 1),
                                        today: today, calendar: cal)
        #expect(p.status == .needsPerMonth(aed(333.34), months: 3))
    }

    @Test func reachedNoDateAndPastDue() {
        #expect(GoalCalculator.progress(saved: aed(1200), target: aed(1000), targetDate: nil, today: today, calendar: cal).status == .reached)
        #expect(GoalCalculator.progress(saved: aed(1200), target: aed(1000), targetDate: nil, today: today, calendar: cal).fraction == 1)
        #expect(GoalCalculator.progress(saved: aed(100), target: aed(1000), targetDate: nil, today: today, calendar: cal).status == .noDate)
        #expect(GoalCalculator.progress(saved: aed(100), target: aed(1000), targetDate: Fixture.date(2026, 10, 1),
                                        today: today, calendar: cal).status == .pastDue)
        // Due later this month still leaves this month to save
        #expect(GoalCalculator.progress(saved: aed(100), target: aed(1000), targetDate: Fixture.date(2026, 10, 30),
                                        today: today, calendar: cal).status == .needsPerMonth(aed(900), months: 1))
    }
}
