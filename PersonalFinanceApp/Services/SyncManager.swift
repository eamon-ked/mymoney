//
//  SyncManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    private let supabaseManager = SupabaseManager.shared
    private let localDB = LocalDatabaseManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private let syncQueue = DispatchQueue(label: "sync.queue", qos: .background)
    private var syncTimer: Timer?
    
    private init() {
        setupPeriodicSync()
        loadLastSyncDate()
    }
    
    private func setupPeriodicSync() {
        // Sync every 5 minutes when app is active
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await self.performSync()
            }
        }
    }
    
    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    private func saveLastSyncDate() {
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }
    
    // MARK: - Public Sync Methods
    
    func performSync() async {
        guard supabaseManager.isAuthenticated else { return }
        
        await MainActor.run {
            isSyncing = true
            syncError = nil
        }
        
        do {
            // Push local changes first
            try await pushLocalChanges()
            
            // Then pull remote changes
            try await pullRemoteChanges()
            
            await MainActor.run {
                self.lastSyncDate = Date()
                self.saveLastSyncDate()
                self.isSyncing = false
            }
        } catch {
            await MainActor.run {
                self.syncError = error.localizedDescription
                self.isSyncing = false
            }
        }
    }
    
    func forceSyncNow() async {
        await performSync()
    }
    
    // MARK: - Push Local Changes
    
    private func pushLocalChanges() async throws {
        try await pushAccounts()
        try await pushCategories()
        try await pushTransactions()
        try await pushGoals()
        try await pushPrivateLoans()
    }
    
    private func pushAccounts() async throws {
        let pendingAccounts = try localDB.fetchPendingSyncAccounts()
        
        for account in pendingAccounts {
            let accountData: [String: Any] = [
                "id": account.id.uuidString,
                "user_id": account.userId?.uuidString ?? supabaseManager.currentUser?.id.uuidString ?? "",
                "name": account.name,
                "type": account.type.rawValue,
                "balance": NSDecimalNumber(decimal: account.balance).doubleValue,
                "currency": account.currency,
                "account_number": account.accountNumber ?? NSNull(),
                "institution_name": account.institutionName ?? NSNull(),
                "color": account.color,
                "is_active": account.isActive,
                "created_at": ISO8601DateFormatter().string(from: account.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: account.updatedAt)
            ]
            
            try await supabaseManager.upsertAccount(accountData)
            try localDB.updateSyncStatus(for: account, status: "synced")
        }
    }
    
    private func pushCategories() async throws {
        let pendingCategories = try localDB.fetchPendingSyncCategories()
        
        for category in pendingCategories {
            let categoryData: [String: Any] = [
                "id": category.id.uuidString,
                "user_id": category.userId?.uuidString ?? supabaseManager.currentUser?.id.uuidString ?? "",
                "name": category.name,
                "type": category.type.rawValue,
                "color": category.color,
                "icon": category.icon,
                "is_default": category.isDefault,
                "created_at": ISO8601DateFormatter().string(from: category.createdAt)
            ]
            
            try await supabaseManager.upsertCategory(categoryData)
            try localDB.updateSyncStatus(for: category, status: "synced")
        }
    }
    
    private func pushTransactions() async throws {
        let pendingTransactions = try localDB.fetchPendingSyncTransactions()
        
        for transaction in pendingTransactions {
            let transactionData: [String: Any] = [
                "id": transaction.id.uuidString,
                "user_id": transaction.userId?.uuidString ?? supabaseManager.currentUser?.id.uuidString ?? "",
                "account_id": transaction.accountId.uuidString,
                "category_id": transaction.categoryId?.uuidString ?? NSNull(),
                "amount": NSDecimalNumber(decimal: transaction.amount).doubleValue,
                "type": transaction.type.rawValue,
                "description": transaction.transactionDescription,
                "notes": transaction.notes ?? NSNull(),
                "transaction_date": ISO8601DateFormatter().string(from: transaction.transactionDate),
                "is_recurring": transaction.isRecurring,
                "recurring_frequency": transaction.recurringFrequency ?? NSNull(),
                "tags": transaction.tags,
                "created_at": ISO8601DateFormatter().string(from: transaction.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: transaction.updatedAt)
            ]
            
            try await supabaseManager.upsertTransaction(transactionData)
            try localDB.updateSyncStatus(for: transaction, status: "synced")
        }
    }
    
    private func pushGoals() async throws {
        let pendingGoals = try localDB.fetchPendingSyncGoals()
        
        for goal in pendingGoals {
            let goalData: [String: Any] = [
                "id": goal.id.uuidString,
                "user_id": goal.userId?.uuidString ?? supabaseManager.currentUser?.id.uuidString ?? "",
                "title": goal.title,
                "description": goal.goalDescription ?? NSNull(),
                "target_amount": NSDecimalNumber(decimal: goal.targetAmount).doubleValue,
                "current_amount": NSDecimalNumber(decimal: goal.currentAmount).doubleValue,
                "target_date": goal.targetDate != nil ? ISO8601DateFormatter().string(from: goal.targetDate!) : NSNull(),
                "category": goal.category ?? NSNull(),
                "priority": goal.priority ?? NSNull(),
                "status": goal.status,
                "created_at": ISO8601DateFormatter().string(from: goal.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: goal.updatedAt)
            ]
            
            try await supabaseManager.upsertGoal(goalData)
            try localDB.updateSyncStatus(for: goal, status: "synced")
        }
    }
    
    private func pushPrivateLoans() async throws {
        let pendingLoans = try localDB.fetchPendingSyncPrivateLoans()
        
        for loan in pendingLoans {
            let loanData: [String: Any] = [
                "id": loan.id.uuidString,
                "user_id": loan.userId?.uuidString ?? supabaseManager.currentUser?.id.uuidString ?? "",
                "loan_name": loan.loanName,
                "loan_type": loan.loanType ?? NSNull(),
                "lender_name": loan.lenderName ?? NSNull(),
                "original_amount": NSDecimalNumber(decimal: loan.originalAmount).doubleValue,
                "remaining_balance": NSDecimalNumber(decimal: loan.remainingBalance).doubleValue,
                "interest_rate": NSDecimalNumber(decimal: loan.interestRate).doubleValue,
                "monthly_payment": NSDecimalNumber(decimal: loan.monthlyPayment).doubleValue,
                "start_date": ISO8601DateFormatter().string(from: loan.startDate),
                "end_date": loan.endDate != nil ? ISO8601DateFormatter().string(from: loan.endDate!) : NSNull(),
                "next_payment_date": loan.nextPaymentDate != nil ? ISO8601DateFormatter().string(from: loan.nextPaymentDate!) : NSNull(),
                "status": loan.status,
                "created_at": ISO8601DateFormatter().string(from: loan.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: loan.updatedAt)
            ]
            
            try await supabaseManager.upsertPrivateLoan(loanData)
            try localDB.updateSyncStatus(for: loan, status: "synced")
        }
    }
    
    // MARK: - Pull Remote Changes
    
    private func pullRemoteChanges() async throws {
        try await pullAccounts()
        try await pullCategories()
        try await pullTransactions()
        try await pullGoals()
        try await pullPrivateLoans()
    }
    
    private func pullAccounts() async throws {
        let remoteAccounts = try await supabaseManager.fetchAccounts(lastSyncedAt: lastSyncDate)
        
        for accountData in remoteAccounts {
            guard let idString = accountData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = accountData["name"] as? String,
                  let typeString = accountData["type"] as? String,
                  let type = AccountType(rawValue: typeString),
                  let balance = accountData["balance"] as? Double else {
                continue
            }
            
            let existingAccount = try localDB.fetchAccount(by: id)
            
            if let account = existingAccount {
                // Update existing
                account.name = name
                account.type = type
                account.balance = Decimal(balance)
                account.currency = accountData["currency"] as? String ?? "USD"
                account.accountNumber = accountData["account_number"] as? String
                account.institutionName = accountData["institution_name"] as? String
                account.color = accountData["color"] as? String ?? "#007AFF"
                account.isActive = accountData["is_active"] as? Bool ?? true
                account.syncStatus = "synced"
                account.lastSyncedAt = Date()
                
                if let updatedAtString = accountData["updated_at"] as? String,
                   let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) {
                    account.updatedAt = updatedAt
                }
            } else {
                // Create new
                let newAccount = Account(
                    id: id,
                    userId: UUID(uuidString: accountData["user_id"] as? String ?? ""),
                    name: name,
                    type: type,
                    balance: Decimal(balance),
                    currency: accountData["currency"] as? String ?? "USD",
                    accountNumber: accountData["account_number"] as? String,
                    institutionName: accountData["institution_name"] as? String,
                    color: accountData["color"] as? String ?? "#007AFF",
                    isActive: accountData["is_active"] as? Bool ?? true,
                    syncStatus: "synced",
                    lastSyncedAt: Date()
                )
                
                if let createdAtString = accountData["created_at"] as? String,
                   let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                    newAccount.createdAt = createdAt
                }
                
                if let updatedAtString = accountData["updated_at"] as? String,
                   let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) {
                    newAccount.updatedAt = updatedAt
                }
                
                try localDB.insert(newAccount)
            }
        }
        
        try localDB.save()
    }
    
    private func pullCategories() async throws {
        let remoteCategories = try await supabaseManager.fetchCategories(lastSyncedAt: lastSyncDate)
        
        for categoryData in remoteCategories {
            guard let idString = categoryData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = categoryData["name"] as? String,
                  let typeString = categoryData["type"] as? String,
                  let type = CategoryType(rawValue: typeString) else {
                continue
            }
            
            let newCategory = Category(
                id: id,
                userId: UUID(uuidString: categoryData["user_id"] as? String ?? ""),
                name: name,
                type: type,
                color: categoryData["color"] as? String ?? "#007AFF",
                icon: categoryData["icon"] as? String ?? "folder",
                isDefault: categoryData["is_default"] as? Bool ?? false,
                syncStatus: "synced",
                lastSyncedAt: Date()
            )
            
            if let createdAtString = categoryData["created_at"] as? String,
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                newCategory.createdAt = createdAt
            }
            
            try localDB.insert(newCategory)
        }
        
        try localDB.save()
    }
    
    private func pullTransactions() async throws {
        let remoteTransactions = try await supabaseManager.fetchTransactions(lastSyncedAt: lastSyncDate)
        
        for transactionData in remoteTransactions {
            guard let idString = transactionData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let accountIdString = transactionData["account_id"] as? String,
                  let accountId = UUID(uuidString: accountIdString),
                  let amount = transactionData["amount"] as? Double,
                  let typeString = transactionData["type"] as? String,
                  let type = TransactionType(rawValue: typeString),
                  let description = transactionData["description"] as? String else {
                continue
            }
            
            let newTransaction = Transaction(
                id: id,
                userId: UUID(uuidString: transactionData["user_id"] as? String ?? ""),
                accountId: accountId,
                categoryId: UUID(uuidString: transactionData["category_id"] as? String ?? ""),
                amount: Decimal(amount),
                type: type,
                transactionDescription: description,
                notes: transactionData["notes"] as? String,
                isRecurring: transactionData["is_recurring"] as? Bool ?? false,
                recurringFrequency: transactionData["recurring_frequency"] as? String,
                tags: transactionData["tags"] as? [String] ?? [],
                syncStatus: "synced",
                lastSyncedAt: Date()
            )
            
            if let transactionDateString = transactionData["transaction_date"] as? String,
               let transactionDate = ISO8601DateFormatter().date(from: transactionDateString) {
                newTransaction.transactionDate = transactionDate
            }
            
            if let createdAtString = transactionData["created_at"] as? String,
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                newTransaction.createdAt = createdAt
            }
            
            if let updatedAtString = transactionData["updated_at"] as? String,
               let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) {
                newTransaction.updatedAt = updatedAt
            }
            
            try localDB.insert(newTransaction)
        }
        
        try localDB.save()
    }
    
    private func pullGoals() async throws {
        let remoteGoals = try await supabaseManager.fetchGoals(lastSyncedAt: lastSyncDate)
        
        for goalData in remoteGoals {
            guard let idString = goalData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = goalData["title"] as? String,
                  let targetAmount = goalData["target_amount"] as? Double else {
                continue
            }
            
            let newGoal = Goal(
                id: id,
                userId: UUID(uuidString: goalData["user_id"] as? String ?? ""),
                title: title,
                goalDescription: goalData["description"] as? String,
                targetAmount: Decimal(targetAmount),
                currentAmount: Decimal(goalData["current_amount"] as? Double ?? 0),
                category: goalData["category"] as? String,
                priority: goalData["priority"] as? String,
                status: goalData["status"] as? String ?? "active",
                syncStatus: "synced",
                lastSyncedAt: Date()
            )
            
            if let targetDateString = goalData["target_date"] as? String,
               let targetDate = ISO8601DateFormatter().date(from: targetDateString) {
                newGoal.targetDate = targetDate
            }
            
            if let createdAtString = goalData["created_at"] as? String,
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                newGoal.createdAt = createdAt
            }
            
            if let updatedAtString = goalData["updated_at"] as? String,
               let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) {
                newGoal.updatedAt = updatedAt
            }
            
            try localDB.insert(newGoal)
        }
        
        try localDB.save()
    }
    
    private func pullPrivateLoans() async throws {
        let remoteLoans = try await supabaseManager.fetchPrivateLoans(lastSyncedAt: lastSyncDate)
        
        for loanData in remoteLoans {
            guard let idString = loanData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let loanName = loanData["loan_name"] as? String,
                  let originalAmount = loanData["original_amount"] as? Double,
                  let remainingBalance = loanData["remaining_balance"] as? Double,
                  let interestRate = loanData["interest_rate"] as? Double,
                  let monthlyPayment = loanData["monthly_payment"] as? Double else {
                continue
            }
            
            let newLoan = PrivateLoan(
                id: id,
                userId: UUID(uuidString: loanData["user_id"] as? String ?? ""),
                loanName: loanName,
                loanType: loanData["loan_type"] as? String,
                lenderName: loanData["lender_name"] as? String,
                originalAmount: Decimal(originalAmount),
                remainingBalance: Decimal(remainingBalance),
                interestRate: Decimal(interestRate),
                monthlyPayment: Decimal(monthlyPayment),
                status: loanData["status"] as? String ?? "active",
                syncStatus: "synced",
                lastSyncedAt: Date()
            )
            
            if let startDateString = loanData["start_date"] as? String,
               let startDate = ISO8601DateFormatter().date(from: startDateString) {
                newLoan.startDate = startDate
            }
            
            if let endDateString = loanData["end_date"] as? String,
               let endDate = ISO8601DateFormatter().date(from: endDateString) {
                newLoan.endDate = endDate
            }
            
            if let nextPaymentDateString = loanData["next_payment_date"] as? String,
               let nextPaymentDate = ISO8601DateFormatter().date(from: nextPaymentDateString) {
                newLoan.nextPaymentDate = nextPaymentDate
            }
            
            if let createdAtString = loanData["created_at"] as? String,
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                newLoan.createdAt = createdAt
            }
            
            if let updatedAtString = loanData["updated_at"] as? String,
               let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) {
                newLoan.updatedAt = updatedAt
            }
            
            try localDB.insert(newLoan)
        }
        
        try localDB.save()
    }
}