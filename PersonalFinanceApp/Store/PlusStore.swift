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
    // In the order the paywall lists them: automation first, then foresight and intelligence
    case autoCapture, statementImport, appleIntelligence, moneyAhead, reports, payoffPlanner, goals, widget
    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoCapture: return "Automatic transaction capture"
        case .statementImport: return "Unlimited statement imports"
        case .appleIntelligence: return "Unlimited money assistant"
        case .moneyAhead: return "60-day cash flow forecast"
        case .reports: return "Advanced reports and trends"
        case .widget: return "Home screen widget"
        case .goals: return "Unlimited savings goals"
        case .payoffPlanner: return "Debt payoff simulations"
        }
    }

    var detail: String {
        switch self {
        case .autoCapture: return "Apple Pay purchases and bank SMS alerts recorded for you, ready to check"
        case .statementImport: return "Import as often as you like. The first for each account is free"
        case .appleIntelligence:
            // Only promise the cloud model where this iPhone can actually reach it
            return [.ready, .limitReached].contains(AppleIntelligence.cloudStatus)
                ? "Ask as much as you like, answered by Apple's larger cloud model. Free has \(FreePlan.askPerMonth) questions a month"
                : "Ask as much as you like and add from a sentence. Free has \(FreePlan.askPerMonth) questions a month"
        case .moneyAhead: return "Your balance day by day for the next 60 days"
        case .reports: return "Every month, and six months side by side. Free has the last \(FreePlan.reportMonths)"
        case .widget: return "Safe to spend and the next bills at a glance"
        case .goals: return "Save for as many things as you like. Free has \(FreePlan.goals)"
        case .payoffPlanner: return "See how much sooner you're debt-free paying a little extra"
        }
    }

    var symbol: String {
        switch self {
        case .autoCapture: return "wallet.pass"
        case .statementImport: return "square.and.arrow.down"
        case .appleIntelligence: return "sparkles"
        case .moneyAhead: return "chart.line.uptrend.xyaxis"
        case .reports: return "chart.bar.xaxis"
        case .widget: return "rectangle.grid.2x2"
        case .goals: return "target"
        case .payoffPlanner: return "flag.checkered"
        }
    }
}

/// Where the free app is limited rather than locked: Plus removes these limits.
/// Free covers everything needed to keep an accurate picture; Plus saves work.
enum FreePlan {
    /// Savings goals with a target; set-asides are always unlimited
    static let goals = 3
    /// This month and the two before it in Reports
    static let reportMonths = 3
    /// Questions to Ask each month
    static let askPerMonth = 3
    /// "Describe it in a sentence" uses each month
    static let describePerMonth = 10
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
        #if DEBUG && targetEnvironment(simulator)
        forced = CommandLine.arguments.contains("-plus")
        #elseif DEBUG
        // On a test iPhone, launching once with -plus keeps Plus on, so Siri and
        // Shortcuts (which launch without arguments) see it too; -noPlus undoes it
        let defaults = UserDefaults.standard
        if CommandLine.arguments.contains("-plus") { defaults.set(true, forKey: "debugForcePlus") }
        if CommandLine.arguments.contains("-noPlus") { defaults.removeObject(forKey: "debugForcePlus") }
        forced = defaults.bool(forKey: "debugForcePlus")
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
