//
//  DashboardView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var syncManager = SyncManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Sync status hidden per requirements
                    
                    // Net Worth Card
                    NetWorthCard(
                        netWorth: viewModel.netWorth,
                        totalDebt: viewModel.totalDebt,
                        netWorthAfterDebt: viewModel.netWorthAfterDebt
                    )
                    
                    // Financial Health Overview
                    FinancialHealthCard(
                        totalSavings: viewModel.totalSavings,
                        totalDebt: viewModel.totalDebt,
                        debtToIncomeRatio: viewModel.debtToIncomeRatio,
                        emergencyFundStatus: viewModel.emergencyFundStatus
                    )
                    
                    // Monthly Overview
                    MonthlyOverviewCard(
                        income: viewModel.monthlyIncome,
                        expenses: viewModel.monthlyExpenses,
                        savings: viewModel.monthlySavings,
                        savingsRate: viewModel.savingsRate,
                        loanPayments: viewModel.loanPaymentsThisMonth,
                        plannedGoalSavings: viewModel.plannedGoalSavingsThisMonth
                    )

                    // Explanatory note (caption-sized) about how totals are calculated
                    Text("Savings = balances in Checking, Savings, Cash, and Investment. Credit Cards count as debt and are subtracted from Net Worth. Monthly Expenses = Expense transactions this month plus any planned loan payments/goal savings you’ve chosen to include.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Debt & Loans Summary
                    if viewModel.totalDebt > 0 {
                        DebtLoansSummaryCard(
                            totalDebt: viewModel.totalDebt,
                            activeLoans: viewModel.activeLoans,
                            totalMonthlyPayments: viewModel.totalMonthlyLoanPayments,
                            averageInterestRate: viewModel.averageInterestRate
                        )
                    }
                    
                    // Goals Progress Summary
                    if viewModel.activeGoals > 0 {
                        GoalsProgressCard(
                            activeGoals: viewModel.activeGoals,
                            totalGoalAmount: viewModel.totalGoalAmount,
                            totalSavedForGoals: viewModel.totalSavedForGoals,
                            averageGoalProgress: viewModel.averageGoalProgress
                        )
                    }
                    
                    // Top Spending
                    if !viewModel.topSpendingCategories.isEmpty {
                        TopSpendingCard(items: viewModel.topSpendingCategories)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Upcoming Payments
                    if !viewModel.upcomingPayments.isEmpty {
                        UpcomingPaymentsCard(loans: viewModel.upcomingPayments)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
                            .animation(.easeInOut(duration: 0.25), value: viewModel.upcomingPayments)
                    }

                    // Recent Transactions
                    RecentTransactionsCard(transactions: viewModel.recentTransactions)
                    
                    // Upcoming Goals
                    if !viewModel.upcomingGoals.isEmpty {
                        UpcomingGoalsCard(goals: viewModel.upcomingGoals)
                            .transition(.opacity.combined(with: .slide))
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.upcomingGoals)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await viewModel.refreshData()
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    viewModel.loadDashboardData()
                }
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Financial Health Card
struct FinancialHealthCard: View {
    let totalSavings: Decimal
    let totalDebt: Decimal
    let debtToIncomeRatio: Double
    let emergencyFundStatus: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Financial Health")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundColor(.green)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Savings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(totalSavings)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Debt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(totalDebt)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Debt/Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(debtToIncomeRatio))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(debtToIncomeRatio > 40 ? .red : debtToIncomeRatio > 20 ? .orange : .green)
                }
            }
            
            HStack {
                Text("Emergency Fund:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(emergencyFundStatus)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(emergencyFundStatus == "Good" ? .green : emergencyFundStatus == "Fair" ? .orange : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Debt & Loans Summary Card
struct DebtLoansSummaryCard: View {
    let totalDebt: Decimal
    let activeLoans: Int
    let totalMonthlyPayments: Decimal
    let averageInterestRate: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Debt & Loans")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink("See Loans", destination: LoansView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Debt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(totalDebt)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Loans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(activeLoans)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg. Interest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", averageInterestRate))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
            
            HStack {
                Text("Monthly Payments:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                AnimatedNumber(totalMonthlyPayments)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Goals Progress Card
struct GoalsProgressCard: View {
    let activeGoals: Int
    let totalGoalAmount: Decimal
    let totalSavedForGoals: Decimal
    let averageGoalProgress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Goals Progress")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink("See Goals", destination: GoalsView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Goals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(activeGoals)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(totalGoalAmount)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg. Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(averageGoalProgress))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                Text("Total Saved:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                AnimatedNumber(totalSavedForGoals)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            
            // Progress bar
            ProgressView(value: averageGoalProgress / 100)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct NetWorthCard: View {
    let netWorth: Decimal
    let totalDebt: Decimal
    let netWorthAfterDebt: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Net Worth")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.green)
            }
            
            AnimatedNumber(netWorth)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: netWorth)

            // Debt and adjusted net worth
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Debt:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currencyFormatter.string(from: totalDebt as NSDecimalNumber) ?? "$0.00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("After Debt:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    AnimatedNumber(netWorthAfterDebt)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: netWorthAfterDebt)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - AnimatedNumber
struct AnimatedNumber: View {
    let value: Decimal
    @State private var animated: Double = 0

    init(_ value: Decimal) {
        self.value = value
    }

    var body: some View {
        Text(formatted(animatedDecimal))
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
    }

    private var animatedDecimal: Decimal {
        Decimal(animated)
    }

    private func animate(to target: Decimal) {
        let targetDouble = Double(truncating: target as NSDecimalNumber)
        withAnimation(.easeOut(duration: 0.4)) {
            animated = targetDouble
        }
    }

    private func formatted(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
        formatter.currencyCode = code.isEmpty ? "USD" : code
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}

struct MonthlyOverviewCard: View {
    let income: Decimal
    let expenses: Decimal
    let savings: Decimal
    let savingsRate: Double
    let loanPayments: Decimal
    let plannedGoalSavings: Decimal
    @State private var showBreakdown: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Month")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(income)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AnimatedNumber(expenses)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Savings Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(savingsRate))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            // Savings amount
            HStack {
                Text("Saved:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                AnimatedNumber(savings)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(savings >= 0 ? .green : .red)
            }

            // Breakdown of planned components added into expenses this month
            if showBreakdown {
                VStack(spacing: 6) {
                HStack {
                    Text("Includes Loan Payments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currencyFormatter.string(from: loanPayments as NSDecimalNumber) ?? "$0.00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Includes Goal Savings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(currencyFormatter.string(from: plannedGoalSavings as NSDecimalNumber) ?? "$0.00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                }
            }
            Button(showBreakdown ? "Hide Breakdown" : "Show Breakdown") { withAnimation(.easeInOut(duration: 0.2)) { showBreakdown.toggle() } }
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct RecentTransactionsCard: View {
    let transactions: [Transaction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink("See All", destination: TransactionsView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            if transactions.isEmpty {
                Text("No transactions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct TopSpendingCard: View {
    let items: [(category: String, amount: Decimal)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Spending")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            ForEach(items, id: \.category) { item in
                HStack {
                    Text(item.category)
                    Spacer()
                    Text(currencyFormatter.string(from: item.amount as NSDecimalNumber) ?? "$0.00")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct UpcomingPaymentsCard: View {
    let loans: [PrivateLoan]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Payments (30 days)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink("See Loans", destination: LoansView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            ForEach(loans.prefix(3), id: \.id) { loan in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loan.loanName)
                            .font(.subheadline).fontWeight(.semibold)
                        if let lender = loan.lenderName { Text(lender).font(.caption).foregroundColor(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(currencyFormatter.string(from: loan.monthlyPayment as NSDecimalNumber) ?? "$0.00")
                            .font(.subheadline).fontWeight(.semibold)
                        if let next = loan.nextPaymentDate { Text(next, style: .date).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct UpcomingGoalsCard: View {
    let goals: [Goal]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Goals")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                NavigationLink("See All", destination: GoalsView())
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(goals.prefix(3), id: \.id) { goal in
                    GoalRowView(goal: goal)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct SyncStatusBanner: View {
    let isVisible: Bool
    let message: String
    
    var body: some View {
        if isVisible {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct OfflineBanner: View {
    let onReconnect: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text("Offline — changes will sync when you’re back online.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Reconnect") { onReconnect() }
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}

private var currencyFormatter: NumberFormatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    formatter.currencyCode = code.isEmpty ? "USD" : code
    return formatter
}

#Preview {
    DashboardView()
}