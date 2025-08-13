//
//  Goal.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

@Model
final class Goal: Identifiable {
    var id: UUID
    var userId: UUID?
    var title: String
    var goalDescription: String?
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date?
    var category: String?
    var priority: String?
    var status: String
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    var progress: Double {
        let target = Double(truncating: targetAmount as NSDecimalNumber)
        let current = Double(truncating: currentAmount as NSDecimalNumber)
        guard target.isFinite, current.isFinite, target > 0 else { return 0.0 }
        let ratio = current / target
        if !ratio.isFinite || ratio.isNaN { return 0.0 }
        return min(max(ratio, 0.0), 1.0)
    }
    
    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        title: String,
        goalDescription: String? = nil,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        category: String? = nil,
        priority: String? = nil,
        status: String = "active",
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.goalDescription = goalDescription
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.category = category
        self.priority = priority
        self.status = status
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}