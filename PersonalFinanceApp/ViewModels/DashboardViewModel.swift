//
//  DashboardViewModel.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

class DashboardViewModel: ObservableObject {
    @Published var netWorth: Decimal = 0
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpenses: Decimal = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var upcomingGoals: [Goal] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let accountRepository = AccountRepository()
    private let transactionRepository = TransactionRepository()
    private let goalRepository = GoalRepository()
    private let syncManager = SyncManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        loadDashboardData()
    }
    
    private func setupBindings() {
        // Listen to repository changes
        accountRepository.$accounts
            .sink { [weak self] _ in
                self?.calculateNetWorth()
            }
            .store(in: &cancellables)
        
        transactionRepository.$transactions
            .sink { [weak self] transactions in
                self?.recentTransactions = Array(transactions.prefix(5))
                self?.calculateMonthlyTotals()
            }
            .store(in: &cancellables)
        
        goalRepository.$goals
            .sink { [weak self] _ in
                self?.loadUpcomingGoals()
            }
            .store(in: &cancellables)
        
        // Listen to sync status
        syncManager.$isSyncing
            .sink { [weak self] isSyncing in
                self?.isLoading = isSyncing
            }
            .store(in: &cancellables)
    }
    
    func loadDashboardData() {
        accountRepository.loadAccounts()
        transactionRepository.loadTransactions()
        goalRepository.loadGoals()
    }
    
    func refreshData() async {
        await syncManager.forceSyncNow()
        loadDashboardData()
    }
    
    private func calculateNetWorth() {
        netWorth = accountRepository.getTotalBalance()
    }
    
    private func calculateMonthlyTotals() {
        let calendar = Calendar.current
        let now = Date()
        
        guard let startOfMonth = calendar.dateInterval(of: .month, for: now) else {
            return
        }
        
        monthlyIncome = transactionRepository.getTotalIncome(for: startOfMonth)
        monthlyExpenses = transactionRepository.getTotalExpenses(for: startOfMonth)
    }
    
    private func loadUpcomingGoals() {
        upcomingGoals = goalRepository.getUpcomingGoals()
    }
    
    var monthlySavings: Decimal {
        return monthlyIncome - monthlyExpenses
    }
    
    var savingsRate: Double {
        let income = Double(truncating: monthlyIncome as NSDecimalNumber)
        let savings = Double(truncating: monthlySavings as NSDecimalNumber)
        return income > 0 ? (savings / income) * 100 : 0
    }
}