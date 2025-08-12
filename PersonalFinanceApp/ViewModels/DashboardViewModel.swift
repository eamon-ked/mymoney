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
    
    // New properties for enhanced dashboard
    @Published var totalSavings: Decimal = 0
    @Published var debtToIncomeRatio: Double = 0
    @Published var emergencyFundStatus: String = "Poor"
    @Published var activeLoans: Int = 0
    @Published var totalMonthlyLoanPayments: Decimal = 0
    @Published var averageInterestRate: Double = 0
    @Published var activeGoals: Int = 0
    @Published var totalGoalAmount: Decimal = 0
    @Published var totalSavedForGoals: Decimal = 0
    @Published var averageGoalProgress: Double = 0
    
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
        calculateTotalSavings()
    }
    
    private func calculateTotalSavings() {
        // Calculate total savings from accounts (excluding debt accounts)
        let accounts = accountRepository.accounts
        totalSavings = accounts.filter { $0.type != .creditCard }.reduce(0) { $0 + $1.balance }
    }
    
    private func calculateDebtToIncomeRatio() {
        let monthlyIncomeDouble = Double(truncating: monthlyIncome as NSDecimalNumber)
        let totalDebtDouble = Double(truncating: totalDebt as NSDecimalNumber)
        
        if monthlyIncomeDouble > 0 {
            // Convert monthly income to annual for debt-to-income ratio
            let annualIncome = monthlyIncomeDouble * 12
            debtToIncomeRatio = (totalDebtDouble / annualIncome) * 100
        } else {
            debtToIncomeRatio = 0
        }
    }
    
    private func calculateEmergencyFundStatus() {
        let monthlyExpensesDouble = Double(truncating: monthlyExpenses as NSDecimalNumber)
        let totalSavingsDouble = Double(truncating: totalSavings as NSDecimalNumber)
        
        if monthlyExpensesDouble > 0 {
            let monthsOfExpenses = totalSavingsDouble / monthlyExpensesDouble
            if monthsOfExpenses >= 6 {
                emergencyFundStatus = "Good"
            } else if monthsOfExpenses >= 3 {
                emergencyFundStatus = "Fair"
            } else {
                emergencyFundStatus = "Poor"
            }
        } else {
            emergencyFundStatus = "Good"
        }
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
        
        // Calculate derived metrics
        calculateDebtToIncomeRatio()
        calculateEmergencyFundStatus()
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
        var totalMonthlyPayments: Decimal = 0
        var totalInterestRate: Decimal = 0
        var activeLoanCount = 0
        
        for loan in loans where loan.status == "active" {
            debt += loan.remainingBalance
            totalMonthlyPayments += loan.monthlyPayment
            totalInterestRate += loan.interestRate
            activeLoanCount += 1
            
            if let due = loan.nextPaymentDate, let month = thisMonth, (due >= month.start && due <= month.end) {
                payments += loan.monthlyPayment
            }
        }
        
        totalDebt = debt
        loanPaymentsThisMonth = payments
        self.activeLoans = activeLoanCount
        self.totalMonthlyLoanPayments = totalMonthlyPayments
        
        // Calculate average interest rate
        if activeLoanCount > 0 {
            averageInterestRate = Double(truncating: (totalInterestRate / Decimal(activeLoanCount)) as NSDecimalNumber)
        } else {
            averageInterestRate = 0
        }
    }

    private func calculatePlannedGoalSavings(goals: [Goal]) {
        let calendar = Calendar.current
        let now = Date()
        var planned: Decimal = 0
        var totalAmount: Decimal = 0
        var totalSaved: Decimal = 0
        var activeGoalCount = 0
        var totalProgress: Double = 0
        
        for goal in goals where goal.status == "active" {
            activeGoalCount += 1
            totalAmount += goal.targetAmount
            totalSaved += goal.currentAmount
            totalProgress += goal.progress
            
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
        self.activeGoals = activeGoalCount
        self.totalGoalAmount = totalAmount
        self.totalSavedForGoals = totalSaved
        
        // Calculate average goal progress
        if activeGoalCount > 0 {
            averageGoalProgress = totalProgress / Double(activeGoalCount) * 100
        } else {
            averageGoalProgress = 0
        }
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