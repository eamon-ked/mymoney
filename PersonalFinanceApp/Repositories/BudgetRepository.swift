//
//  BudgetRepository.swift
//  PersonalFinanceApp
//
//  Local-only for now: CategoryBudget rows are marked "pending" so they can be
//  pushed once budget sync is added.
//

import Foundation
import Combine

@MainActor
class BudgetRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared

    static let payFirstPercentKey = "payFirstPercent"
    static let defaultPayFirstPercent: Decimal = 10

    @Published var month: String = BudgetMonth.key(for: Date())
    @Published private(set) var categories: [Category] = []
    @Published private(set) var calculator = BudgetCalculator(accounts: [], entries: [], assignments: [])
    @Published var error: String?

    init() {
        reload()
    }

    func reload() {
        do {
            categories = try localDB.fetchCategories().filter { $0.type == .expense }
            let budgetCategoryIds = Set(categories.map(\.id))

            let accounts = try localDB.fetchAccounts().map {
                BudgetCalculator.AccountInfo(id: $0.id, openingBalance: $0.openingBalance, onBudget: $0.onBudget)
            }
            let entries = try localDB.fetchAllActiveTransactions().map { t in
                BudgetCalculator.Entry(
                    accountId: t.accountId,
                    transferAccountId: t.transferAccountId,
                    // Only expense categories hold budget; anything else counts as uncategorised
                    categoryId: t.categoryId.flatMap { budgetCategoryIds.contains($0) ? $0 : nil },
                    amount: t.amount,
                    type: t.type,
                    month: BudgetMonth.key(for: t.transactionDate))
            }
            let assignments = try localDB.fetchCategoryBudgets().map {
                BudgetCalculator.Assignment(categoryId: $0.categoryId, month: $0.month, assigned: $0.assigned)
            }
            calculator = BudgetCalculator(accounts: accounts, entries: entries, assignments: assignments)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Derived numbers for the month on screen

    var readyToAssign: Decimal { calculator.readyToAssign(through: month) }

    func line(for category: Category) -> BudgetCalculator.CategoryLine {
        calculator.line(for: category.id, month: month)
    }

    func needed(for category: Category) -> Decimal {
        calculator.neededThisMonth(target: category.monthlyTarget, line: line(for: category))
    }

    // MARK: - Month navigation

    func previousMonth() { month = BudgetMonth.adding(-1, to: month) }
    func nextMonth() { month = BudgetMonth.adding(1, to: month) }

    // MARK: - Writes

    func setAssigned(_ amount: Decimal, for category: Category, month: String? = nil) {
        do {
            try writeAssigned(category.id, month: month ?? self.month) { _ in amount }
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Moves assigned money between categories in the month on screen; this is
    /// how overspending gets covered.
    func move(_ amount: Decimal, from source: Category, to destination: Category) {
        guard amount > 0, source.id != destination.id else { return }
        do {
            try writeAssigned(source.id, month: month) { $0 - amount }
            try writeAssigned(destination.id, month: month) { $0 + amount }
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Pay yourself first

    var payFirstCategory: Category? {
        categories.first { $0.isPayFirst }
    }

    static var payFirstPercent: Decimal {
        if let s = UserDefaults.standard.string(forKey: payFirstPercentKey), let d = Decimal(string: s) { return d }
        return defaultPayFirstPercent
    }

    /// Suggested savings for an income amount, rounded to 2 places
    static func suggestedPayFirst(for income: Decimal) -> Decimal {
        var raw = income * payFirstPercent / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }

    /// Adds the amount to the pay-first category in the month the income landed
    func assignPayFirst(_ amount: Decimal, incomeDate: Date) {
        guard amount > 0, let category = payFirstCategory else { return }
        do {
            try writeAssigned(category.id, month: BudgetMonth.key(for: incomeDate)) { $0 + amount }
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setPayFirst(_ category: Category?) {
        do {
            for c in categories {
                let shouldBe = (c.id == category?.id)
                if c.isPayFirst != shouldBe {
                    c.isPayFirst = shouldBe
                    c.syncStatus = "pending"
                }
            }
            try localDB.save()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setTarget(_ target: Decimal?, for category: Category) {
        do {
            category.monthlyTarget = (target ?? 0) > 0 ? target : nil
            category.syncStatus = "pending"
            try localDB.save()
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func writeAssigned(_ categoryId: UUID, month: String, _ change: (Decimal) -> Decimal) throws {
        if let row = try localDB.fetchCategoryBudget(categoryId: categoryId, month: month) {
            row.assigned = change(row.assigned)
            row.updatedAt = Date()
            row.syncStatus = "pending"
            try localDB.save()
        } else {
            try localDB.insert(CategoryBudget(categoryId: categoryId, month: month, assigned: change(0)))
        }
    }
}
