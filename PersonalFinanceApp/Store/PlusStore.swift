//
//  PlusStore.swift
//  Nokael Money
//
//  Nokael Plus through StoreKit 2: a monthly or yearly subscription, or a
//  one-time lifetime purchase. Apple keeps the receipts; the app only asks
//  StoreKit what's currently owned, so it works offline and on new devices
//  after Restore.
//

import Foundation
import StoreKit

/// Features that need Nokael Plus, with how the paywall introduces each
enum PlusFeature: String, Identifiable, CaseIterable {
    case statementImport, appleIntelligence, moneyAhead, reports, widget, goals, payoffPlanner, export
    var id: String { rawValue }

    var title: String {
        switch self {
        case .statementImport: return "Import bank statements"
        case .appleIntelligence: return "Apple Intelligence"
        case .moneyAhead: return "Money ahead"
        case .reports: return "Reports"
        case .widget: return "Home screen widget"
        case .goals: return "Unlimited savings goals"
        case .payoffPlanner: return "Debt payoff planner"
        case .export: return "Export to a spreadsheet"
        }
    }

    var detail: String {
        switch self {
        case .statementImport: return "Bring in a CSV from your bank; what's already recorded is skipped"
        case .appleIntelligence: return "Add from a sentence, ask about your money, a monthly summary"
        case .moneyAhead: return "Your balance day by day for the next 60 days"
        case .reports: return "Where the money went, six months side by side"
        case .widget: return "Safe to spend and the next bills at a glance"
        case .goals: return "Save for as many things as you like"
        case .payoffPlanner: return "See how much sooner you're debt-free paying a little extra"
        case .export: return "Every entry as a CSV for your own records"
        }
    }

    var symbol: String {
        switch self {
        case .statementImport: return "square.and.arrow.down"
        case .appleIntelligence: return "sparkles"
        case .moneyAhead: return "chart.line.uptrend.xyaxis"
        case .reports: return "chart.bar.xaxis"
        case .widget: return "rectangle.grid.2x2"
        case .goals: return "target"
        case .payoffPlanner: return "flag.checkered"
        case .export: return "tablecells"
        }
    }
}

@MainActor @Observable
final class PlusStore {
    static let monthly = "nokael.plus.monthly"
    static let yearly = "nokael.plus.yearly"
    static let lifetime = "nokael.plus.lifetime"
    static let productIds = [yearly, monthly, lifetime]

    private(set) var products: [Product] = []
    /// Product ids currently owned
    private(set) var owned: Set<String> = []
    private(set) var loadFailed = false
    private var updates: Task<Void, Never>?
    private let forced: Bool

    var isPlus: Bool { forced || !owned.isEmpty }

    /// The plan that's active, for Settings
    var currentPlan: String? {
        if owned.contains(Self.lifetime) { return "Lifetime" }
        if owned.contains(Self.yearly) { return "Yearly" }
        if owned.contains(Self.monthly) { return "Monthly" }
        return forced ? "Test" : nil
    }

    init() {
        #if DEBUG
        forced = CommandLine.arguments.contains("-plus")
        #else
        forced = false
        #endif
        // Renewals, refunds and purchases made on another device arrive here
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh(); await loadProducts() }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIds)
            products = Self.productIds.compactMap { id in loaded.first { $0.id == id } }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    func refresh() async {
        var now: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if let expires = t.expirationDate, expires < Date() { continue }
            now.insert(t.productID)
        }
        owned = now
    }

    /// True when the purchase went through; false if cancelled or waiting for approval
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refresh()
            return true
        case .success(.unverified):
            throw PlusError.unverified
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }
}

enum PlusError: LocalizedError {
    case unverified
    var errorDescription: String? { "The App Store couldn't confirm this purchase. Try Restore purchases." }
}
