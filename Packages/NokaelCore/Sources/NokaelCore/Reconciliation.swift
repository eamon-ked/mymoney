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
