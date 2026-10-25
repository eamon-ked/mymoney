//
//  AccountRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

@MainActor
class AccountRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadAccounts()
    }
    
    func loadAccounts() {
        isLoading = true
        error = nil
        
        do {
            accounts = try localDB.fetchAccounts()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // Called after a remote pull to ensure local cache is fresh
    func reloadFromLocalStore() {
        do { accounts = try localDB.fetchAccounts() } catch { }
    }
    
    func addAccount(_ account: Account) {
        do {
            try localDB.insert(account)
            loadAccounts()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateAccount(_ account: Account) {
        do {
            account.updatedAt = Date()
            account.syncStatus = "pending"
            try localDB.save()
            loadAccounts()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Soft-deletes the account and its own income and expenses. Transfers with
    /// other accounts stay, so those accounts' balances don't change.
    func deleteAccount(_ account: Account) {
        do {
            let now = Date()
            account.deletedAt = now
            account.updatedAt = now
            account.syncStatus = "pending"
            for t in try localDB.fetchAllActiveTransactions()
            where t.accountId == account.id && t.type != .transfer {
                t.deletedAt = now
                t.updatedAt = now
                t.syncStatus = "pending"
            }
            try localDB.save()
            loadAccounts()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// How many of the account's own transactions a delete would remove
    func ownTransactionCount(for account: Account) -> Int {
        let rows = (try? localDB.fetchAllActiveTransactions()) ?? []
        return rows.filter { $0.accountId == account.id && $0.type != .transfer }.count
    }
    
    /// For cards saved with the amount owed as a positive number: shows the same
    /// amount as owed (negative) from now on, keeping every transaction.
    func flipCardBalance(_ account: Account) {
        do {
            let target = -account.balance
            account.openingBalance = target - (try localDB.transactionTotal(for: account.id))
            account.balanceConfirmedAt = Date()
            try localDB.recalculateBalance(for: account.id)
            updateAccount(account)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func getAccount(by id: UUID) -> Account? {
        return accounts.first { $0.id == id }
    }
    
    func getTotalBalance() -> Decimal {
        return accounts.reduce(0) { total, account in
            if account.type == .creditCard {
                return total - account.balance
            } else {
                return total + account.balance
            }
        }
    }
    
    func getAccountsByType(_ type: AccountType) -> [Account] {
        return accounts.filter { $0.type == type }
    }
}