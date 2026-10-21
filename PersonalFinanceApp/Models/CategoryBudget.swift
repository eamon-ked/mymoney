//
//  CategoryBudget.swift
//  PersonalFinanceApp
//
//  Money assigned to one category for one month. Everything else in the
//  budget (Ready to Assign, Available, Spent) is derived, never stored.
//

import Foundation
import SwiftData

@Model
final class CategoryBudget {
    var id: UUID
    var userId: UUID?
    var categoryId: UUID
    /// Calendar month in the user's time zone, "yyyy-MM"
    var month: String
    var assigned: Decimal
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date? = nil

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        categoryId: UUID,
        month: String,
        assigned: Decimal = 0,
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.categoryId = categoryId
        self.month = month
        self.assigned = assigned
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
