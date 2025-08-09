//
//  LocalDatabaseManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

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
            PrivateLoan.self
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
    
    func fetchPendingSyncAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Transaction Operations
    
    func fetchTransactions(limit: Int = 100) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)],
            fetchLimit: limit
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchTransactions(for accountId: UUID) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.accountId == accountId },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncTransactions() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Category Operations
    
    func fetchCategories() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncCategories() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Goal Operations
    
    func fetchGoals() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncGoals() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Private Loan Operations
    
    func fetchPrivateLoans() throws -> [PrivateLoan] {
        let descriptor = FetchDescriptor<PrivateLoan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchPendingSyncPrivateLoans() throws -> [PrivateLoan] {
        let descriptor = FetchDescriptor<PrivateLoan>(
            predicate: #Predicate { $0.syncStatus == "pending" }
        )
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
}