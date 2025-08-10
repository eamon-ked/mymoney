//
//  CategoryRepository.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine

@MainActor
class CategoryRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var categories: [Category] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadCategories()
        ensureUniqueCategories()
        // Create defaults only once (and avoid server duplicates by checking remote first)
        Task { await seedDefaultsIfNeeded() }
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
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func updateCategory(_ category: Category) {
        do {
            category.syncStatus = "pending"
            try localDB.save()
            loadCategories()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteCategory(_ category: Category) {
        do {
            try localDB.delete(category)
            loadCategories()
            
            // Trigger debounced sync instead of immediate sync
            syncManager.triggerSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func getCategoriesByType(_ type: CategoryType) -> [Category] {
        // Deduplicate by id to avoid ForEach warnings if defaults were seeded multiple times previously
        var seen = Set<UUID>()
        var unique: [Category] = []
        for category in categories where category.type == type {
            if !seen.contains(category.id) {
                seen.insert(category.id)
                unique.append(category)
            }
        }
        return unique
    }
    
    func getCategory(by id: UUID) -> Category? {
        return categories.first { $0.id == id }
    }
    
    private func ensureUniqueCategories() {
        // Remove duplicates by id if they exist in the persistent store
        var seen = Set<UUID>()
        var duplicates: [Category] = []
        for category in categories {
            if seen.contains(category.id) {
                duplicates.append(category)
            } else {
                seen.insert(category.id)
            }
        }
        guard !duplicates.isEmpty else { return }
        do {
            for dup in duplicates {
                try localDB.delete(dup)
            }
            loadCategories()
        } catch {
            // Best-effort cleanup; ignore errors
        }
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
        
        // Avoid duplicate IDs across runs: generate new UUIDs
        for template in defaultCategories {
            let category = Category(
                id: UUID(),
                userId: template.userId,
                name: template.name,
                type: template.type,
                color: template.color,
                icon: template.icon,
                isDefault: true,
                syncStatus: template.syncStatus,
                lastSyncedAt: template.lastSyncedAt,
                createdAt: template.createdAt
            )
            addCategory(category)
        }
    }

    private func categoryExistsRemotely(name: String, type: CategoryType) async -> Bool {
        do {
            let rows = try await SupabaseManager.shared.fetchCategories(lastSyncedAt: nil)
            let exists = rows.contains { row in
                (row["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame &&
                (row["type"] as? String) == type.rawValue
            }
            return exists
        } catch { return false }
    }

    private func seedDefaultsIfNeeded() async {
        guard categories.isEmpty else { return }
        // Check remote to avoid duplicates across devices
        let defaults: [(String, CategoryType, String, String)] = [
            ("Salary", .income, "#4CAF50", "dollarsign.circle"),
            ("Freelance", .income, "#2196F3", "briefcase"),
            ("Investment", .income, "#FF9800", "chart.line.uptrend.xyaxis"),
            ("Other Income", .income, "#9C27B0", "plus.circle"),
            ("Food & Dining", .expense, "#F44336", "fork.knife"),
            ("Transportation", .expense, "#3F51B5", "car"),
            ("Shopping", .expense, "#E91E63", "bag"),
            ("Entertainment", .expense, "#9C27B0", "tv"),
            ("Bills & Utilities", .expense, "#607D8B", "bolt"),
            ("Healthcare", .expense, "#4CAF50", "cross.case"),
            ("Education", .expense, "#FF5722", "book"),
            ("Travel", .expense, "#00BCD4", "airplane"),
            ("Other Expenses", .expense, "#795548", "minus.circle")
        ]
        var createdAny = false
        for (name, type, color, icon) in defaults {
            let exists = await categoryExistsRemotely(name: name, type: type)
            if exists { continue }
            let category = Category(
                id: UUID(),
                name: name,
                type: type,
                color: color,
                icon: icon,
                isDefault: true
            )
            addCategory(category)
            createdAny = true
        }
        if createdAny { loadCategories() }
    }
}