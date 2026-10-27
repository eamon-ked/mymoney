import Foundation

/// Money that has already left an account, as the bill matcher sees it
public struct BillPayment: Sendable {
    public let date: Date
    /// What left the paying account, positive
    public let amount: Money
    public let fromAccountId: UUID?
    /// The spending category, for an expense
    public let categoryId: UUID?
    /// The card or loan it went to, for a transfer or debt payment
    public let debtId: UUID?
    public let memo: String

    public init(date: Date, amount: Money, fromAccountId: UUID?, categoryId: UUID?, debtId: UUID?, memo: String) {
        self.date = date
        self.amount = amount
        self.fromAccountId = fromAccountId
        self.categoryId = categoryId
        self.debtId = debtId
        self.memo = memo
    }

    /// Reads an expense, a transfer to a card or loan, or a debt payment.
    /// Income, adjustments and transfers between owned cash accounts are never bill payments.
    public init?(_ entry: Entry, accounts: [UUID: AccountInfo]) {
        guard entry.status == .posted else { return nil }
        func kind(_ line: Line) -> AccountKind? { accounts[line.accountId]?.kind }
        let from = entry.lines.first { kind($0)?.isAsset == true && $0.amount.isNegative }
        guard let from else { return nil }
        switch entry.kind {
        case .expense:
            let category = entry.lines.first { kind($0) == .expense }
            self.init(date: entry.date, amount: from.amount.negated, fromAccountId: from.accountId,
                      categoryId: category?.accountId, debtId: nil, memo: entry.memo)
        case .transfer, .debtPayment:
            guard let debt = entry.lines.first(where: { kind($0)?.isLiability == true }) else { return nil }
            self.init(date: entry.date, amount: from.amount.negated, fromAccountId: from.accountId,
                      categoryId: nil, debtId: debt.accountId, memo: entry.memo)
        default:
            return nil
        }
    }
}

public struct BillMatch: Hashable, Sendable {
    public let occurrenceId: UUID
    public let itemId: UUID
    public let score: Int
    /// Less than what's left on the bill: it would leave the bill part paid
    public let isPartial: Bool
}

/// Which unpaid bill a payment that's already recorded probably was. It only
/// ever suggests: linking is always the person's decision.
public enum BillMatcher {
    /// The lowest score worth showing
    public static let threshold = 6

    /// Unpaid outflow bills this payment could be, best first. A match needs
    /// the bill's identity (its category, its card or loan, or its name) as
    /// well as a fitting amount; the same account and amount alone is not
    /// enough. A payment larger than what's left only fits a card or loan.
    public static func candidates(for payment: BillPayment, occurrences: [Occurrence], items: [PlannedItem],
                                  calendar: Calendar = .current) -> [BillMatch] {
        let words = Set(StatementImport.merchantWords(payment.memo, limit: 6))
        return occurrences.compactMap { occ -> (BillMatch, TimeInterval)? in
            guard let item = items.first(where: { $0.id == occ.itemId }), item.direction == .outflow,
                  !occ.skipped, occ.remaining.isPositive, payment.amount.isPositive,
                  payment.amount.currency == occ.remaining.currency else { return nil }

            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: occ.dueDate),
                                               to: calendar.startOfDay(for: payment.date)).day ?? 0
            guard days >= -20 && days <= 15 else { return nil }

            // Identity: a debt bill is only ever paid to its own card or loan
            var identity = 0
            if let debtId = item.debtId {
                guard payment.debtId == debtId else { return nil }
                identity += 4
            } else if payment.debtId != nil {
                return nil
            }
            if let bill = item.categoryId, let category = payment.categoryId {
                guard bill == category else { return nil }
                identity += 3
            }
            let named = !words.isDisjoint(with: StatementImport.merchantWords(item.name, limit: 6))
            if named { identity += 2 }
            guard identity > 0 else { return nil }

            // Amount: exact, close to an estimate, or a real part of what's left
            var score = identity
            let isPartial = payment.amount < occ.remaining
            if payment.amount > occ.remaining {
                // More than a card or loan's monthly amount is an extra repayment; for any other bill it's not this one
                guard item.debtId != nil else { return nil }
                score += 3
            } else if payment.amount == occ.remaining {
                score += 3
            } else if occ.isEstimate && payment.amount.minorUnits * 4 >= occ.remaining.minorUnits * 3 {
                score += 2
            } else if payment.amount.minorUnits * 10 >= occ.remaining.minorUnits {
                score += 1
            } else {
                return nil
            }

            if let from = payment.fromAccountId, let account = item.accountId { score += from == account ? 1 : -1 }
            score += abs(days) <= 3 ? 2 : abs(days) <= 10 ? 1 : 0

            guard score >= threshold else { return nil }
            // An estimate is settled at whatever was really paid, so it's never part paid
            let match = BillMatch(occurrenceId: occ.id, itemId: item.id, score: score,
                                  isPartial: isPartial && !occ.isEstimate)
            return (match, abs(occ.dueDate.timeIntervalSince(payment.date)))
        }
        .sorted { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        .map(\.0)
    }
}
