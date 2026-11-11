import Foundation
import Testing
@testable import NokaelCore

struct NotificationPlannerTests {
    let cal = Fixture.dubai
    let aed = Fixture.aed
    let now = Fixture.date(2026, 10, 26, 10)

    func item(_ name: String, _ amount: Decimal, _ direction: Direction = .outflow, start: Date = Fixture.date(2026, 10, 1)) -> PlannedItem {
        PlannedItem(name: name, direction: direction, amount: aed(amount),
                    schedule: Schedule(start: start, frequency: .monthly(every: 1)))
    }

    @Test func aBillRemindsBeforeAndAsksTheMorningAfter() {
        let rent = item("Rent", 5000)
        let occ = Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000))
        let notices = NotificationPlanner.bills(items: [rent], occurrences: [occ], daysBefore: [:], now: now, hour: 9, calendar: cal)
        #expect(notices.map(\.kind) == [.billDue, .billMissed])
        #expect(notices[0].fireDate == Fixture.date(2026, 10, 30, 9))
        #expect(notices[1].fireDate == Fixture.date(2026, 11, 2, 9))
        #expect(!notices[0].isUrgent)
    }

    @Test func aPaidOrSwitchedOffBillSendsNothing() {
        let rent = item("Rent", 5000)
        let gym = item("Gym", 300)
        let occurrences = [Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000), paid: aed(5000)),
                           Occurrence(itemId: gym.id, dueDate: Fixture.date(2026, 11, 5), expected: aed(300))]
        let notices = NotificationPlanner.bills(items: [rent, gym], occurrences: occurrences, daysBefore: [gym.id: -1],
                                                now: now, hour: 9, calendar: cal)
        #expect(notices.isEmpty)
    }

    @Test func dueTodayIsUrgent() {
        let card = item("Card", 900)
        let occ = Occurrence(itemId: card.id, dueDate: Fixture.date(2026, 10, 28), expected: aed(900))
        let notices = NotificationPlanner.bills(items: [card], occurrences: [occ], daysBefore: [card.id: 0], now: now, hour: 9, calendar: cal)
        #expect(notices.first { $0.kind == .billDue }?.isUrgent == true)
    }

    @Test func runningShortNamesTheBillTheMorningBefore() {
        let rent = item("Rent", 5000)
        let gym = item("Gym", 300)
        let occurrences = [Occurrence(itemId: gym.id, dueDate: Fixture.date(2026, 10, 29), expected: aed(300)),
                           Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 11, 1), expected: aed(5000))]
        let forecast = CashForecaster.forecast(start: aed(4000), items: [rent, gym], occurrences: occurrences, spendableAccountIds: [],
                                               today: now, through: Fixture.date(2026, 11, 9), calendar: cal)
        let notice = NotificationPlanner.runningShort(forecast, now: now, hour: 9, calendar: cal)
        #expect(notice?.name == "Rent")
        #expect(notice?.amount == aed(1300))
        #expect(notice?.fireDate == Fixture.date(2026, 10, 31, 9))
        #expect(notice?.isUrgent == true)
    }

    @Test func runningShortTomorrowStillWarnsThisMorning() {
        let rent = item("Rent", 5000)
        let occ = Occurrence(itemId: rent.id, dueDate: Fixture.date(2026, 10, 27), expected: aed(5000))
        let forecast = CashForecaster.forecast(start: aed(100), items: [rent], occurrences: [occ], spendableAccountIds: [],
                                               today: Fixture.date(2026, 10, 26, 8), through: Fixture.date(2026, 11, 9), calendar: cal)
        let early = NotificationPlanner.runningShort(forecast, now: Fixture.date(2026, 10, 26, 8), hour: 9, calendar: cal)
        #expect(early?.fireDate == Fixture.date(2026, 10, 26, 9))
        // Once the hour's gone there's no second chance to send it the same day
        #expect(NotificationPlanner.runningShort(forecast, now: Fixture.date(2026, 10, 26, 20), hour: 9, calendar: cal) == nil)
    }

    @Test func paydayIsTheNextUnrecordedPay() {
        let pay = item("Salary", 12000, .inflow)
        let occurrences = [Occurrence(itemId: pay.id, dueDate: Fixture.date(2026, 10, 26), expected: aed(12000), paid: aed(12000)),
                           Occurrence(itemId: pay.id, dueDate: Fixture.date(2026, 11, 26), expected: aed(12000))]
        let notice = NotificationPlanner.payday(items: [pay], occurrences: occurrences, now: now, hour: 9, calendar: cal)
        #expect(notice?.fireDate == Fixture.date(2026, 11, 26, 9))
    }

    @Test func aTrialWarnsTwoDaysBeforeItsFirstCharge() {
        let tv = item("Streaming", 45, start: Fixture.date(2026, 11, 5))
        let occurrences = [Occurrence(itemId: tv.id, dueDate: Fixture.date(2026, 11, 5), expected: aed(45)),
                           Occurrence(itemId: tv.id, dueDate: Fixture.date(2026, 12, 5), expected: aed(45))]
        let notices = NotificationPlanner.trials(items: [tv], occurrences: occurrences, trialIds: [tv.id], now: now, hour: 9, calendar: cal)
        #expect(notices.map(\.fireDate) == [Fixture.date(2026, 11, 3, 9)])
        #expect(NotificationPlanner.trials(items: [tv], occurrences: occurrences, trialIds: [], now: now, hour: 9, calendar: cal).isEmpty)
    }

    @Test func theMostUrgentKeepTheirPlaceWhenThereAreTooMany() {
        let bills = (1...70).map { PlannedNotice(id: "b\($0)", kind: .billDue, fireDate: now.addingTimeInterval(Double($0) * 3600)) }
        let backup = PlannedNotice(id: "backup", kind: .backup, fireDate: now.addingTimeInterval(60))
        let short = PlannedNotice(id: "short", kind: .runningShort, fireDate: now.addingTimeInterval(9_000_000))
        let fitted = NotificationPlanner.fit(bills + [backup, short], calendar: cal)
        #expect(fitted.count == 60)
        #expect(fitted.first?.id == "short")
        // Then the soonest: the backup nudge in a minute stays, the bills furthest away go
        #expect(fitted.contains { $0.id == "backup" })
        #expect(fitted.contains { $0.id == "b1" } && !fitted.contains { $0.id == "b70" })
    }

    @Test func weeklyNagsLandOnTheSameWeekday() {
        let anchor = Fixture.date(2026, 10, 1)
        #expect(NotificationPlanner.weekly(from: anchor, after: now, hour: 9, calendar: cal) == Fixture.date(2026, 10, 29, 9))
        #expect(NotificationPlanner.weekly(from: Fixture.date(2026, 11, 2), after: now, hour: 9, calendar: cal) == Fixture.date(2026, 11, 2, 9))
        #expect(NotificationPlanner.next(dayOfMonth: 3, after: now, hour: 9, calendar: cal) == Fixture.date(2026, 11, 3, 9))
        #expect(NotificationPlanner.next(dayOfMonth: 28, after: now, hour: 9, calendar: cal) == Fixture.date(2026, 10, 28, 9))
    }

    @Test func worksTheSameInEurosOnABerlinCalendar() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        berlin.firstWeekday = 2
        let at = { (d: Int, h: Int) in berlin.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
        let rent = PlannedItem(name: "Miete", direction: .outflow, amount: Money(900, currency: "EUR"),
                               schedule: Schedule(start: at(1, 12), frequency: .monthly(every: 1)))
        // The clocks go back on 25 October in Berlin; reminders still come at 8 local time
        let occ = Occurrence(itemId: rent.id, dueDate: at(27, 12), expected: Money(900, currency: "EUR"))
        let notices = NotificationPlanner.bills(items: [rent], occurrences: [occ], daysBefore: [rent.id: 1],
                                                now: at(24, 10), hour: 8, calendar: berlin)
        #expect(notices.map(\.fireDate) == [at(26, 8), at(28, 8)])
        #expect(notices[0].amount == Money(900, currency: "EUR"))
    }
}

struct UnusualSpendTests {
    let aed = Fixture.aed
    let t = Fixture.date(2026, 10, 26, 12)

    func entry(_ memo: String, _ amount: Decimal, _ direction: Capture.Direction = .spent, minutes: Double = 0) -> CapturedEntry {
        CapturedEntry(id: UUID(), date: t.addingTimeInterval(minutes * 60), amount: aed(amount), direction: direction, memo: memo, source: .sms)
    }

    @Test func theSameShopAndAmountTwiceInAnHourIsADoubleCharge() {
        let new = entry("CARREFOUR MOE", 85.5)
        #expect(UnusualSpend.check(new, recent: [entry("Carrefour", 85.5, minutes: -20)], usual: []) == .doubleCharge)
        #expect(UnusualSpend.check(new, recent: [entry("Carrefour", 85.5, minutes: -200)], usual: []) == nil)
        #expect(UnusualSpend.check(new, recent: [entry("Spinneys", 85.5, minutes: -20)], usual: []) == nil)
    }

    @Test func feesRefundsAndBigOnes() {
        #expect(UnusualSpend.check(entry("ATM WITHDRAWAL FEE", 2.1), recent: [], usual: []) == .fee)
        #expect(UnusualSpend.check(entry("LOAN INTEREST", 900), recent: [], usual: []) == nil)
        #expect(UnusualSpend.check(entry("ZARA", 120, .received), recent: [entry("Zara Mall", 300, minutes: -3000)], usual: []) == .refund)
        #expect(UnusualSpend.check(entry("Salary", 120, .received), recent: [entry("Zara", 300, minutes: -3000)], usual: []) == nil)
        let usual = [40, 55, 60, 35, 70].map { aed(Decimal($0)) }
        #expect(UnusualSpend.check(entry("Talabat", 400), recent: [], usual: usual) == .large)
        #expect(UnusualSpend.check(entry("Talabat", 90), recent: [], usual: usual) == nil)
        #expect(UnusualSpend.check(entry("Talabat", 400), recent: [], usual: Array(usual.prefix(3))) == nil)
    }
}
