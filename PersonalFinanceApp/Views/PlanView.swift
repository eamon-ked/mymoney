//
//  PlanView.swift
//  PersonalFinanceApp
//
//  Plan tab: what you are saving towards and what you still owe.
//

import SwiftUI

struct PlanView: View {
    @StateObject private var goalRepository = GoalRepository()
    @StateObject private var loanRepository = LoanRepository()
    @State private var showingAddGoal = false
    @State private var showingAddLoan = false
    @State private var goalToUpdate: Goal?
    @State private var loanToUpdate: PrivateLoan?

    private var savedForGoals: Decimal {
        goalRepository.goals.reduce(Decimal(0)) { $0 + $1.currentAmount }
    }

    private var goalTargets: Decimal {
        goalRepository.goals.reduce(Decimal(0)) { $0 + $1.targetAmount }
    }

    private var owed: Decimal {
        loanRepository.loans.reduce(Decimal(0)) { $0 + $1.remainingBalance }
    }

    private var monthlyPayments: Decimal {
        loanRepository.loans.filter { $0.remainingBalance > 0 }.reduce(Decimal(0)) { $0 + $1.monthlyPayment }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    SummaryBanner(
                        amount: savedForGoals,
                        title: "Saved towards your goals",
                        tint: .teal,
                        details: [("Goal targets", formatMoneyCompact(goalTargets)),
                                  ("Still owed", formatMoneyCompact(owed)),
                                  ("Loan payments / mo", formatMoneyCompact(monthlyPayments))])
                    .bannerRow()
                }

                Section {
                    if goalRepository.goals.isEmpty {
                        EmptyStateRow(
                            symbol: "target",
                            title: "No goals yet",
                            message: "An emergency fund, a trip, a car: set a target and track how close you are.",
                            actionTitle: "Add goal") { showingAddGoal = true }
                    } else {
                        ForEach(goalRepository.goals, id: \.id) { goal in
                            Button { goalToUpdate = goal } label: { GoalRow(goal: goal) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) { goalRepository.deleteGoal(goal) }
                                }
                        }
                    }
                } header: {
                    Text("Goals")
                }

                Section {
                    if loanRepository.loans.isEmpty {
                        EmptyStateRow(
                            symbol: "banknote",
                            title: "No loans",
                            message: "Add a car loan or money you owe a friend to see what's left and when the next payment is due.",
                            actionTitle: "Add loan") { showingAddLoan = true }
                    } else {
                        ForEach(sortedLoans, id: \.id) { loan in
                            Button { loanToUpdate = loan } label: { LoanRow(loan: loan) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        withAnimation { loanRepository.deleteLoan(loan) }
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Loans")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingAddGoal = true } label: { Label("New goal", systemImage: "target") }
                        Button { showingAddLoan = true } label: { Label("New loan", systemImage: "banknote") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add goal or loan")
                }
            }
            .sheet(isPresented: $showingAddGoal) { AddGoalView(repository: goalRepository) }
            .sheet(isPresented: $showingAddLoan) { AddLoanView(repository: loanRepository) }
            .sheet(item: $goalToUpdate) { goal in UpdateGoalProgressView(repository: goalRepository, goal: goal) }
            .sheet(item: $loanToUpdate) { loan in UpdateLoanProgressView(repository: loanRepository, loan: loan) }
            .onAppear {
                goalRepository.loadGoals()
                loanRepository.loadLoans()
            }
            .refreshable {
                goalRepository.loadGoals()
                loanRepository.loadLoans()
            }
        }
    }

    /// Next payment due first; paid-off loans last
    private var sortedLoans: [PrivateLoan] {
        loanRepository.loans.sorted { a, b in
            if (a.remainingBalance > 0) != (b.remainingBalance > 0) { return a.remainingBalance > 0 }
            return (a.nextPaymentDate ?? .distantFuture) < (b.nextPaymentDate ?? .distantFuture)
        }
    }
}

struct GoalRow: View {
    let goal: Goal

    private var caption: String {
        var parts = ["\(formatMoneyCompact(goal.currentAmount)) of \(formatMoneyCompact(goal.targetAmount))"]
        if let date = goal.targetDate {
            parts.append("by \(date.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListRow(title: goal.title, caption: caption, symbol: "target", color: .teal) {
                AmountPill(text: "\(Int(min(goal.progress, 1) * 100))%",
                           style: goal.progress >= 1 ? .positive : .neutral)
            }
            ProgressBar(value: goal.progress, tint: goal.progress >= 1 ? .green : .teal)
                .padding(.leading, 46)
        }
        .padding(.vertical, 4)
    }
}

struct LoanRow: View {
    let loan: PrivateLoan

    private var caption: String {
        if loan.remainingBalance <= 0 { return "Paid off" }
        var parts: [String] = []
        if let lender = loan.lenderName, !lender.isEmpty { parts.append(lender) }
        parts.append("\(formatMoneyCompact(loan.monthlyPayment))/mo")
        if let next = loan.nextPaymentDate { parts.append("next \(dueText(next))") }
        return parts.joined(separator: " · ")
    }

    private var isDueSoon: Bool {
        guard let next = loan.nextPaymentDate, loan.remainingBalance > 0 else { return false }
        return next.timeIntervalSinceNow < 7 * 24 * 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListRow(title: loan.loanName, caption: caption,
                    symbol: "banknote", color: isDueSoon ? .orange : .purple) {
                AmountPill(loan.remainingBalance, style: loan.remainingBalance <= 0 ? .positive : .neutral)
            }
            ProgressBar(value: loan.progress, tint: .purple)
                .padding(.leading, 46)
        }
        .padding(.vertical, 4)
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
