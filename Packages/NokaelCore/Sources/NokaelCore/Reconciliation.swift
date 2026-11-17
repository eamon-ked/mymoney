import Foundation

public struct ReconciliationCheck: Sendable {
    public let accountId: UUID
    public let statementDate: Date
    /// What the ledger says the account held on the statement date
    public let calculated: Money
    public let statement: Money
    /// Statement minus calculated; zero means they agree
    public let difference: Money
    /// Posted entries up to the statement date that haven't been reconciled yet
    public let unreconciled: [Entry]

    public var matches: Bool { difference.isZero }

    public init(accountId: UUID, statementDate: Date, calculated: Money, statement: Money, difference: Money,
                unreconciled: [Entry]) {
        self.accountId = accountId
        self.statementDate = statementDate
        self.calculated = calculated
        self.statement = statement
        self.difference = difference
        self.unreconciled = unreconciled
    }
}

public enum Reconciler {
    /// Compares the ledger with a bank statement. Never changes the ledger by itself.
    public static func check(ledger: Ledger, accountId: UUID, statementDate: Date, statementBalance: Money) -> ReconciliationCheck {
        let calculated = ledger.balance(of: accountId, asOf: statementDate)
        let open = ledger.posted.filter { $0.date <= statementDate && $0.touches(accountId) && !$0.isReconciled(in: accountId) }
        return ReconciliationCheck(accountId: accountId, statementDate: statementDate, calculated: calculated,
                                   statement: statementBalance, difference: statementBalance - calculated,
                                   unreconciled: open)
    }

    /// The adjustment that makes the ledger agree with the statement. Needs a reason,
    /// which goes into the entry memo and the audit trail. nil when they already agree.
    public static func adjustment(for check: ReconciliationCheck, account: AccountInfo, equity: AccountInfo,
                                  reason: String) throws -> Entry? {
        guard !check.matches else { return nil }
        return try EntryFactory.adjustment(check.difference, account: account, equity: equity,
                                           date: check.statementDate, reason: reason, kind: .reconciliation)
    }
}

/// The app's entries for a statement's dates that the statement doesn't show. Some just haven't reached
/// it yet: card purchases take a few days to post, and anything on its last day may have come after it
/// was made. The rest are worth a look, as one may be a mistake (the same money saved twice).
public struct StatementGaps: Equatable, Sendable {
    public struct Candidate: Sendable {
        public let id: UUID
        public let date: Date
        /// How much it moved, either way
        public let size: Money
        /// Saved from a bank message or Apple Pay, not typed or imported
        public let automatic: Bool
        /// Money out with a card: banks post these a few days later
        public let cardPurchase: Bool

        public init(id: UUID, date: Date, size: Money, automatic: Bool, cardPurchase: Bool) {
            self.id = id
            self.date = date
            self.size = size.magnitude
            self.automatic = automatic
            self.cardPurchase = cardPurchase
        }
    }

    /// Probably not on the statement yet: left out of the balance check
    public let waiting: [UUID]
    /// Not on the statement, and it should be by now
    public let missing: [UUID]

    /// How many days a card purchase can take to reach a statement
    public static let postingDays = 3

    public static func find(_ entries: [Candidate], matched: Set<UUID>, firstDay: Date, lastDay: Date,
                            calendar: Calendar) -> StatementGaps {
        let start = calendar.startOfDay(for: firstDay)
        let last = calendar.startOfDay(for: lastDay)
        guard let end = calendar.date(byAdding: .day, value: 1, to: last),
              let postingFrom = calendar.date(byAdding: .day, value: -postingDays, to: last) else {
            return StatementGaps(waiting: [], missing: [])
        }
        var waiting: [UUID] = [], missing: [UUID] = []
        let onStatement = entries.filter { matched.contains($0.id) }
        for e in entries.sorted(by: { $0.date < $1.date })
        where e.date >= start && e.date < end && !matched.contains(e.id) {
            let lastDayOfStatement = e.date >= last
            let posting = e.cardPurchase && e.date >= postingFrom
            // The same amount that day is already on the statement: more likely the same money saved twice
            let twin = onStatement.contains { $0.size == e.size && calendar.isDate($0.date, inSameDayAs: e.date) }
            if e.automatic && (lastDayOfStatement || posting) && !twin { waiting.append(e.id) } else { missing.append(e.id) }
        }
        return StatementGaps(waiting: waiting, missing: missing)
    }
}
