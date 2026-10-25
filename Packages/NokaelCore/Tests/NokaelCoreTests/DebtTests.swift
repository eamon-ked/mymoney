import Foundation
import Testing
@testable import NokaelCore

struct DebtTests {
    let cal = Fixture.dubai
    let aed = Fixture.aed

    @Test func monthlyInterestRoundsToTheFils() {
        // 30,000 at 6% is 150.00 a month
        #expect(DebtCalculator.monthlyInterest(owed: aed(30000), annualRateBps: 600) == aed(150))
        // 1,234.56 at 19.99% is 20.5657… → 20.57
        #expect(DebtCalculator.monthlyInterest(owed: aed(1234.56), annualRateBps: 1999) == aed(20.57))
        #expect(DebtCalculator.monthlyInterest(owed: aed(5000), annualRateBps: 0).isZero)
        #expect(DebtCalculator.monthlyInterest(owed: aed(0), annualRateBps: 1200).isZero)
    }

    @Test("QA-07: 1,000 against a 30,000 loan at 6% is 150 interest and 850 principal")
    func splitMatchesSpec() {
        let s = DebtCalculator.split(payment: aed(1000), owed: aed(30000), annualRateBps: 600)
        #expect(s.interest == aed(150))
        #expect(s.principal == aed(850))
        #expect(s.overpaid.isZero)
        #expect(s.total == aed(1000))
    }

    @Test func splitUsesStatementInterestAndFees() {
        let s = DebtCalculator.split(payment: aed(500), owed: aed(8000), annualRateBps: 2400,
                                     interest: aed(120), fees: aed(30))
        #expect(s.interest == aed(120))
        #expect(s.fees == aed(30))
        #expect(s.principal == aed(350))
    }

    @Test func splitNeverTakesMoreThanIsOwed() {
        let s = DebtCalculator.split(payment: aed(1000), owed: aed(400), annualRateBps: 1200)
        #expect(s.interest == aed(4))
        #expect(s.principal == aed(400))
        #expect(s.overpaid == aed(596))
        // A payment smaller than the interest is all interest
        let small = DebtCalculator.split(payment: aed(100), owed: aed(30000), annualRateBps: 600)
        #expect(small.interest == aed(100))
        #expect(small.principal.isZero)
    }

    @Test func payoffAtZeroInterestIsSimpleDivision() {
        let terms = DebtTerms(annualRateBps: 0, monthlyPayment: aed(1000), dueDay: 5)
        let p = DebtCalculator.payoff(owed: aed(5500), terms: terms, firstPayment: Fixture.date(2026, 11, 5), calendar: cal)
        guard case let .paidOff(months, last, interest, final) = p else { Issue.record("expected payoff"); return }
        #expect(months == 6)
        #expect(final == aed(500))
        #expect(interest.isZero)
        #expect(cal.dateComponents([.year, .month, .day], from: last) == DateComponents(year: 2027, month: 4, day: 5))
    }

    @Test func payoffWithInterestAndExtraPayments() {
        let terms = DebtTerms(annualRateBps: 600, monthlyPayment: aed(1000))
        let start = Fixture.date(2026, 11, 1)
        guard case let .paidOff(months, _, interest, _) =
                DebtCalculator.payoff(owed: aed(30000), terms: terms, firstPayment: start, calendar: cal),
              case let .paidOff(fasterMonths, _, lessInterest, _) =
                DebtCalculator.payoff(owed: aed(30000), terms: terms, extra: aed(500), firstPayment: start, calendar: cal)
        else { Issue.record("expected payoff"); return }
        // A standard amortisation: 30,000 at 6% with 1,000 a month takes 33 months
        #expect(months == 33)
        #expect(interest > aed(2500) && interest < aed(2700))
        #expect(fasterMonths < months)
        #expect(lessInterest < interest)
    }

    @Test func paymentBelowInterestNeverPaysOff() {
        let terms = DebtTerms(annualRateBps: 3000, monthlyPayment: aed(200))
        let p = DebtCalculator.payoff(owed: aed(10000), terms: terms, firstPayment: Fixture.date(2026, 11, 1), calendar: cal)
        #expect(p == .never(monthlyInterest: aed(250)))
        #expect(DebtCalculator.payoff(owed: aed(0), terms: terms, firstPayment: Date(), calendar: cal) == .alreadyPaidOff)
    }

    @Test func dueDatesClampToShortMonths() {
        let next = DebtCalculator.nextDueDate(dueDay: 31, onOrAfter: Fixture.date(2027, 2, 10), calendar: cal)
        #expect(cal.dateComponents([.month, .day], from: next) == DateComponents(month: 2, day: 28))
        let rolled = DebtCalculator.nextDueDate(dueDay: 5, onOrAfter: Fixture.date(2026, 10, 25), calendar: cal)
        #expect(cal.dateComponents([.month, .day], from: rolled) == DateComponents(month: 11, day: 5))
        let today = DebtCalculator.nextDueDate(dueDay: 25, onOrAfter: Fixture.date(2026, 10, 25, 18), calendar: cal)
        #expect(cal.dateComponents([.month, .day], from: today) == DateComponents(month: 10, day: 25))
    }

    @Test func ratesParseFromWhatPeopleType() {
        #expect(DebtTerms.rateBps(from: "12.5") == 1250)
        #expect(DebtTerms.rateBps(from: "3.99%") == 399)
        #expect(DebtTerms.rateBps(from: "0") == 0)
        #expect(DebtTerms.rateBps(from: "abc") == nil)
        #expect(DebtTerms.rateBps(from: "150") == nil)
    }
}
