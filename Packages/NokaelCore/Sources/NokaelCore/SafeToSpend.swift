import Foundation

/// Money set aside in an account for a purpose (an emergency fund, a holiday).
/// It stays in the account: reserving never moves cash or counts it twice.
public struct Reserve: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var amount: Money
    public var accountId: UUID
    /// A savings goal's target, if this money is being saved towards something
    public var target: Money?
    public var targetDate: Date?

    public init(id: UUID = UUID(), name: String, amount: Money, accountId: UUID,
                target: Money? = nil, targetDate: Date? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.accountId = accountId
        self.target = target
        self.targetDate = targetDate
    }

    public var isGoal: Bool { target != nil }
}

/// A budget category whose remaining money should be kept out of safe-to-spend
public struct CategoryReservation: Hashable, Sendable {
    public let categoryId: UUID
    public let name: String
    public let remaining: Money

    public init(categoryId: UUID, name: String, remaining: Money) {
        self.categoryId = categoryId
        self.name = name
        self.remaining = remaining
    }
}

public enum SafeToSpendStatus: Hashable, Sendable {
    /// Every input is confirmed
    case reliable
    /// Includes estimated bills
    case estimated
    /// Not enough set up to calculate (no spendable account yet)
    case incompleteSetup
    /// Some spendable balances haven't been checked for a while
    case stale(accountNames: [String])
    /// Commitments exceed spendable money; not an overdraft, just nothing left to spend freely
    case shortfall
}

public struct SafeToSpend: Sendable {
    /// nil when setup is incomplete
    public let amount: Money?
    public let periodEnd: Date
    public let statuses: [SafeToSpendStatus]
    public let spendable: [BreakdownItem]
    public let obligations: [BreakdownItem]
    public let reserves: [BreakdownItem]
    public let categoryReservations: [BreakdownItem]
    public let buffer: Money

    public var spendableTotal: Money { spendable.map(\.amount).sum(buffer.currency) }
    public var obligationsTotal: Money { obligations.map(\.amount).sum(buffer.currency) }
    public var reservesTotal: Money { reserves.map(\.amount).sum(buffer.currency) }
    public var categoryReservationsTotal: Money { categoryReservations.map(\.amount).sum(buffer.currency) }

    public var isReliable: Bool { statuses == [.reliable] }
}

public struct Projection: Sendable {
    public let date: Date
    public let amount: Money
    public let expectedIncome: [BreakdownItem]
    public let obligations: [BreakdownItem]
    /// Plain-language assumptions the number depends on
    public let assumptions: [String]
}

public struct SafeToSpendCalculator: Sendable {
    public let ledger: Ledger
    public let items: [PlannedItem]
    public let occurrences: [Occurrence]
    public let reserves: [Reserve]
    public let categoryReservations: [CategoryReservation]
    public let buffer: Money
    /// When each account's balance was last confirmed (newest entry or reconciliation)
    public let lastConfirmed: [UUID: Date]
    public let staleAfterDays: Int
    public let calendar: Calendar

    public init(ledger: Ledger, items: [PlannedItem], occurrences: [Occurrence], reserves: [Reserve],
                categoryReservations: [CategoryReservation] = [], buffer: Money,
                lastConfirmed: [UUID: Date] = [:], staleAfterDays: Int = 30, calendar: Calendar) {
        self.ledger = ledger
        self.items = items
        self.occurrences = occurrences
        self.reserves = reserves
        self.categoryReservations = categoryReservations
        self.buffer = buffer
        self.lastConfirmed = lastConfirmed
        self.staleAfterDays = staleAfterDays
        self.calendar = calendar
    }

    private var currency: String { ledger.currency }

    private var spendableAccounts: [AccountInfo] {
        ledger.accounts.values
            .filter { $0.kind.isBalanceSheet && $0.spendable && !$0.archived }
            .sorted { $0.name < $1.name }
    }

    private func isSpendable(_ accountId: UUID?) -> Bool {
        guard let id = accountId else { return true } // unassigned bills are assumed paid from spendable money
        return spendableAccounts.contains { $0.id == id }
    }

    /// Safe to spend from `today` through `periodEnd`. Uses only posted balances:
    /// expected income never raises today's number. Bills are held back through
    /// `billsThrough` (default `periodEnd`), so one due on payday isn't left to luck.
    public func calculate(today: Date, periodEnd: Date, billsThrough: Date? = nil) -> SafeToSpend {
        let accounts = spendableAccounts
        guard !accounts.isEmpty else {
            return SafeToSpend(amount: nil, periodEnd: periodEnd, statuses: [.incompleteSetup], spendable: [],
                               obligations: [], reserves: [], categoryReservations: [], buffer: buffer)
        }

        // Posted balances already include every payment made, so nothing posted is subtracted again
        let spendable = accounts.map {
            BreakdownItem(label: $0.name, amount: ledger.balance(of: $0.id, asOf: today), sourceIds: [$0.id])
        }

        let due = dueOutflows(through: max(periodEnd, billsThrough ?? periodEnd))
        let obligations = due.map { pair in
            BreakdownItem(label: pair.item.name, amount: pair.occurrence.remaining,
                          detail: pair.occurrence.isEstimate ? "Estimate" : pair.occurrence.dueDate > periodEnd ? "Due on payday" : nil,
                          sourceIds: [pair.occurrence.id])
        }

        // A reserve only protects money that is still counted as spendable
        let reserved = reserves.filter { isSpendable($0.accountId) && $0.amount.isPositive }.map {
            BreakdownItem(label: $0.name, amount: $0.amount, sourceIds: [$0.id])
        }

        // Categories already covered by a bill in this period aren't reserved twice
        let billCategories = Set(due.compactMap { $0.item.categoryId })
        let categoryItems = categoryReservations
            .filter { !billCategories.contains($0.categoryId) && $0.remaining.isPositive }
            .map { BreakdownItem(label: $0.name, amount: $0.remaining, sourceIds: [$0.categoryId]) }

        let amount = spendable.map(\.amount).sum(currency)
            - obligations.map(\.amount).sum(currency)
            - reserved.map(\.amount).sum(currency)
            - categoryItems.map(\.amount).sum(currency)
            - buffer

        var statuses: [SafeToSpendStatus] = []
        let staleNames = accounts.filter { account in
            guard let last = lastConfirmed[account.id] else { return true }
            return (calendar.dateComponents([.day], from: last, to: today).day ?? 0) > staleAfterDays
        }.map(\.name)
        if !staleNames.isEmpty { statuses.append(.stale(accountNames: staleNames)) }
        if due.contains(where: { $0.occurrence.isEstimate }) { statuses.append(.estimated) }
        if amount.isNegative { statuses.append(.shortfall) }
        if statuses.isEmpty { statuses = [.reliable] }

        return SafeToSpend(amount: amount, periodEnd: periodEnd, statuses: statuses, spendable: spendable,
                           obligations: obligations, reserves: reserved, categoryReservations: categoryItems, buffer: buffer)
    }

    /// A projection for a future date. Clearly separate from today's number:
    /// expected income is included only here, and every assumption is listed.
    public func project(today: Date, to date: Date) -> Projection {
        let base = calculate(today: today, periodEnd: date)
        let income = occurrences
            .filter { occ in
                guard let item = items.first(where: { $0.id == occ.itemId }), item.direction == .inflow else { return false }
                return occ.dueDate <= date && !occ.remaining.isZero && !occ.skipped && isSpendable(item.accountId)
            }
            .sorted { $0.dueDate < $1.dueDate }
        let incomeItems = income.map { occ in
            BreakdownItem(label: items.first { $0.id == occ.itemId }?.name ?? "Expected income",
                          amount: occ.remaining, detail: "Expected", sourceIds: [occ.id])
        }
        var assumptions = ["Expected income arrives in full on its date", "Bills are paid at their scheduled amounts"]
        if base.obligations.contains(where: { $0.detail == "Estimate" }) { assumptions.append("Some bills are estimates") }
        let amount = (base.amount ?? .zero(currency)) + incomeItems.map(\.amount).sum(currency)
        return Projection(date: date, amount: amount, expectedIncome: incomeItems, obligations: base.obligations,
                          assumptions: assumptions)
    }

    /// Unpaid outflows due by `periodEnd` (overdue included), paid from spendable money
    private func dueOutflows(through periodEnd: Date) -> [(item: PlannedItem, occurrence: Occurrence)] {
        occurrences.compactMap { occ in
            guard let item = items.first(where: { $0.id == occ.itemId }),
                  item.direction == .outflow,
                  !occ.skipped, !occ.remaining.isZero,
                  occ.dueDate <= periodEnd,
                  isSpendable(item.accountId) else { return nil }
            return (item, occ)
        }
        .sorted { $0.occurrence.dueDate < $1.occurrence.dueDate }
    }
}
