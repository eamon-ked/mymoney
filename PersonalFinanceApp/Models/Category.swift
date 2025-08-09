//
//  Category.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

enum CategoryType: String, CaseIterable, Codable {
    case income = "income"
    case expense = "expense"
    
    var displayName: String {
        switch self {
        case .income: return "Income"
        case .expense: return "Expense"
        }
    }
}

@Model
final class Category {
    var id: UUID
    var userId: UUID?
    var name: String
    var type: CategoryType
    var color: String
    var icon: String
    var isDefault: Bool
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []
    
    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        type: CategoryType,
        color: String = "#007AFF",
        icon: String = "folder",
        isDefault: Bool = false,
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.color = color
        self.icon = icon
        self.isDefault = isDefault
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }
}