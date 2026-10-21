//
//  LocalDatabaseManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

@MainActor
class LocalDatabaseManager: ObservableObject {
    static let shared = LocalDatabaseManager()
    
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    private init() {
        let schema = Schema([
            UserProfile.self,
            Account.self,
            Category.self,
            Transaction.self,
            Goal.self,
            PrivateLoan.self,
            CategoryBudget.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        captureLegacyOpeningBalances()
    }
    
    /// Runs once after upgrading from v1.0, before anything recomputes a balance:
    /// sets each account's opening balance so its computed balance equals the
    /// stored one, preserving today's number until the user confirms it.
    private func captureLegacyOpeningBalances() {
        let key = "legacyBalancesCaptured_v11"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            for account in try fetchAccounts() where account.balanceConfirmedAt == nil {
                account.openingBalance = account.balance - (try transactionTotal(for: account.id))
            }
            try save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            print("Error capturing legacy balances: \(error)")
        }
    }
    
    var context: ModelContext {
        return modelContext
    }
    
    // MARK: - Generic Operations
    
    func save() throws {
        try modelContext.save()
    }
    
    func insert<T: PersistentModel>(_ model: T) throws {
        modelContext.insert(model)
        try save()
    }
    
    func delete<T: PersistentModel>(_ model: T) throws {
        modelContext.delete(model)
        try save()
    }
    
    // MARK: - Account Operations
    
    func fetchAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchAccount(by id: UUID) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchTransaction(by id: UUID) throws -> Transaction? {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchCategory(by id: UUID) throws -> Category? {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchGoal(by id: UUID) throws -> Goal? {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchPrivateLoan(by id: UUID) throws -> PrivateLoan? {
        let descriptor = FetchDescriptor<PrivateLoan>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    func fetchPendingSyncAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - User Profile Operations
    func fetchUserProfiles() throws -> [UserProfile] {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchUserProfile() throws -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Transaction Operations
    
    func fetchTransactions(limit: Int = 100) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = 0
        return try modelContext.fetch(descriptor)
    }
    
    func fetchTransactions(for accountId: UUID) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.accountId == accountId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Balances
    
    /// The only place Account.balance is written: opening balance plus every
    /// non-deleted transaction, recomputed from scratch with no fetch limit.
    func recalculateBalance(for accountId: UUID) throws {
        guard let account = try fetchAccount(by: accountId) else { return }
        account.balance = try computedBalance(for: account)
        try save()
    }
    
    func recalculateAllBalances() throws {
        for account in try fetchAccounts() {
            account.balance = try computedBalance(for: account)
        }
        try save()
    }
    
    /// Sum of an account's non-deleted transactions, excluding its opening balance.
    func transactionTotal(for accountId: UUID) throws -> Decimal {
        let optionalId: UUID? = accountId   // #Predicate needs matching optionality
        let outgoing = try modelContext.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.accountId == accountId && $0.deletedAt == nil }))
        let incoming = try modelContext.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.transferAccountId == optionalId && $0.deletedAt == nil }))
        
        var total: Decimal = 0
        for t in outgoing {
            switch t.type {
            case .income:   total += t.amount
            case .expense:  total -= t.amount
            case .transfer:
                // Transfers saved before v1.1 have no destination and stay neutral
                if t.transferAccountId != nil { total -= t.amount }
            }
        }
        for t in incoming where t.type == .transfer { total += t.amount }
        return total
    }
    
    private func computedBalance(for account: Account) throws -> Decimal {
        account.openingBalance + (try transactionTotal(for: account.id))
    }
    
    func fetchPendingSyncTransactions() throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        descriptor.fetchLimit = 100 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    /// Every non-deleted transaction, unlimited; for budget math only
    func fetchAllActiveTransactions() throws -> [Transaction] {
        try modelContext.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil }))
    }
    
    // MARK: - Budget Operations
    
    func fetchCategoryBudgets() throws -> [CategoryBudget] {
        try modelContext.fetch(FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.deletedAt == nil }))
    }
    
    func fetchCategoryBudget(categoryId: UUID, month: String) throws -> CategoryBudget? {
        try modelContext.fetch(FetchDescriptor<CategoryBudget>(
            predicate: #Predicate { $0.categoryId == categoryId && $0.month == month && $0.deletedAt == nil })).first
    }
    
    // MARK: - Category Operations
    
    func fetchCategories() throws -> [Category] {
        var descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 200 // Reasonable limit for categories
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncCategories() throws -> [Category] {
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        descriptor.fetchLimit = 50 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Goal Operations
    
    func fetchGoals() throws -> [Goal] {
        var descriptor = FetchDescriptor<Goal>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncGoals() throws -> [Goal] {
        var descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        descriptor.fetchLimit = 50 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Private Loan Operations
    
    func fetchPrivateLoans() throws -> [PrivateLoan] {
        var descriptor = FetchDescriptor<PrivateLoan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncPrivateLoans() throws -> [PrivateLoan] {
        var descriptor = FetchDescriptor<PrivateLoan>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        descriptor.fetchLimit = 50 // Limit for performance
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Sync Status Updates
    
    func updateSyncStatus<T: PersistentModel>(for model: T, status: String, lastSyncedAt: Date = Date()) throws {
        if let account = model as? Account {
            account.syncStatus = status
            account.lastSyncedAt = lastSyncedAt
        } else if let transaction = model as? Transaction {
            transaction.syncStatus = status
            transaction.lastSyncedAt = lastSyncedAt
        } else if let category = model as? Category {
            category.syncStatus = status
            category.lastSyncedAt = lastSyncedAt
        } else if let goal = model as? Goal {
            goal.syncStatus = status
            goal.lastSyncedAt = lastSyncedAt
        } else if let loan = model as? PrivateLoan {
            loan.syncStatus = status
            loan.lastSyncedAt = lastSyncedAt
        }
        try save()
    }

    // MARK: - Destructive Operations
    func wipeAllData() throws {
        // Delete in dependency order to avoid relationship constraints
        let allTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        allTransactions.forEach { modelContext.delete($0) }

        let allGoals = try modelContext.fetch(FetchDescriptor<Goal>())
        allGoals.forEach { modelContext.delete($0) }

        let allCategories = try modelContext.fetch(FetchDescriptor<Category>())
        allCategories.forEach { modelContext.delete($0) }

        let allLoans = try modelContext.fetch(FetchDescriptor<PrivateLoan>())
        allLoans.forEach { modelContext.delete($0) }

        let allAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        allAccounts.forEach { modelContext.delete($0) }

        let allProfiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        allProfiles.forEach { modelContext.delete($0) }

        try save()
    }
}