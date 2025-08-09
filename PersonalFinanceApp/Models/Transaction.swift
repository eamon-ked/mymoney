//
//  Transaction.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

enum TransactionType: String, CaseIterable, Codable {
    case income = "income"
    case expense = "expense"
    case transfer = "transfer"
    
    var displayName: String {
        switch self {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }
}

@Model
final class Transaction {
    var id: UUID
    var userId: UUID?
    var accountId: UUID
    var categoryId: UUID?
    var amount: Decimal
    var type: TransactionType
    var transactionDescription: String
    var notes: String?
    var transactionDate: Date
    var isRecurring: Bool
    var recurringFrequency: String?
    var tags: [String]
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship
    var account: Account?
    
    @Relationship
    var category: Category?
    
    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        accountId: UUID,
        categoryId: UUID? = nil,
        amount: Decimal,
        type: TransactionType,
        transactionDescription: String,
        notes: String? = nil,
        transactionDate: Date = Date(),
        isRecurring: Bool = false,
        recurringFrequency: String? = nil,
        tags: [String] = [],
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.accountId = accountId
        self.categoryId = categoryId
        self.amount = amount
        self.type = type
        self.transactionDescription = transactionDescription
        self.notes = notes
        self.transactionDate = transactionDate
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.tags = tags
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}