//
//  TransactionRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

class TransactionRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var transactions: [Transaction] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadTransactions()
    }
    
    func loadTransactions(limit: Int = 100) {
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
            try localDB.insert(transaction)
            loadTransactions()
            
            // Update account balance
            updateAccountBalance(for: transaction)
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateTransaction(_ transaction: Transaction) {
        do {
            transaction.updatedAt = Date()
            transaction.syncStatus = "pending"
            try localDB.save()
            loadTransactions()
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        do {
            // Reverse account balance change
            reverseAccountBalance(for: transaction)
            
            try localDB.delete(transaction)
            loadTransactions()
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func updateAccountBalance(for transaction: Transaction) {
        do {
            if let account = try localDB.fetchAccount(by: transaction.accountId) {
                switch transaction.type {
                case .income:
                    account.balance += transaction.amount
                case .expense:
                    account.balance -= transaction.amount
                case .transfer:
                    // Handle transfer logic if needed
                    break
                }
                account.updatedAt = Date()
                account.syncStatus = "pending"
                try localDB.save()
            }
        } catch {
            print("Error updating account balance: \(error)")
        }
    }
    
    private func reverseAccountBalance(for transaction: Transaction) {
        do {
            if let account = try localDB.fetchAccount(by: transaction.accountId) {
                switch transaction.type {
                case .income:
                    account.balance -= transaction.amount
                case .expense:
                    account.balance += transaction.amount
                case .transfer:
                    // Handle transfer logic if needed
                    break
                }
                account.updatedAt = Date()
                account.syncStatus = "pending"
                try localDB.save()
            }
        } catch {
            print("Error reversing account balance: \(error)")
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