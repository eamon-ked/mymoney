//  Regression tests from the audits (8 Nov 2026).
import Foundation
import Testing
@testable import NokaelCore

struct AuditCoreTests {
    let now = Date(timeIntervalSince1970: 1794096000)
    @Test func aPurchaseReversalMustNotBeAnotherExpense() throws {
        let parsed = try #require(AlertParser.read("Your purchase of AED 45.00 at Carrefour has been reversed.", homeCurrency: "AED", date: now))
        #expect(parsed.direction == .received)
    }
    @Test func aCashbackPromotionMustNotBeIncome() {
        let parsed = AlertParser.read("Earn AED 50 cashback at Carrefour this weekend.", homeCurrency: "AED", date: now)
        #expect(parsed == nil)
    }
    @Test func aWarningMustDetectIntradayShortfallEvenWhenSalaryRestoresBalance() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = cal.date(byAdding: .day, value: 3, to: now)!
        let account = UUID()
        let bill = PlannedItem(name: "Rent", direction: .outflow, amount: Money(200, currency: "AED"), schedule: Schedule(start: date, frequency: .monthly(every: 1)), accountId: account)
        let pay = PlannedItem(name: "Salary", direction: .inflow, amount: Money(300, currency: "AED"), schedule: Schedule(start: date, frequency: .monthly(every: 1)), accountId: account)
        let occurrences = [Occurrence(itemId: bill.id, dueDate: date, expected: bill.amount), Occurrence(itemId: pay.id, dueDate: date, expected: pay.amount)]
        let forecast = CashForecaster.forecast(start: Money(100, currency: "AED"), items: [bill,pay], occurrences: occurrences, spendableAccountIds: [account], today: now, through: date, calendar: cal)
        #expect(forecast.firstShortfall != nil)
        #expect(NotificationPlanner.runningShort(forecast, now: now, hour: 9, calendar: cal) != nil)
    }
    @Test func inferredAmountMustAppearAsAnAmountInsteadOfInsideUnrelatedDigits() {
        #expect(!AlertParser.mentions(Money(Decimal(string: "12.34")!, currency: "AED"), in: "Code 123456 for a purchase of AED 99.00"))
    }
}

struct AuditCSVTests {
    @Test func malformedDebitMustRaiseAnErrorInsteadOfDisappearing() throws {
        let text = "Date,Description,Debit,Credit\n08/11/2026,Carrefour,BAD,\n"
        var rejected = false
        do {
            let rows = try StatementImport.read(text, currency: "AED", calendar: Calendar(identifier: .gregorian))
        } catch { rejected = true }
        #expect(rejected)
    }
}

struct CaptureIdentityRecheckTests {
    @Test func separateSameAmountPurchasesAcrossSourcesMustNotMerge() {
        let now = Date(timeIntervalSince1970: 1794096000)
        let incoming = Capture(source: .sms, direction: .spent, amount: Money(45, currency: "AED"), merchant: "Starbucks", cardHint: "2222", date: now.addingTimeInterval(120), text: "purchase B")
        let existing = CapturedEntry(id: UUID(), date: now, amount: Money(45, currency: "AED"), direction: .spent, memo: "Carrefour", source: .applePay)
        #expect(CaptureMatcher.duplicate(of: incoming, in: [existing]) == nil)
    }
}

struct NotificationSaturationAuditTests {
 @Test func imminentDueRemindersMustNotBeCrowdedOutByDistantMissedNotices() {
  let now = Fixture.date(2026, 11, 8, 8)
  let items = (1...16).map { PlannedItem(name: "Bill \($0)", direction: .outflow, amount: Fixture.aed(100), schedule: Schedule(start: Fixture.date(2026,11,10), frequency: .monthly(every: 1))) }
  let dates = [Fixture.date(2026,11,10),Fixture.date(2026,12,10),Fixture.date(2027,1,10),Fixture.date(2027,2,10)]
  let occs = items.flatMap { item in dates.map { Occurrence(itemId: item.id, dueDate:$0, expected:Fixture.aed(100)) } }
  let all = NotificationPlanner.bills(items:items, occurrences:occs, daysBefore:[:], now:now, hour:9, calendar:Fixture.dubai)
  let fitted = NotificationPlanner.fit(all)
  #expect(fitted.contains { $0.kind == .billDue && Fixture.dubai.isDate($0.fireDate, inSameDayAs: now) })
 }
}
