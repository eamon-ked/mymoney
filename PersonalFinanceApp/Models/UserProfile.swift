//
//  UserProfile.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var fullName: String
    var avatarUrl: String?
    var phone: String?
    var dateOfBirth: Date?
    var occupation: String?
    var annualIncome: Decimal?
    var creditScore: Int?
    var financialGoals: [String]
    var riskTolerance: String?
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        fullName: String,
        avatarUrl: String? = nil,
        phone: String? = nil,
        dateOfBirth: Date? = nil,
        occupation: String? = nil,
        annualIncome: Decimal? = nil,
        creditScore: Int? = nil,
        financialGoals: [String] = [],
        riskTolerance: String? = nil,
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.phone = phone
        self.dateOfBirth = dateOfBirth
        self.occupation = occupation
        self.annualIncome = annualIncome
        self.creditScore = creditScore
        self.financialGoals = financialGoals
        self.riskTolerance = riskTolerance
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}