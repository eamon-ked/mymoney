//
//  DashboardViewModel.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var netWorth: Decimal = 0
    @Published var totalDebt: Decimal = 0
    @Published var netWorthAfterDebt: Decimal = 0
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpenses: Decimal = 0
    @Published var loanPaymentsThisMonth: Decimal = 0
    @Published var plannedGoalSavingsThisMonth: Decimal = 0
    @Published var topSpendingCategories: [(category: String, amount: Decimal)] = []
    @Published var upcomingPayments: [PrivateLoan] = []
    @Published var recentTransactions: [Transaction] = []
    @Published var upcomingGoals: [Goal] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let accountRepository = AccountRepository()
    private let transactionRepository = TransactionRepository()
    private let goalRepository = GoalRepository()
    private let loanRepository = LoanRepository()
    private let syncManager = SyncManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var calculationWorkItem: DispatchWorkItem?
    
    // Performance optimizations
    private var lastCalculationTime: Date = Date.distantPast
    private let calculationDebounceInterval: TimeInterval = 0.5 // 500ms debounce
    
    init() {
        setupBindings()
        loadDashboardData()
        // React to preference changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.debouncedCalculateMonthlyTotals()
            }
            .store(in: &cancellables)
    }
    
    private func setupBindings() {
        // Listen to repository changes with debouncing
        accountRepository.$accounts
            .sink { [weak self] _ in
                self?.debouncedCalculateNetWorth()
            }
            .store(in: &cancellables)
        
        transactionRepository.$transactions
            .sink { [weak self] transactions in
                self?.debouncedUpdateTransactions(transactions)
            }
            .store(in: &cancellables)
        
        goalRepository.$goals
            .sink { [weak self] goals in
                self?.debouncedUpdateGoals(goals)
            }
            .store(in: &cancellables)
        
        // Listen to sync status
        syncManager.$isSyncing
            .sink { [weak self] isSyncing in
                self?.isLoading = isSyncing
            }
            .store(in: &cancellables)
        loanRepository.$loans
            .sink { [weak self] loans in
                self?.debouncedUpdateLoans(loans)
            }
            .store(in: &cancellables)
    }
    
    func loadDashboardData() {
        accountRepository.loadAccounts()
        transactionRepository.loadTransactions()
        goalRepository.loadGoals()
        loanRepository.loadLoans()
    }
    
    func refreshData() async {
        await syncManager.forceSyncNow()
        loadDashboardData()
    }
    
    private func calculateNetWorth() {
        netWorth = accountRepository.getTotalBalance()
        netWorthAfterDebt = netWorth - totalDebt
    }
    
    private func calculateMonthlyTotals() {
        let calendar = Calendar.current
        let now = Date()
        
        guard let startOfMonth = calendar.dateInterval(of: .month, for: now) else {
            return
        }
        
        monthlyIncome = transactionRepository.getTotalIncome(for: startOfMonth)
        // Base expenses from transactions
        let baseExpenses = transactionRepository.getTotalExpenses(for: startOfMonth)
        // Respect user preferences for including planned amounts
        let includeLoans = getBoolPreference("includeLoanPaymentsInMonthly", defaultValue: false)
        let includeGoals = getBoolPreference("includeGoalSavingsInMonthly", defaultValue: false)
        let loans = includeLoans ? loanPaymentsThisMonth : 0
        let goals = includeGoals ? plannedGoalSavingsThisMonth : 0
        // Forecasted scheduled items
        monthlyExpenses = baseExpenses + loans + goals
    }

    private func calculateTopSpending(transactions: [Transaction]) {
        var categoryTotals: [String: Decimal] = [:]
        for t in transactions where t.type == .expense {
            let key = t.category?.name ?? "Other"
            categoryTotals[key, default: 0] += t.amount
        }
        let sorted = categoryTotals.sorted { $0.value > $1.value }
        topSpendingCategories = Array(sorted.prefix(5)).map { ($0.key, $0.value) }
    }

    private func loadUpcomingPayments(loans: [PrivateLoan]) {
        let now = Date()
        let in30 = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        upcomingPayments = loans.filter { loan in
            if let next = loan.nextPaymentDate { return next >= now && next <= in30 }
            return false
        }.sorted { ($0.nextPaymentDate ?? .distantFuture) < ($1.nextPaymentDate ?? .distantFuture) }
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

    // MARK: - Loans & Goals derived figures
    private func calculateDebtAndPayments(loans: [PrivateLoan]) {
        let calendar = Calendar.current
        let now = Date()
        let thisMonth = calendar.dateInterval(of: .month, for: now)
        var debt: Decimal = 0
        var payments: Decimal = 0
        for loan in loans where loan.status == "active" {
            debt += loan.remainingBalance
            if let due = loan.nextPaymentDate, let month = thisMonth, (due >= month.start && due <= month.end) {
                payments += loan.monthlyPayment
            }
        }
        totalDebt = debt
        loanPaymentsThisMonth = payments
    }

    private func calculatePlannedGoalSavings(goals: [Goal]) {
        let calendar = Calendar.current
        let now = Date()
        var planned: Decimal = 0
        for goal in goals where goal.status == "active" {
            guard let targetDate = goal.targetDate else { continue }
            let remaining = max(0, goal.targetAmount - goal.currentAmount)
            if remaining == 0 { continue }
            let comps = calendar.dateComponents([.month], from: now, to: targetDate)
            let months = max(1, comps.month ?? 0)
            if months > 0 {
                planned += remaining / Decimal(months)
            } else {
                // target date passed; allocate full remaining this month
                planned += remaining
            }
        }
        plannedGoalSavingsThisMonth = planned
    }

    private func getBoolPreference(_ key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }
    
    // MARK: - Debounced Calculations
    
    private func debouncedCalculateNetWorth() {
        calculationWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.calculateNetWorth()
        }
        
        calculationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + calculationDebounceInterval, execute: workItem)
    }
    
    private func debouncedCalculateMonthlyTotals() {
        calculationWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.calculateMonthlyTotals()
        }
        
        calculationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + calculationDebounceInterval, execute: workItem)
    }
    
    private func debouncedUpdateTransactions(_ transactions: [Transaction]) {
        calculationWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.recentTransactions = Array(transactions.prefix(5))
            self?.calculateMonthlyTotals()
            self?.calculateTopSpending(transactions: transactions)
        }
        
        calculationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + calculationDebounceInterval, execute: workItem)
    }
    
    private func debouncedUpdateGoals(_ goals: [Goal]) {
        calculationWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadUpcomingGoals()
            self?.calculatePlannedGoalSavings(goals: goals)
            self?.calculateMonthlyTotals()
        }
        
        calculationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + calculationDebounceInterval, execute: workItem)
    }
    
    private func debouncedUpdateLoans(_ loans: [PrivateLoan]) {
        calculationWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadUpcomingPayments(loans: loans)
            self?.calculateDebtAndPayments(loans: loans)
            self?.calculateNetWorth()
            self?.calculateMonthlyTotals()
        }
        
        calculationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + calculationDebounceInterval, execute: workItem)
    }
}