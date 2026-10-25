//
//  TransactionRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

@MainActor
class TransactionRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var transactions: [Transaction] = []
    @Published var isLoading = false
    @Published var error: String?
    
    /// Repeats whichever load the screen asked for last, so a write never
    /// swaps one account's history for the full list or shrinks the list
    private var reloadCurrent: (() -> Void)?
    
    init() {
        loadTransactions()
    }
    
    func loadTransactions(limit: Int = 100) {
        reloadCurrent = { [weak self] in self?.loadTransactions(limit: limit) }
        isLoading = true
        error = nil
        
        do {
            transactions = try localDB.fetchTransactions(limit: limit)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func loadTransactions(for accountId: UUID) {
        reloadCurrent = { [weak self] in self?.loadTransactions(for: accountId) }
        isLoading = true
        error = nil
        
        do {
            transactions = try localDB.fetchTransactions(for: accountId)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        do {
            if let categoryId = transaction.categoryId {
                transaction.category = try localDB.fetchCategory(by: categoryId)
            }
            try localDB.insert(transaction)
            try refreshBalances(transaction.accountId, transaction.transferAccountId)
            reload()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Pass the account IDs as they were BEFORE the edit, so a transaction
    /// moved between accounts fixes both the old and the new account.
    func updateTransaction(_ transaction: Transaction, previousAccountId: UUID, previousTransferAccountId: UUID?) {
        do {
            transaction.updatedAt = Date()
            transaction.syncStatus = "pending"
            transaction.category = try transaction.categoryId.flatMap { try localDB.fetchCategory(by: $0) }
            try localDB.save()
            try refreshBalances(previousAccountId, previousTransferAccountId,
                                transaction.accountId, transaction.transferAccountId)
            reload()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        do {
            // Soft delete so the delete reaches other devices; never localDB.delete
            transaction.deletedAt = Date()
            transaction.updatedAt = Date()
            transaction.syncStatus = "pending"
            try localDB.save()
            try refreshBalances(transaction.accountId, transaction.transferAccountId)
            reload()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func reload() {
        if let reloadCurrent { reloadCurrent() } else { loadTransactions() }
    }
    
    private func refreshBalances(_ ids: UUID?...) throws {
        for id in Set(ids.compactMap { $0 }) {
            try localDB.recalculateBalance(for: id)
        }
    }
    
    func getRecentTransactions(limit: Int = 10) -> [Transaction] {
        return Array(transactions.prefix(limit))
    }
    
    func getTransactionsByType(_ type: TransactionType) -> [Transaction] {
        return transactions.filter { $0.type == type }
    }
    
    func getTransactionsForDateRange(from startDate: Date, to endDate: Date) -> [Transaction] {
        return transactions.filter { transaction in
            transaction.transactionDate >= startDate && transaction.transactionDate <= endDate
        }
    }
    
    func getTotalIncome(for period: DateInterval) -> Decimal {
        return getTransactionsForDateRange(from: period.start, to: period.end)
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }
    
    func getTotalExpenses(for period: DateInterval) -> Decimal {
        return getTransactionsForDateRange(from: period.start, to: period.end)
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
}