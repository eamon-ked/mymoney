import Foundation

/// Calendar months as "yyyy-MM" keys in the user's time zone
public enum BudgetMonth {
    public static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    public static func start(of key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    public static func end(of key: String, calendar: Calendar) -> Date? {
        guard let s = start(of: key, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: s)
    }

    public static func adding(_ months: Int, to key: String, calendar: Calendar) -> String {
        guard let s = start(of: key, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: s) else { return key }
        return self.key(for: moved, calendar: calendar)
    }
}

/// What happens to a category's leftover money at the end of a month
public enum RolloverPolicy: String, Codable, Sendable, CaseIterable {
    /// Unspent money stays in the category. Overspending doesn't follow it: that money is
    /// already gone from the accounts, so it lowers what's left to plan instead.
    case rollover
    /// Each month starts fresh; leftovers and overspending go back to Available to allocate
    case reset

    public var label: String {
        switch self {
        case .rollover: return "Roll over to next month"
        case .reset: return "Start fresh each month"
        }
    }
}

public struct BudgetCategory: Hashable, Codable, Sendable, Identifiable {
    /// The expense category's ledger account id
    public let id: UUID
    public var name: String
    public var group: String
    public var policy: RolloverPolicy

    public init(id: UUID, name: String, group: String, policy: RolloverPolicy = .rollover) {
        self.id = id
        self.name = name
        self.group = group
        self.policy = policy
    }
}

/// Money planned for a category in a month. A plan, never an account transaction.
public struct Allocation: Hashable, Codable, Sendable {
    public var categoryId: UUID
    public var month: String
    public var amount: Money

    public init(categoryId: UUID, month: String, amount: Money) {
        self.categoryId = categoryId
        self.month = month
        self.amount = amount
    }
}

/// A bill's due date in a month, counted as planned for its category whether or not it's paid yet
public struct BudgetBill: Hashable, Sendable {
    public var categoryId: UUID
    public var month: String
    /// What the bill is for: the larger of expected and paid
    public var amount: Money
    /// What's still to pay
    public var unpaid: Money

    public init(categoryId: UUID, month: String, amount: Money, unpaid: Money) {
        self.categoryId = categoryId
        self.month = month
        self.amount = amount
        self.unpaid = unpaid
    }
}

public struct CategoryLine: Equatable, Sendable {
    /// Planned for this month by hand
    public let allocated: Money
    /// Planned automatically so this month's bills are covered, on top of what was planned by hand
    public let fromBills: Money
    /// Bills due this month that aren't paid yet: planned, but not yet spent
    public let unpaidBills: Money
    /// Net spending this month, positive
    public let spent: Money
    /// Brought forward from earlier months (rollover policy only)
    public let carriedIn: Money
    /// What can still be spent this month; negative means overspent
    public let remaining: Money

    public var isOverspent: Bool { remaining.isNegative }
    /// Everything planned: by hand, carried in, and for bills
    public var planned: Money { allocated + carriedIn + fromBills }
    /// What's left of what was planned by hand. Safe to spend holds bills back as bills instead.
    public var withoutBills: Money { remaining - fromBills }
}

public enum BudgetError: Error, Equatable, Sendable {
    case amountMustBePositive
    case sameCategory
    /// Moving more than the source has left; the user must confirm or lower it
    case exceedsAvailable(available: Money)
}

/// YNAB-style plan over the ledger. The core identity:
/// Available to allocate = money in budget accounts − money still set aside in categories − future allocations.
/// Transfers, refunds and uncategorised movements are therefore handled by the ledger itself.
public struct Budget: Sendable {
    public let ledger: Ledger
    public let categories: [BudgetCategory]
    public let allocations: [Allocation]
    public let calendar: Calendar
    /// Money saved towards goals (and other set-asides) inside budget accounts.
    /// It already has a job, so it isn't available to plan again.
    public let saved: Money
    /// Bills due each month. A category is always planned at least enough to cover them.
    public let bills: [BudgetBill]
    /// Which spending category each loan's payments belong to (loan id to category id)
    public let loanCategories: [UUID: UUID]

    public init(ledger: Ledger, categories: [BudgetCategory], allocations: [Allocation], calendar: Calendar,
                saved: Money? = nil, bills: [BudgetBill] = [], loanCategories: [UUID: UUID] = [:]) {
        self.ledger = ledger
        self.loanCategories = loanCategories
        self.categories = categories
        self.allocations = allocations
        self.calendar = calendar
        self.saved = saved ?? .zero(ledger.currency)
        self.bills = bills
    }

    private var currency: String { ledger.currency }

    private var budgetAccountIds: Set<UUID> {
        Set(ledger.accounts.values.filter { $0.kind.isBalanceSheet && $0.onBudget }.map(\.id))
    }

    /// The accounts whose money can still be given a job. An archived account is out of sight in every
    /// total, so its money can't be handed out here either; what was spent from it still counts.
    private var heldAccountIds: Set<UUID> {
        Set(ledger.accounts.values.filter { $0.kind.isBalanceSheet && $0.onBudget && !$0.archived }.map(\.id))
    }

    /// Spending in a category during a month, counting only money from budget accounts, or a bill
    /// a friend paid for you (what you owe them is still your spending).
    /// A loan instalment counts in full against its loan's category: the part that
    /// paid the loan down left the budget too, so it can't still be "left" to spend.
    public func spent(_ categoryId: UUID, month: String) -> Money {
        guard let start = BudgetMonth.start(of: month, calendar: calendar),
              let end = BudgetMonth.end(of: month, calendar: calendar) else { return .zero(currency) }
        let ids = budgetAccountIds.union(ledger.accounts.values.filter { $0.kind == .lent }.map(\.id))
        return ledger.posted
            .filter { $0.date >= start && $0.date < end && $0.lines.contains { ids.contains($0.accountId) } }
            .compactMap { ledger.spending(of: $0, on: categoryId, loanCategories: loanCategories) }
            .sum(currency)
    }

    public func allocated(_ categoryId: UUID, month: String) -> Money {
        allocations.filter { $0.categoryId == categoryId && $0.month == month }.map(\.amount).sum(currency)
    }

    public func line(_ categoryId: UUID, month: String) -> CategoryLine {
        let categoryBills = bills.filter { $0.categoryId == categoryId }
        let policy = categories.first { $0.id == categoryId }?.policy ?? .rollover
        var carried = Money.zero(currency)
        if policy == .rollover {
            // In order, since what a month's bills add depends on what was carried into it
            let earlierMonths = Set(allocations.filter { $0.categoryId == categoryId && $0.month < month }.map(\.month))
                .union(spendingMonths(categoryId).filter { $0 < month })
                .union(categoryBills.map(\.month).filter { $0 < month })
            for m in earlierMonths.sorted() {
                let base = carried + allocated(categoryId, month: m)
                let left = base + billTopUp(categoryBills, month: m, base: base) - spent(categoryId, month: m)
                carried = Money.max(left, .zero(currency))
            }
        }
        let allocatedNow = allocated(categoryId, month: month)
        let spentNow = spent(categoryId, month: month)
        let base = carried + allocatedNow
        let topUp = billTopUp(categoryBills, month: month, base: base)
        return CategoryLine(allocated: allocatedNow, fromBills: topUp,
                            unpaidBills: categoryBills.filter { $0.month == month }.map(\.unpaid).sum(currency),
                            spent: spentNow, carriedIn: carried, remaining: base + topUp - spentNow)
    }

    /// What a month's bills need beyond what's already planned for the category
    private func billTopUp(_ categoryBills: [BudgetBill], month: String, base: Money) -> Money {
        let due = categoryBills.filter { $0.month == month }.map(\.amount).sum(currency)
        return Money.max(due - Money.max(base, .zero(currency)), .zero(currency))
    }

    /// Money not yet given a job, as of the month on screen. Negative means more
    /// is planned than the budget accounts hold.
    public func availableToAllocate(month: String) -> Money {
        guard let end = BudgetMonth.end(of: month, calendar: calendar) else { return .zero(currency) }
        let held = heldAccountIds.map { ledger.balance(of: $0, asOf: end.addingTimeInterval(-0.001)) }.sum(currency)
        // Only what's still left in categories is set aside. Overspending is already gone from
        // the accounts, so counting it here as a negative would add spent money back as unplanned.
        let setAside = categories.map { line($0.id, month: month).remaining }.filter(\.isPositive).sum(currency)
        let future = allocations.filter { $0.month > month }.map(\.amount).sum(currency)
        return held - setAside - future - saved
    }

    /// Total allocated this month, and the share of this month's planning funds it represents
    public func allocationProgress(month: String) -> (allocated: Money, planningFunds: Money, fraction: Double) {
        let allocatedNow = allocations.filter { $0.month == month }.map(\.amount).sum(currency)
        // Saved money and bills count as planned: they have a job
        let forBills = categories.map { line($0.id, month: month).fromBills }.sum(currency)
        let planned = allocatedNow + forBills + saved
        let funds = planned + availableToAllocate(month: month)
        let fraction = funds.isPositive ? Double(planned.minorUnits) / Double(funds.minorUnits) : 0
        return (allocatedNow, funds, min(max(fraction, 0), 1))
    }

    /// The two allocation changes that move money between categories. Totals
    /// are conserved. Moving more than the source has left throws unless `allowOverdraw`.
    public func move(_ amount: Money, from source: UUID, to destination: UUID, month: String,
                     allowOverdraw: Bool = false) throws -> [Allocation] {
        guard amount.isPositive else { throw BudgetError.amountMustBePositive }
        guard source != destination else { throw BudgetError.sameCategory }
        let available = line(source, month: month).remaining
        if amount > available && !allowOverdraw { throw BudgetError.exceedsAvailable(available: available) }
        return [Allocation(categoryId: source, month: month, amount: amount.negated),
                Allocation(categoryId: destination, month: month, amount: amount)]
    }

    /// Allocations to start a month with last month's plan
    public func copyPlan(from previous: String, to month: String) -> [Allocation] {
        categories.compactMap { c in
            let amount = allocated(c.id, month: previous)
            guard amount.isPositive, allocated(c.id, month: month).isZero else { return nil }
            return Allocation(categoryId: c.id, month: month, amount: amount)
        }
    }

    private func spendingMonths(_ categoryId: UUID) -> Set<String> {
        Set(ledger.posted.filter { $0.touches(categoryId) }.map { BudgetMonth.key(for: $0.date, calendar: calendar) })
    }
}
