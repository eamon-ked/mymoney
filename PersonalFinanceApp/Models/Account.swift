//
//  Account.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

enum AccountType: String, CaseIterable, Codable {
    case checking = "checking"
    case savings = "savings"
    case creditCard = "credit_card"
    case cash = "cash"
    case investment = "investment"
    
    var displayName: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .creditCard: return "Credit Card"
        case .cash: return "Cash"
        case .investment: return "Investment"
        }
    }
}

@Model
final class Account {
    var id: UUID
    var userId: UUID?
    var name: String
    var type: AccountType
    var balance: Decimal
    var currency: String
    var accountNumber: String?
    var institutionName: String?
    var color: String
    var isActive: Bool
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []
    
    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        type: AccountType,
        balance: Decimal = 0,
        currency: String = "USD",
        accountNumber: String? = nil,
        institutionName: String? = nil,
        color: String = "#007AFF",
        isActive: Bool = true,
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.balance = balance
        self.currency = currency
        self.accountNumber = accountNumber
        self.institutionName = institutionName
        self.color = color
        self.isActive = isActive
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}