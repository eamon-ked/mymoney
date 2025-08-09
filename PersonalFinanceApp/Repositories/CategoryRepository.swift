//
//  CategoryRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

class CategoryRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var categories: [Category] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadCategories()
        createDefaultCategories()
    }
    
    func loadCategories() {
        isLoading = true
        error = nil
        
        do {
            categories = try localDB.fetchCategories()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addCategory(_ category: Category) {
        do {
            try localDB.insert(category)
            loadCategories()
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateCategory(_ category: Category) {
        do {
            category.syncStatus = "pending"
            try localDB.save()
            loadCategories()
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteCategory(_ category: Category) {
        do {
            try localDB.delete(category)
            loadCategories()
            
            // Trigger sync in background
            Task {
                await syncManager.performSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func getCategoriesByType(_ type: CategoryType) -> [Category] {
        return categories.filter { $0.type == type }
    }
    
    func getCategory(by id: UUID) -> Category? {
        return categories.first { $0.id == id }
    }
    
    private func createDefaultCategories() {
        // Only create if no categories exist
        guard categories.isEmpty else { return }
        
        let defaultCategories = [
            // Income categories
            Category(name: "Salary", type: .income, color: "#4CAF50", icon: "dollarsign.circle"),
            Category(name: "Freelance", type: .income, color: "#2196F3", icon: "briefcase"),
            Category(name: "Investment", type: .income, color: "#FF9800", icon: "chart.line.uptrend.xyaxis"),
            Category(name: "Other Income", type: .income, color: "#9C27B0", icon: "plus.circle"),
            
            // Expense categories
            Category(name: "Food & Dining", type: .expense, color: "#F44336", icon: "fork.knife"),
            Category(name: "Transportation", type: .expense, color: "#3F51B5", icon: "car"),
            Category(name: "Shopping", type: .expense, color: "#E91E63", icon: "bag"),
            Category(name: "Entertainment", type: .expense, color: "#9C27B0", icon: "tv"),
            Category(name: "Bills & Utilities", type: .expense, color: "#607D8B", icon: "bolt"),
            Category(name: "Healthcare", type: .expense, color: "#4CAF50", icon: "cross.case"),
            Category(name: "Education", type: .expense, color: "#FF5722", icon: "book"),
            Category(name: "Travel", type: .expense, color: "#00BCD4", icon: "airplane"),
            Category(name: "Other Expenses", type: .expense, color: "#795548", icon: "minus.circle")
        ]
        
        for category in defaultCategories {
            category.isDefault = true
            addCategory(category)
        }
    }
}