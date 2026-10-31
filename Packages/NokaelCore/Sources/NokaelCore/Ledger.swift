import Foundation

// MARK: - Accounts

/// Every place money can sit or come from. Balance-sheet kinds are real
/// accounts; income, expense and equity are the ledger's other side.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case cash, bank, savings, creditCard, loan, investment, otherAsset
    /// Money lent to someone: theirs to pay back, so it's owned but can't be spent or planned
    case lent
    case income, expense, equity

    public var isAsset: Bool { [.cash, .bank, .savings, .investment, .otherAsset, .lent].contains(self) }
    /// Money of your own to pay with; what someone owes you isn't, until they pay it back
    public var holdsMoney: Bool { isAsset && self != .lent }
    public var isLiability: Bool { [.creditCard, .loan].contains(self) }
    public var isBalanceSheet: Bool { isAsset || isLiability }
    public var isCategory: Bool { self == .income || self == .expense }

    /// Cash and bank money can be spent today; savings and investments are kept aside
    public var defaultSpendable: Bool { self == .cash || self == .bank }

    /// Accounts whose money (or debt) the monthly budget plans for
    public var defaultOnBudget: Bool { [.cash, .bank, .savings, .creditCard].contains(self) }
}

/// What the calculators need to know about an account
public struct AccountInfo: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var kind: AccountKind
    public var currency: String
    public var includeInNetWorth: Bool
    public var spendable: Bool
    public var onBudget: Bool
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, kind: AccountKind, currency: String,
                includeInNetWorth: Bool = true, spendable: Bool? = nil, onBudget: Bool? = nil, archived: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.includeInNetWorth = includeInNetWorth
        self.spendable = spendable ?? kind.defaultSpendable
        self.onBudget = onBudget ?? kind.defaultOnBudget
        self.archived = archived
    }
}

// MARK: - Entries

/// One side of an entry. Debits are positive, credits negative: an asset or
/// expense goes up with a positive line, a liability, income or equity with a
/// negative one. So an account's balance is simply the sum of its lines, and a
/// card you owe AED 2,100 on has a balance of −2,100.
public struct Line: Hashable, Codable, Sendable {
    public var accountId: UUID
    public var amount: Money

    public init(accountId: UUID, amount: Money) {
        self.accountId = accountId
        self.amount = amount
    }
}

public enum EntryKind: String, Codable, Sendable {
    case expense, income, transfer, adjustment, openingBalance, reconciliation, debtPayment
}

public enum EntryStatus: String, Codable, Sendable {
    case posted, void
}

public enum ClearedState: String, Codable, Sendable {
    case uncleared, cleared, reconciled
}

public struct Entry: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var kind: EntryKind
    public var date: Date
    public var status: EntryStatus
    public var cleared: ClearedState
    public var memo: String
    public var lines: [Line]
    /// Set by the caller per save attempt; a repeat of the same key is the same entry
    public var idempotencyKey: UUID
    /// The planned item occurrence this entry pays, if any
    public var occurrenceId: UUID?

    public init(id: UUID = UUID(), kind: EntryKind, date: Date, status: EntryStatus = .posted,
                cleared: ClearedState = .uncleared, memo: String = "", lines: [Line],
                idempotencyKey: UUID = UUID(), occurrenceId: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.status = status
        self.cleared = cleared
        self.memo = memo
        self.lines = lines
        self.idempotencyKey = idempotencyKey
        self.occurrenceId = occurrenceId
    }

    public var isPosted: Bool { status == .posted }

    public func amount(on accountId: UUID) -> Money? {
        let mine = lines.filter { $0.accountId == accountId }
        guard let first = mine.first else { return nil }
        return mine.dropFirst().reduce(first.amount) { $0 + $1.amount }
    }

    public func touches(_ accountId: UUID) -> Bool { lines.contains { $0.accountId == accountId } }
}

public enum LedgerError: Error, Equatable, Sendable {
    case noLines
    case unbalanced(Money)
    case mixedCurrencies
    case amountMustBePositive
    case sameAccount
    case wrongAccountKind(String)
    case reasonRequired
    case unknownAccount(UUID)
}

// MARK: - Building entries

/// The only way to make entries, so every movement balances by construction
public enum EntryFactory {
    public static func validate(_ entry: Entry) throws {
        guard !entry.lines.isEmpty else { throw LedgerError.noLines }
        let currency = entry.lines[0].amount.currency
        guard entry.lines.allSatisfy({ $0.amount.currency == currency }) else { throw LedgerError.mixedCurrencies }
        let total = entry.lines.map(\.amount).sum(currency)
        guard total.isZero else { throw LedgerError.unbalanced(total) }
    }

    /// Money spent from an account (or put on a card) for a spending category
    public static func expense(_ amount: Money, from account: AccountInfo, category: AccountInfo,
                               date: Date, memo: String = "", key: UUID = UUID(), occurrenceId: UUID? = nil) throws -> Entry {
        guard amount.isPositive else { throw LedgerError.amountMustBePositive }
        guard account.kind.isBalanceSheet else { throw LedgerError.wrongAccountKind("Pay from an account") }
        guard category.kind == .expense else { throw LedgerError.wrongAccountKind("Choose a spending category") }
        return try make(.expense, date: date, memo: memo, key: key, occurrenceId: occurrenceId, lines: [
            Line(accountId: account.id, amount: -amount),
            Line(accountId: category.id, amount: amount)
        ])
    }

    /// Money received into an account from an income category
    public static func income(_ amount: Money, to account: AccountInfo, category: AccountInfo,
                              date: Date, memo: String = "", key: UUID = UUID(), occurrenceId: UUID? = nil) throws -> Entry {
        guard amount.isPositive else { throw LedgerError.amountMustBePositive }
        guard account.kind.isBalanceSheet else { throw LedgerError.wrongAccountKind("Receive into an account") }
        guard category.kind == .income else { throw LedgerError.wrongAccountKind("Choose an income category") }
        return try make(.income, date: date, memo: memo, key: key, occurrenceId: occurrenceId, lines: [
            Line(accountId: account.id, amount: amount),
            Line(accountId: category.id, amount: -amount)
        ])
    }

    /// Moves money between two of the user's own accounts; never income or spending
    public static func transfer(_ amount: Money, from source: AccountInfo, to destination: AccountInfo,
                                date: Date, memo: String = "", key: UUID = UUID(), occurrenceId: UUID? = nil) throws -> Entry {
        guard amount.isPositive else { throw LedgerError.amountMustBePositive }
        guard source.id != destination.id else { throw LedgerError.sameAccount }
        guard source.kind.isBalanceSheet, destination.kind.isBalanceSheet else {
            throw LedgerError.wrongAccountKind("Transfers are between your accounts")
        }
        return try make(.transfer, date: date, memo: memo, key: key, occurrenceId: occurrenceId, lines: [
            Line(accountId: source.id, amount: -amount),
            Line(accountId: destination.id, amount: amount)
        ])
    }

    /// Starting balance of an account. Pass what the account holds: negative for a card you owe on.
    public static func openingBalance(_ balance: Money, for account: AccountInfo, equity: AccountInfo,
                                      date: Date, key: UUID = UUID()) throws -> Entry {
        guard equity.kind == .equity else { throw LedgerError.wrongAccountKind("Opening balances need the equity account") }
        return try make(.openingBalance, date: date, memo: "Opening balance", key: key, lines: [
            Line(accountId: account.id, amount: balance),
            Line(accountId: equity.id, amount: -balance)
        ])
    }

    /// Corrects an account's balance by `delta`. Always needs a reason, for the audit trail.
    public static func adjustment(_ delta: Money, account: AccountInfo, equity: AccountInfo, date: Date,
                                  reason: String, kind: EntryKind = .adjustment, key: UUID = UUID()) throws -> Entry {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.reasonRequired }
        guard !delta.isZero else { throw LedgerError.amountMustBePositive }
        return try make(kind, date: date, memo: reason, key: key, lines: [
            Line(accountId: account.id, amount: delta),
            Line(accountId: equity.id, amount: -delta)
        ])
    }

    /// A debt payment: the funding account drops by the whole payment, the debt by
    /// the principal only, and interest and fees are recognised as spending.
    public static func debtPayment(principal: Money, interest: Money, fees: Money,
                                   from funding: AccountInfo, debt: AccountInfo,
                                   interestCategory: AccountInfo, feeCategory: AccountInfo? = nil,
                                   date: Date, memo: String = "", key: UUID = UUID(), occurrenceId: UUID? = nil) throws -> Entry {
        guard debt.kind.isLiability else { throw LedgerError.wrongAccountKind("Pay towards a card or loan") }
        guard interestCategory.kind == .expense else { throw LedgerError.wrongAccountKind("Interest needs a spending category") }
        guard !principal.isNegative, !interest.isNegative, !fees.isNegative else { throw LedgerError.amountMustBePositive }
        let total = principal + interest + fees
        guard total.isPositive else { throw LedgerError.amountMustBePositive }
        var lines = [Line(accountId: funding.id, amount: -total)]
        if principal.isPositive { lines.append(Line(accountId: debt.id, amount: principal)) }
        if interest.isPositive { lines.append(Line(accountId: interestCategory.id, amount: interest)) }
        if fees.isPositive { lines.append(Line(accountId: (feeCategory ?? interestCategory).id, amount: fees)) }
        return try make(.debtPayment, date: date, memo: memo, key: key, occurrenceId: occurrenceId, lines: lines)
    }

    /// A bill paid in full for a group: the account drops by the whole amount, the category
    /// takes your share, and each person's share becomes what they owe you
    public static func splitExpense(_ total: Money, from account: AccountInfo, category: AccountInfo,
                                    shares: [(person: AccountInfo, amount: Money)], date: Date, memo: String = "",
                                    key: UUID = UUID(), occurrenceId: UUID? = nil) throws -> Entry {
        guard !shares.isEmpty else {
            return try expense(total, from: account, category: category, date: date, memo: memo, key: key, occurrenceId: occurrenceId)
        }
        guard total.isPositive, shares.allSatisfy({ $0.amount.isPositive }) else { throw LedgerError.amountMustBePositive }
        guard account.kind.isBalanceSheet, account.kind != .lent else { throw LedgerError.wrongAccountKind("Pay from an account") }
        guard category.kind == .expense else { throw LedgerError.wrongAccountKind("Choose a spending category") }
        guard shares.allSatisfy({ $0.person.kind == .lent }) else { throw LedgerError.wrongAccountKind("Split with people") }
        let mine = total - shares.map(\.amount).sum(total.currency)
        guard mine.isPositive else { throw LedgerError.wrongAccountKind("Others' shares must be less than the total") }
        var lines = [Line(accountId: account.id, amount: -total), Line(accountId: category.id, amount: mine)]
        lines += shares.map { Line(accountId: $0.person.id, amount: $0.amount) }
        return try make(.expense, date: date, memo: memo, key: key, occurrenceId: occurrenceId, lines: lines)
    }

    private static func make(_ kind: EntryKind, date: Date, memo: String, key: UUID,
                             occurrenceId: UUID? = nil, lines: [Line]) throws -> Entry {
        let entry = Entry(kind: kind, date: date, memo: memo, lines: lines, idempotencyKey: key, occurrenceId: occurrenceId)
        try validate(entry)
        return entry
    }
}

// MARK: - Reading the ledger

/// A read-only view over accounts and entries. Every number is recomputed
/// from posted entries, so it is always reproducible.
public struct Ledger: Sendable {
    public let accounts: [UUID: AccountInfo]
    public let entries: [Entry]
    public let currency: String

    public init(accounts: [AccountInfo], entries: [Entry], currency: String) {
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.entries = entries.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        self.currency = currency
    }

    public var posted: [Entry] { entries.filter(\.isPosted) }

    /// Sum of an account's posted lines up to and including `asOf`
    public func balance(of accountId: UUID, asOf: Date? = nil) -> Money {
        posted
            .filter { asOf == nil || $0.date <= asOf! }
            .compactMap { $0.amount(on: accountId) }
            .sum(currency)
    }

    /// Each posted entry on an account with the balance right after it, oldest first
    public func runningBalance(of accountId: UUID) -> [(entry: Entry, change: Money, balance: Money)] {
        var running = Money.zero(currency)
        return posted.compactMap { entry in
            guard let change = entry.amount(on: accountId) else { return nil }
            running += change
            return (entry, change, running)
        }
    }

    /// Net movement on a category in [start, end): spending positive for expense
    /// categories, money received positive for income categories.
    public func activity(on categoryId: UUID, from start: Date, to end: Date) -> Money {
        let raw = posted
            .filter { $0.date >= start && $0.date < end }
            .compactMap { $0.amount(on: categoryId) }
            .sum(currency)
        return accounts[categoryId]?.kind == .income ? raw.negated : raw
    }

    /// What an entry spent from a spending category. A loan payment counts in full: its interest and
    /// fees, plus the principal of each loan that belongs to the category (`loanCategories`, loan id to
    /// category id). A loan with no category listed counts with whatever category its interest went to.
    /// A card's principal never counts: it paid for purchases that were counted when they were made.
    public func spending(of entry: Entry, on categoryId: UUID, loanCategories: [UUID: UUID] = [:]) -> Money? {
        let charge = entry.amount(on: categoryId)
        guard entry.kind == .debtPayment else { return charge }
        let principal = entry.lines.filter { line in
            guard accounts[line.accountId]?.kind == .loan else { return false }
            if let assigned = loanCategories[line.accountId] { return assigned == categoryId }
            return charge != nil
        }.map(\.amount).sum(currency)
        guard charge != nil || !principal.isZero else { return nil }
        return (charge ?? .zero(currency)) + principal
    }

    /// Spending in a category over [start, end), loan payments in full (see `spending(of:on:loanCategories:)`)
    public func spending(on categoryId: UUID, from start: Date, to end: Date, loanCategories: [UUID: UUID] = [:]) -> Money {
        posted
            .filter { $0.date >= start && $0.date < end }
            .compactMap { spending(of: $0, on: categoryId, loanCategories: loanCategories) }
            .sum(currency)
    }

    public func netWorth(asOf: Date? = nil) -> NetWorth {
        var assets = Money.zero(currency)
        var liabilities = Money.zero(currency)
        var items: [BreakdownItem] = []
        for account in accounts.values.sorted(by: { $0.name < $1.name })
        where account.kind.isBalanceSheet && account.includeInNetWorth && !account.archived {
            let b = balance(of: account.id, asOf: asOf)
            if account.kind.isAsset { assets += b } else { liabilities += b.negated }
            if !b.isZero { items.append(BreakdownItem(label: account.name, amount: b, sourceIds: [account.id])) }
        }
        return NetWorth(assets: assets, liabilities: liabilities, items: items)
    }
}

public struct NetWorth: Equatable, Sendable {
    /// Everything owned in included accounts
    public let assets: Money
    /// Everything owed, as a positive amount
    public let liabilities: Money
    public let items: [BreakdownItem]

    public var total: Money { assets - liabilities }
}

/// One line of an explanation: a label, an amount and the records it came from
public struct BreakdownItem: Hashable, Sendable, Identifiable {
    public var id: String { label + sourceIds.map(\.uuidString).joined() }
    public let label: String
    public let amount: Money
    public let detail: String?
    public let sourceIds: [UUID]

    public init(label: String, amount: Money, detail: String? = nil, sourceIds: [UUID] = []) {
        self.label = label
        self.amount = amount
        self.detail = detail
        self.sourceIds = sourceIds
    }
}
