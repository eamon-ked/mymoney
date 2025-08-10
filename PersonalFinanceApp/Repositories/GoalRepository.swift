//
//  GoalRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

@MainActor
class GoalRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var goals: [Goal] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadGoals()
    }
    
    func loadGoals() {
        isLoading = true
        error = nil
        
        do {
            goals = try localDB.fetchGoals()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addGoal(_ goal: Goal) {
        do {
            try localDB.insert(goal)
            loadGoals()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateGoal(_ goal: Goal) {
        do {
            goal.updatedAt = Date()
            goal.syncStatus = "pending"
            try localDB.save()
            loadGoals()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteGoal(_ goal: Goal) {
        do {
            try localDB.delete(goal)
            loadGoals()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateGoalProgress(_ goal: Goal, amount: Decimal) {
        goal.currentAmount = amount
        updateGoal(goal)
    }
    
    func addToGoalProgress(_ goal: Goal, amount: Decimal) {
        goal.currentAmount += amount
        updateGoal(goal)
    }
    
    func getActiveGoals() -> [Goal] {
        return goals.filter { $0.status == "active" }
    }
    
    func getCompletedGoals() -> [Goal] {
        return goals.filter { $0.status == "completed" }
    }
    
    func getGoalsByCategory(_ category: String) -> [Goal] {
        return goals.filter { $0.category == category }
    }
    
    func getUpcomingGoals() -> [Goal] {
        let now = Date()
        let thirtyDaysFromNow = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        
        return goals.filter { goal in
            guard let targetDate = goal.targetDate else { return false }
            return targetDate >= now && targetDate <= thirtyDaysFromNow && goal.status == "active"
        }
    }
}