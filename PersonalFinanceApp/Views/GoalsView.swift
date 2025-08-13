//
//  GoalsView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct GoalsView: View {
    @StateObject private var repository = GoalRepository()
    @State private var showingAddGoal = false
    @State private var showingUpdateGoal = false
    @State private var goalToUpdate: Goal? = nil
    
    var body: some View {
        NavigationView {
            List {
                ForEach(repository.goals, id: \.id) { goal in
                    GoalRowView(goal: goal)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                repository.deleteGoal(goal)
                            }
                            Button("Update") {
                                goalToUpdate = goal
                                showingUpdateGoal = true
                            }
                        }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGoal = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView(repository: repository)
            }
            .sheet(isPresented: $showingUpdateGoal) {
                if let goal = goalToUpdate {
                    UpdateGoalProgressView(repository: repository, goal: goal)
                }
            }
            .refreshable {
                repository.loadGoals()
            }
        }
    }
}

struct GoalRowView: View {
    let goal: Goal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let description = goal.goalDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let targetDate = goal.targetDate {
                        Text("Target: \(targetDate, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(currencyFormatter.string(from: goal.currentAmount as NSDecimalNumber) ?? "$0.00")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("of \(currencyFormatter.string(from: goal.targetAmount as NSDecimalNumber) ?? "$0.00")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if goal.syncStatus == "pending" {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(goal.progress * 100))% Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let category = goal.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                
                ProgressView(value: goal.progress.isFinite ? goal.progress : 0.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
            }
        }
        .padding(.vertical, 8)
    }
    
    private var progressColor: Color {
        if goal.progress >= 1.0 {
            return .green
        } else if goal.progress >= 0.7 {
            return .blue
        } else if goal.progress >= 0.3 {
            return .orange
        } else {
            return .red
        }
    }
}

struct AddGoalView: View {
    @ObservedObject var repository: GoalRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var description = ""
    @State private var targetAmount = ""
    @State private var currentAmount = ""
    @State private var targetDate = Date().addingTimeInterval(365 * 24 * 60 * 60) // 1 year from now
    @State private var hasTargetDate = true
    @State private var category = ""
    @State private var priority = "Medium"
    
    private let priorities = ["Low", "Medium", "High"]
    private let categories = ["Emergency Fund", "Vacation", "Car", "House", "Education", "Retirement", "Other"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Goal Details") {
                    TextField("Goal Title", text: $title)
                    
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Target Amount", text: $targetAmount)
                        .keyboardType(.decimalPad)
                    
                    TextField("Current Amount", text: $currentAmount)
                        .keyboardType(.decimalPad)
                }
                
                Section("Timeline") {
                    Toggle("Set Target Date", isOn: $hasTargetDate)
                    
                    if hasTargetDate {
                        DatePicker("Target Date", selection: $targetDate, displayedComponents: .date)
                    }
                }
                
                Section("Category & Priority") {
                    Picker("Category", selection: $category) {
                        Text("Select Category").tag("")
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { pri in
                            Text(pri).tag(pri)
                        }
                    }
                }
            }
            .navigationTitle("Add Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !title.isEmpty && !targetAmount.isEmpty
    }
    
    private func saveGoal() {
        guard let targetAmountDecimal = Decimal(string: targetAmount) else {
            return
        }
        
        let currentAmountDecimal = Decimal(string: currentAmount) ?? 0
        
        let goal = Goal(
            title: title,
            goalDescription: description.isEmpty ? nil : description,
            targetAmount: targetAmountDecimal,
            currentAmount: currentAmountDecimal,
            targetDate: hasTargetDate ? targetDate : nil,
            category: category.isEmpty ? nil : category,
            priority: priority
        )
        
        repository.addGoal(goal)
        dismiss()
    }
}

struct UpdateGoalProgressView: View {
    @ObservedObject var repository: GoalRepository
    let goal: Goal
    @Environment(\.dismiss) private var dismiss

    @State private var newCurrentAmount: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Update Progress") {
                    TextField("New Current Amount", text: $newCurrentAmount)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Update Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(Decimal(string: newCurrentAmount) == nil)
                }
            }
            .onAppear { newCurrentAmount = (goal.currentAmount as NSDecimalNumber).stringValue }
        }
    }

    private func save() {
        guard let amount = Decimal(string: newCurrentAmount) else { return }
        repository.updateGoalProgress(goal, amount: amount)
        dismiss()
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
    GoalsView()
}