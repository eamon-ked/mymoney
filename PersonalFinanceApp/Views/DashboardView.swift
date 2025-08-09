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
                    // Sync status banner
                    if syncManager.isSyncing {
                        SyncStatusBanner(isVisible: true, message: "Syncing...")
                    } else if let lastSync = syncManager.lastSyncDate {
                        SyncStatusBanner(
                            isVisible: true,
                            message: "Last synced \(timeAgoString(from: lastSync))"
                        )
                    }
                    
                    // Net Worth Card
                    NetWorthCard(netWorth: viewModel.netWorth)
                    
                    // Monthly Overview
                    MonthlyOverviewCard(
                        income: viewModel.monthlyIncome,
                        expenses: viewModel.monthlyExpenses,
                        savings: viewModel.monthlySavings,
                        savingsRate: viewModel.savingsRate
                    )
                    
                    // Recent Transactions
                    RecentTransactionsCard(transactions: viewModel.recentTransactions)
                    
                    // Upcoming Goals
                    if !viewModel.upcomingGoals.isEmpty {
                        UpcomingGoalsCard(goals: viewModel.upcomingGoals)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await viewModel.refreshData()
            }
            .onAppear {
                viewModel.loadDashboardData()
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NetWorthCard: View {
    let netWorth: Decimal
    
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
            
            Text(currencyFormatter.string(from: netWorth as NSDecimalNumber) ?? "$0.00")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct MonthlyOverviewCard: View {
    let income: Decimal
    let expenses: Decimal
    let savings: Decimal
    let savingsRate: Double
    
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
                    Text(currencyFormatter.string(from: income as NSDecimalNumber) ?? "$0.00")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currencyFormatter.string(from: expenses as NSDecimalNumber) ?? "$0.00")
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
                Text(currencyFormatter.string(from: savings as NSDecimalNumber) ?? "$0.00")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(savings >= 0 ? .green : .red)
            }
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

private let currencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter
}()

#Preview {
    DashboardView()
}