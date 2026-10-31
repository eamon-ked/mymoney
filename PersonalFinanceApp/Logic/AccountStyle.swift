//
//  AccountStyle.swift
//  Nokael Money
//
//  The default icon, name and colour for each kind of account, used when
//  one is added or its type changes.
//

import Foundation
import NokaelCore

enum AccountStyle {
    static func icon(for kind: AccountKind) -> String {
        switch kind {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .savings: return "lock.fill"
        case .creditCard: return "creditcard.fill"
        case .loan: return "doc.text.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .otherAsset: return "shippingbox.fill"
        case .lent: return "person.crop.circle.badge.clock"
        case .income: return "arrow.down.circle.fill"
        case .expense: return "tag.fill"
        case .equity: return "scalemass.fill"
        }
    }

    static func name(for kind: AccountKind) -> String {
        switch kind {
        case .cash: return "Cash"
        case .bank: return "Bank account"
        case .savings: return "Savings account"
        case .creditCard: return "Credit card"
        case .loan: return "Loan"
        case .investment: return "Investment"
        case .otherAsset: return "Other asset"
        case .lent: return "Money lent"
        case .income: return "Income"
        case .expense: return "Spending"
        case .equity: return "Adjustments"
        }
    }
}

enum AccountColors {
    static func next(for kind: AccountKind) -> String {
        switch kind {
        case .bank: return "#3A7BD5"
        case .cash: return "#2BA84A"
        case .savings: return "#0E9AA7"
        case .creditCard: return "#E4572E"
        case .loan: return "#8E44AD"
        case .investment: return "#5B6CFF"
        case .lent: return "#FF9500"
        default: return "#8E8E93"
        }
    }
}
