//
//  PaywallView.swift
//  Nokael Money
//
//  What Nokael Plus adds and the three ways to get it. Prices come from the
//  App Store so they're always in the person's own currency.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(PlusStore.self) private var plus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The feature that was tapped, shown first
    var feature: PlusFeature? = nil

    @State private var selected = PlusStore.yearly
    @State private var trialEligible = false
    @State private var working = false
    @State private var error: String?

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://mymoney-legal-docs.pages.dev/privacy-policy.html")!

    private var features: [PlusFeature] {
        guard let feature else { return PlusFeature.allCases }
        return [feature] + PlusFeature.allCases.filter { $0 != feature }
    }

    private var selectedProduct: Product? { plus.products.first { $0.id == selected } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features) { f in
                            HStack(alignment: .top, spacing: 12) {
                                IconBadge(symbol: f.symbol, color: Palette.home)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.subheadline.weight(.semibold))
                                    Text(f.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    plans
                    if let error { FieldError(message: error) }
                    legal
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { buyBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Restore") { Task { await restore() } }.disabled(working)
                }
            }
            .task {
                if plus.products.isEmpty { await plus.loadProducts() }
                trialEligible = await plus.products.first { $0.id == PlusStore.yearly }?.subscription?.isEligibleForIntroOffer ?? false
            }
            .onChange(of: plus.isPlus) { _, isPlus in if isPlus { dismiss() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nokael Plus", systemImage: "star.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(Palette.home)
            // Two reasons, not a list: the list of features follows
            VStack(alignment: .leading, spacing: 6) {
                Label("It does the work for you", systemImage: "wand.and.stars")
                Label("It understands your money", systemImage: "sparkles")
            }
            .font(.headline)
            Text("Purchases saved automatically, statements imported, and answers to anything you ask.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var plans: some View {
        if plus.products.isEmpty {
            HStack(spacing: 8) {
                if plus.loadFailed {
                    Text("Couldn't reach the App Store. Check your connection and try again.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Retry") { Task { await plus.loadProducts() } }
                } else {
                    ProgressView()
                    Text("Loading prices…").foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(plus.products, id: \.id) { product in
                    PlanCard(product: product, selected: selected == product.id,
                             badge: product.id == PlusStore.yearly ? "Best value" : nil,
                             caption: caption(for: product)) { selected = product.id }
                }
            }
        }
    }

    private func caption(for product: Product) -> String {
        switch product.id {
        case PlusStore.yearly:
            let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            return trialEligible ? "1 week free, then \(product.displayPrice) a year (\(perMonth) a month)"
                                 : "\(product.displayPrice) a year, \(perMonth) a month"
        case PlusStore.monthly: return "\(product.displayPrice) a month"
        default: return "\(product.displayPrice) once, yours to keep"
        }
    }

    private var buyBar: some View {
        VStack(spacing: 6) {
            Button {
                Task { await buy() }
            } label: {
                Group {
                    if working { ProgressView().tint(.white) } else { Text(buyTitle).bold() }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProduct == nil || working)
            .accessibilityIdentifier("buyPlus")
            Text(selected == PlusStore.lifetime ? "One payment. No subscription." : "Cancel anytime in Settings › Apple Account › Subscriptions.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }

    private var buyTitle: String {
        if selected == PlusStore.yearly && trialEligible { return "Try free for 1 week" }
        if selected == PlusStore.lifetime { return "Buy lifetime" }
        return "Subscribe"
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account. Any unused part of a free trial ends when you subscribe.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Terms of Use") { openURL(Self.termsURL) }
                Button("Privacy Policy") { openURL(Self.privacyURL) }
            }
            .font(.caption)
        }
    }

    private func buy() async {
        guard let product = selectedProduct else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            if try await plus.purchase(product) { dismiss() }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "The purchase didn't go through. You haven't been charged."
        }
    }

    private func restore() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await plus.restore()
            if !plus.isPlus { error = "No Nokael Plus purchase was found for this Apple Account." }
        } catch {
            self.error = "Couldn't restore right now. Try again."
        }
    }
}

private struct PlanCard: View {
    let product: Product
    let selected: Bool
    let badge: String?
    let caption: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Palette.home : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.displayName).font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.home.opacity(0.15)))
                                .foregroundStyle(Palette.home)
                        }
                    }
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Palette.home : Color.gray.opacity(0.3), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small "PLUS" label beside locked features
struct PlusBadge: View {
    var body: some View {
        Text("PLUS")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Palette.home.opacity(0.15)))
            .foregroundStyle(Palette.home)
            .accessibilityLabel("Needs Nokael Plus")
    }
}

extension View {
    /// Presents the paywall when `feature` is set
    func paywall(_ feature: Binding<PlusFeature?>) -> some View {
        sheet(item: feature) { PaywallView(feature: $0) }
    }
}

/// Settings: the current plan, managing it, and restoring. The sheets live
/// on the Settings page, since sheets inside a Form section don't open.
struct PlusSection: View {
    @Environment(PlusStore.self) private var plus
    @Binding var showingPaywall: Bool
    @Binding var managing: Bool

    var body: some View {
        Section {
            if let plan = plus.currentPlan {
                LabeledContent("Nokael Plus", value: plan)
                if plan == "Monthly" || plan == "Yearly" {
                    Button("Manage subscription") { managing = true }
                }
            } else {
                Button { showingPaywall = true } label: {
                    Label("Get Nokael Plus", systemImage: "star.circle.fill")
                }
                Button("Restore purchases") { Task { try? await plus.restore() } }
            }
        } footer: {
            if plus.currentPlan == nil {
                Text("Apple Pay and bank SMS capture, statement import, Apple Intelligence, Money ahead, reports, the widget, unlimited goals and more.")
            }
        }
    }
}
