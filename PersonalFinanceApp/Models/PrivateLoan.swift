//
//  PrivateLoan.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import SwiftData

@Model
final class PrivateLoan: Identifiable {
    var id: UUID
    var userId: UUID?
    var loanName: String
    var loanType: String?
    var lenderName: String?
    var originalAmount: Decimal
    var remainingBalance: Decimal
    var interestRate: Decimal
    var monthlyPayment: Decimal
    var startDate: Date
    var endDate: Date?
    var nextPaymentDate: Date?
    var status: String
    var syncStatus: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    
    var progress: Double {
        let original = Double(truncating: originalAmount as NSDecimalNumber)
        let remaining = Double(truncating: remainingBalance as NSDecimalNumber)
        return original > 0 ? max(0, (original - remaining) / original) : 0.0
    }
    
    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        loanName: String,
        loanType: String? = nil,
        lenderName: String? = nil,
        originalAmount: Decimal,
        remainingBalance: Decimal,
        interestRate: Decimal,
        monthlyPayment: Decimal,
        startDate: Date = Date(),
        endDate: Date? = nil,
        nextPaymentDate: Date? = nil,
        status: String = "active",
        syncStatus: String = "pending",
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.loanName = loanName
        self.loanType = loanType
        self.lenderName = lenderName
        self.originalAmount = originalAmount
        self.remainingBalance = remainingBalance
        self.interestRate = interestRate
        self.monthlyPayment = monthlyPayment
        self.startDate = startDate
        self.endDate = endDate
        self.nextPaymentDate = nextPaymentDate
        self.status = status
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}