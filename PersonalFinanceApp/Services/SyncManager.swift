//
//  SyncManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine
import Network

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var isOnline: Bool = true
    
    private let supabaseManager = SupabaseManager.shared
    private let localDB = LocalDatabaseManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private let syncQueue = DispatchQueue(label: "sync.queue", qos: .background)
    private let pathMonitor = NWPathMonitor()
    private var syncTimer: Timer?
    private var pendingSyncWorkItem: DispatchWorkItem?
    
    // Performance optimizations
    private var lastSyncAttempt: Date = Date.distantPast
    private let minimumSyncInterval: TimeInterval = 30 // 30 seconds between syncs
    private let syncDebounceInterval: TimeInterval = 2 // 2 seconds debounce
    
    // Server-clock updated_at of the newest transaction pulled so far
    private let transactionsCursorKey = "transactionsPullCursor"
    
    private init() {
        setupPeriodicSync()
        loadLastSyncDate()
        startNetworkMonitoring()
    }
    
    private func setupPeriodicSync() {
        // Sync every 10 minutes when app is active (reduced from 5 minutes)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task {
                await self.performSync()
            }
        }
    }
    
    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    private func saveLastSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }

    // Reset sync checkpoints so a new sign-in (or first sign-in on a device)
    // performs a full pull from the server.
    func resetSyncState() {
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: transactionsCursorKey)
    }
    
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let nowOnline = (path.status == .satisfied)
                let wasOffline = (self?.isOnline == false)
                self?.isOnline = nowOnline
                // Auto-sync when coming back online, but only if we have pending changes
                if nowOnline && wasOffline {
                    await self?.performSyncIfNeeded()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "network.monitor"))
    }
    
    // MARK: - Public Sync Methods
    
    func performSync() async {
        await performSyncIfNeeded()
    }
    
    private func performSyncIfNeeded() async {
        // Check if we have pending changes first
        let hasPendingChanges = await checkForPendingChanges()
        guard hasPendingChanges else {
            print("🔄 No pending changes, skipping sync")
            return
        }
        
        // Rate limiting
        let timeSinceLastSync = Date().timeIntervalSince(lastSyncAttempt)
        guard timeSinceLastSync >= minimumSyncInterval else {
            print("🔄 Sync rate limited, last sync was \(Int(timeSinceLastSync))s ago")
            return
        }
        
        await performSyncInternal()
    }
    
    private func performSyncInternal() async {
        guard supabaseManager.isAuthenticated else { return }
        
        lastSyncAttempt = Date()
        
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
        await performSyncInternal()
    }
    
    // Called from UI when offline; will sync immediately if back online
    func reconnectNow() async {
        if isOnline {
            await performSyncInternal()
        }
    }
    
    // Debounced sync for UI operations
    func triggerSync() {
        pendingSyncWorkItem?.cancel()
        
        let workItem = DispatchWorkItem {
            Task {
                await self.performSyncIfNeeded()
            }
        }
        
        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + syncDebounceInterval, execute: workItem)
    }
    
    // MARK: - Check for Pending Changes
    
    private func checkForPendingChanges() async -> Bool {
        do {
            let pendingAccounts = try localDB.fetchPendingSyncAccounts()
            let pendingTransactions = try localDB.fetchPendingSyncTransactions()
            let pendingCategories = try localDB.fetchPendingSyncCategories()
            let pendingGoals = try localDB.fetchPendingSyncGoals()
            let pendingLoans = try localDB.fetchPendingSyncPrivateLoans()
            
            let hasPending = !pendingAccounts.isEmpty || 
                           !pendingTransactions.isEmpty || 
                           !pendingCategories.isEmpty || 
                           !pendingGoals.isEmpty || 
                           !pendingLoans.isEmpty
            
            print("🔍 Pending changes: accounts(\(pendingAccounts.count)), transactions(\(pendingTransactions.count)), categories(\(pendingCategories.count)), goals(\(pendingGoals.count)), loans(\(pendingLoans.count))")
            
            return hasPending
        } catch {
            print("❌ Error checking pending changes: \(error)")
            return true // Assume there are changes if we can't check
        }
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
                // Cached value kept up to date for v1.0 clients; v1.1 never reads it
                "balance": moneyString(account.balance),
                "currency": account.currency,
                "account_number": account.accountNumber ?? NSNull(),
                "institution_name": account.institutionName ?? NSNull(),
                "color": account.color,
                "is_active": account.isActive,
                "created_at": ISO8601DateFormatter().string(from: account.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: account.updatedAt)
            ]
            var payload = accountData
            // Only a confirmed opening balance is shared; an unconfirmed one is this
            // device's guess and must not overwrite another device's confirmed value.
            if let confirmedAt = account.balanceConfirmedAt {
                payload["opening_balance"] = moneyString(account.openingBalance)
                payload["balance_confirmed_at"] = ISO8601DateFormatter().string(from: confirmedAt)
            }
            
            try await supabaseManager.upsertAccount(payload)
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
                "transfer_account_id": transaction.transferAccountId?.uuidString ?? NSNull(),
                "category_id": transaction.categoryId?.uuidString ?? NSNull(),
                "amount": moneyString(transaction.amount),
                "type": transaction.type.rawValue,
                "description": transaction.transactionDescription,
                "notes": transaction.notes ?? NSNull(),
                "transaction_date": ISO8601DateFormatter().string(from: transaction.transactionDate),
                "is_recurring": transaction.isRecurring,
                "recurring_frequency": transaction.recurringFrequency ?? NSNull(),
                "tags": transaction.tags,
                "created_at": ISO8601DateFormatter().string(from: transaction.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: transaction.updatedAt),
                "deleted_at": transaction.deletedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
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
                "target_amount": moneyString(goal.targetAmount),
                "current_amount": moneyString(goal.currentAmount),
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
                "original_amount": moneyString(loan.originalAmount),
                "remaining_balance": moneyString(loan.remainingBalance),
                "interest_rate": moneyString(loan.interestRate),
                "monthly_payment": moneyString(loan.monthlyPayment),
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
        // Unconfirmed accounts new to this device keep their v1.0 balance until repaired
        for (id, legacy) in legacyBalances {
            if let account = try localDB.fetchAccount(by: id), account.balanceConfirmedAt == nil {
                account.openingBalance = legacy - (try localDB.transactionTotal(for: id))
            }
        }
        legacyBalances.removeAll()
        // Balances are derived from transactions, never pulled
        try localDB.recalculateAllBalances()
    }
    
    /// v1.0 stored balances of accounts first seen on this device, keyed by account id
    private var legacyBalances: [UUID: Decimal] = [:]
    
    private func pullAccounts() async throws {
        let remoteAccounts = try await supabaseManager.fetchAccounts(lastSyncedAt: lastSyncDate)
        
        for accountData in remoteAccounts {
            guard let idString = accountData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = accountData["name"] as? String,
                  let typeString = accountData["type"] as? String,
                  let type = AccountType(rawValue: typeString) else {
                continue
            }
            let remoteOpening = decimal(accountData["opening_balance"]) ?? 0
            let remoteConfirmedAt = parseISODate(accountData["balance_confirmed_at"] as? String ?? "")
            
            let existingAccount = try localDB.fetchAccount(by: id)
            
            if let account = existingAccount {
                let remoteUpdated = parseISODate(accountData["updated_at"] as? String ?? "") ?? .distantPast
                if account.syncStatus == "pending" && account.updatedAt > remoteUpdated {
                    continue   // local edit is newer; it goes up on the next push
                }
                // Update existing
                account.name = name
                account.type = type
                // A remote opening balance replaces ours only once someone confirmed it
                if let remoteConfirmedAt {
                    account.openingBalance = remoteOpening
                    account.balanceConfirmedAt = remoteConfirmedAt
                }
                account.currency = accountData["currency"] as? String ?? "USD"
                account.accountNumber = accountData["account_number"] as? String
                account.institutionName = accountData["institution_name"] as? String
                account.color = accountData["color"] as? String ?? "#007AFF"
                account.isActive = accountData["is_active"] as? Bool ?? true
                account.syncStatus = "synced"
                account.lastSyncedAt = Date()
                
                if let updatedAtString = accountData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    account.updatedAt = updatedAt
                }
            } else {
                // Create new
                let newAccount = Account(
                    id: id,
                    userId: UUID(uuidString: accountData["user_id"] as? String ?? ""),
                    name: name,
                    type: type,
                    openingBalance: remoteOpening,
                    currency: accountData["currency"] as? String ?? "USD",
                    accountNumber: accountData["account_number"] as? String,
                    institutionName: accountData["institution_name"] as? String,
                    color: accountData["color"] as? String ?? "#007AFF",
                    isActive: accountData["is_active"] as? Bool ?? true,
                    syncStatus: "synced",
                    lastSyncedAt: Date()
                )
                newAccount.balanceConfirmedAt = remoteConfirmedAt
                if remoteConfirmedAt == nil {
                    // Seeded once transactions are pulled, from the v1.0 stored balance
                    legacyBalances[id] = decimal(accountData["balance"]) ?? 0
                }
                
                if let createdAtString = accountData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    newAccount.createdAt = createdAt
                }
                
                if let updatedAtString = accountData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    newAccount.updatedAt = updatedAt
                }
                
                try localDB.insert(newAccount)
            }
        }
        
        try localDB.save()
        // Notify repositories to reload
        AccountRepository().loadAccounts() // lightweight refresh for UI listeners
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
            if let existing = try localDB.fetchCategory(by: id) {
                existing.name = name
                existing.type = type
                existing.color = categoryData["color"] as? String ?? existing.color
                existing.icon = categoryData["icon"] as? String ?? existing.icon
                existing.isDefault = categoryData["is_default"] as? Bool ?? existing.isDefault
                existing.syncStatus = "synced"
                existing.lastSyncedAt = Date()
                if let createdAtString = categoryData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    existing.createdAt = createdAt
                }
            } else {
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
                   let createdAt = parseISODate(createdAtString) {
                    newCategory.createdAt = createdAt
                }
                try localDB.insert(newCategory)
            }
        }
        
        try localDB.save()
        // No-op: category repo observes changes
    }
    
    private func pullTransactions() async throws {
        let cursor = UserDefaults.standard.string(forKey: transactionsCursorKey)
        let remoteTransactions = try await supabaseManager.fetchTransactions(updatedSince: cursor)
        var newestUpdated: Date?
        
        for transactionData in remoteTransactions {
            let remoteUpdated = parseISODate(transactionData["updated_at"] as? String ?? "")
            if let remoteUpdated, remoteUpdated > (newestUpdated ?? .distantPast) {
                newestUpdated = remoteUpdated
            }
            guard let idString = transactionData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let accountIdString = transactionData["account_id"] as? String,
                  let accountId = UUID(uuidString: accountIdString),
                  let amount = decimal(transactionData["amount"]),
                  let typeString = transactionData["type"] as? String,
                  let type = TransactionType(rawValue: typeString),
                  let description = transactionData["description"] as? String else {
                continue
            }
            
            let transferAccountId = UUID(uuidString: transactionData["transfer_account_id"] as? String ?? "")
            let deletedAt = parseISODate(transactionData["deleted_at"] as? String ?? "")
            
            if let existing = try localDB.fetchTransaction(by: id) {
                if existing.syncStatus == "pending" && existing.updatedAt > (remoteUpdated ?? .distantPast) {
                    continue   // local edit is newer; it goes up on the next push
                }
                existing.userId = UUID(uuidString: transactionData["user_id"] as? String ?? existing.userId?.uuidString ?? "")
                existing.accountId = accountId
                existing.categoryId = UUID(uuidString: transactionData["category_id"] as? String ?? existing.categoryId?.uuidString ?? "")
                existing.transferAccountId = transferAccountId
                existing.deletedAt = deletedAt
                existing.amount = amount
                existing.type = type
                existing.transactionDescription = description
                existing.notes = transactionData["notes"] as? String
                existing.isRecurring = transactionData["is_recurring"] as? Bool ?? existing.isRecurring
                existing.recurringFrequency = transactionData["recurring_frequency"] as? String
                existing.tags = transactionData["tags"] as? [String] ?? existing.tags
                existing.syncStatus = "synced"
                existing.lastSyncedAt = Date()
                if let transactionDateString = transactionData["transaction_date"] as? String,
                   let transactionDate = parseISODate(transactionDateString) {
                    existing.transactionDate = transactionDate
                }
                if let createdAtString = transactionData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    existing.createdAt = createdAt
                }
                if let updatedAtString = transactionData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    existing.updatedAt = updatedAt
                }
            } else {
                let newTransaction = Transaction(
                    id: id,
                    userId: UUID(uuidString: transactionData["user_id"] as? String ?? ""),
                    accountId: accountId,
                    transferAccountId: transferAccountId,
                    categoryId: UUID(uuidString: transactionData["category_id"] as? String ?? ""),
                    amount: amount,
                    type: type,
                    transactionDescription: description,
                    notes: transactionData["notes"] as? String,
                    isRecurring: transactionData["is_recurring"] as? Bool ?? false,
                    recurringFrequency: transactionData["recurring_frequency"] as? String,
                    tags: transactionData["tags"] as? [String] ?? [],
                    syncStatus: "synced",
                    lastSyncedAt: Date()
                )
                newTransaction.deletedAt = deletedAt
                if let transactionDateString = transactionData["transaction_date"] as? String,
                   let transactionDate = parseISODate(transactionDateString) {
                    newTransaction.transactionDate = transactionDate
                }
                if let createdAtString = transactionData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    newTransaction.createdAt = createdAt
                }
                if let updatedAtString = transactionData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    newTransaction.updatedAt = updatedAt
                }
                try localDB.insert(newTransaction)
            }
        }
        
        try localDB.save()
        if let newestUpdated {
            // Step back a second so rows sharing the newest timestamp are never skipped;
            // re-applying a row is harmless.
            UserDefaults.standard.set(isoWithFractionalSeconds(newestUpdated.addingTimeInterval(-1)),
                                      forKey: transactionsCursorKey)
        }
    }
    
    private func pullGoals() async throws {
        let remoteGoals = try await supabaseManager.fetchGoals(lastSyncedAt: lastSyncDate)
        
        for goalData in remoteGoals {
            guard let idString = goalData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = goalData["title"] as? String,
                  let targetAmount = decimal(goalData["target_amount"]) else {
                continue
            }
            
            if let existing = try localDB.fetchGoal(by: id) {
                existing.userId = UUID(uuidString: goalData["user_id"] as? String ?? existing.userId?.uuidString ?? "")
                existing.title = title
                existing.goalDescription = goalData["description"] as? String
                existing.targetAmount = targetAmount
                existing.currentAmount = decimal(goalData["current_amount"]) ?? 0
                existing.category = goalData["category"] as? String
                existing.priority = goalData["priority"] as? String
                existing.status = goalData["status"] as? String ?? existing.status
                existing.syncStatus = "synced"
                existing.lastSyncedAt = Date()
                if let targetDateString = goalData["target_date"] as? String,
                   let targetDate = parseISODate(targetDateString) {
                    existing.targetDate = targetDate
                }
                if let createdAtString = goalData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    existing.createdAt = createdAt
                }
                if let updatedAtString = goalData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    existing.updatedAt = updatedAt
                }
            } else {
                let newGoal = Goal(
                    id: id,
                    userId: UUID(uuidString: goalData["user_id"] as? String ?? ""),
                    title: title,
                    goalDescription: goalData["description"] as? String,
                    targetAmount: targetAmount,
                    currentAmount: decimal(goalData["current_amount"]) ?? 0,
                    category: goalData["category"] as? String,
                    priority: goalData["priority"] as? String,
                    status: goalData["status"] as? String ?? "active",
                    syncStatus: "synced",
                    lastSyncedAt: Date()
                )
                if let targetDateString = goalData["target_date"] as? String,
                   let targetDate = parseISODate(targetDateString) {
                    newGoal.targetDate = targetDate
                }
                if let createdAtString = goalData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    newGoal.createdAt = createdAt
                }
                if let updatedAtString = goalData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    newGoal.updatedAt = updatedAt
                }
                try localDB.insert(newGoal)
            }
        }
        
        try localDB.save()
    }
    
    private func pullPrivateLoans() async throws {
        let remoteLoans = try await supabaseManager.fetchPrivateLoans(lastSyncedAt: lastSyncDate)
        
        for loanData in remoteLoans {
            guard let idString = loanData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let loanName = loanData["loan_name"] as? String,
                  let originalAmount = decimal(loanData["original_amount"]),
                  let remainingBalance = decimal(loanData["remaining_balance"]),
                  let interestRate = decimal(loanData["interest_rate"]),
                  let monthlyPayment = decimal(loanData["monthly_payment"]) else {
                continue
            }
            
            if let existing = try localDB.fetchPrivateLoan(by: id) {
                existing.userId = UUID(uuidString: loanData["user_id"] as? String ?? existing.userId?.uuidString ?? "")
                existing.loanName = loanName
                existing.loanType = loanData["loan_type"] as? String
                existing.lenderName = loanData["lender_name"] as? String
                existing.originalAmount = originalAmount
                existing.remainingBalance = remainingBalance
                existing.interestRate = interestRate
                existing.monthlyPayment = monthlyPayment
                existing.status = loanData["status"] as? String ?? existing.status
                existing.syncStatus = "synced"
                existing.lastSyncedAt = Date()
                if let startDateString = loanData["start_date"] as? String,
                   let startDate = parseISODate(startDateString) {
                    existing.startDate = startDate
                }
                if let endDateString = loanData["end_date"] as? String,
                   let endDate = parseISODate(endDateString) {
                    existing.endDate = endDate
                }
                if let nextPaymentDateString = loanData["next_payment_date"] as? String,
                   let nextPaymentDate = parseISODate(nextPaymentDateString) {
                    existing.nextPaymentDate = nextPaymentDate
                }
                if let createdAtString = loanData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    existing.createdAt = createdAt
                }
                if let updatedAtString = loanData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    existing.updatedAt = updatedAt
                }
            } else {
                let newLoan = PrivateLoan(
                    id: id,
                    userId: UUID(uuidString: loanData["user_id"] as? String ?? ""),
                    loanName: loanName,
                    loanType: loanData["loan_type"] as? String,
                    lenderName: loanData["lender_name"] as? String,
                    originalAmount: originalAmount,
                    remainingBalance: remainingBalance,
                    interestRate: interestRate,
                    monthlyPayment: monthlyPayment,
                    status: loanData["status"] as? String ?? "active",
                    syncStatus: "synced",
                    lastSyncedAt: Date()
                )
                if let startDateString = loanData["start_date"] as? String,
                   let startDate = parseISODate(startDateString) {
                    newLoan.startDate = startDate
                }
                if let endDateString = loanData["end_date"] as? String,
                   let endDate = parseISODate(endDateString) {
                    newLoan.endDate = endDate
                }
                if let nextPaymentDateString = loanData["next_payment_date"] as? String,
                   let nextPaymentDate = parseISODate(nextPaymentDateString) {
                    newLoan.nextPaymentDate = nextPaymentDate
                }
                if let createdAtString = loanData["created_at"] as? String,
                   let createdAt = parseISODate(createdAtString) {
                    newLoan.createdAt = createdAt
                }
                if let updatedAtString = loanData["updated_at"] as? String,
                   let updatedAt = parseISODate(updatedAtString) {
                    newLoan.updatedAt = updatedAt
                }
                try localDB.insert(newLoan)
            }
        }
        
        try localDB.save()
    }
}

// MARK: - Wire format helpers

/// Money goes up as a string; PostgREST casts it to numeric exactly.
fileprivate func moneyString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

/// Parses a numeric column without passing through Double.
fileprivate func decimal(_ value: Any?) -> Decimal? {
    if let s = value as? String { return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) }
    if let n = value as? NSNumber { return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
    return nil
}

/// Accepts Supabase timestamps with or without fractional seconds (any number
/// of digits) and plain DATE values such as 2025-08-09.
fileprivate func parseISODate(_ string: String) -> Date? {
    guard !string.isEmpty else { return nil }
    // Trim fractional seconds to milliseconds, which ISO8601DateFormatter handles reliably
    let trimmed = string.replacingOccurrences(
        of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: trimmed) { return d }
    if let d = ISO8601DateFormatter().date(from: trimmed) { return d }
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.timeZone = TimeZone(identifier: "UTC")
    dateOnly.dateFormat = "yyyy-MM-dd"
    return dateOnly.date(from: string)
}

fileprivate func isoWithFractionalSeconds(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}
