//
//  GoalsView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

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
            .navigationTitle("New goal")
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
