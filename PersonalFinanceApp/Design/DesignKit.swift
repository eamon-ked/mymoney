//
//  DesignKit.swift
//  Nokael Money
//
//  Shared building blocks: one summary banner per screen, native grouped
//  lists, two-line rows with the key number on the right, and every headline
//  figure tappable for its explanation.
//

import SwiftUI
import NokaelCore

// MARK: - Formatting

extension Money {
    /// Full precision, e.g. "AED 1,250.50"
    var formatted: String { MoneyFormat.string(self) }
    /// Drops ".00" on whole amounts, for rows and pills
    var compact: String { MoneyFormat.string(self, dropWholeFraction: true) }
    /// With an explicit sign for changes, e.g. "+AED 50" / "−AED 85"
    var signed: String {
        if isZero { return compact }
        return (isNegative ? "−" : "+") + magnitude.compact
    }
}

enum Palette {
    static let positive = Color.green
    static let negative = Color.red
    static let warning = Color.orange
    static let home = Color(red: 0.20, green: 0.36, blue: 0.85)
    static let budget = Color(red: 0.13, green: 0.60, blue: 0.40)
    static let activity = Color(red: 0.93, green: 0.50, blue: 0.16)
    static let accounts = Color(red: 0.36, green: 0.33, blue: 0.85)
    static let plan = Color(red: 0.05, green: 0.58, blue: 0.62)
}

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
        case .income: return "Income"
        case .expense: return "Spending"
        case .equity: return "Adjustments"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 3: (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        default: (r, g, b) = (128, 128, 128)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// MARK: - Banner

/// The coloured block at the top of each tab. Tapping it explains the number.
struct SummaryBanner<Footer: View>: View {
    let title: String
    let amount: String
    var caption: String? = nil
    /// Said loudly under the amount, e.g. "Short by AED 103.33"
    var alert: String? = nil
    var tint: Color
    var action: (() -> Void)? = nil
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Shows how this number is worked out")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .opacity(0.9)
            Text(amount)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            if let alert {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.22)))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .opacity(0.9)
            }
            footer()
            if action != nil {
                Label("How is this worked out?", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
                    .opacity(0.9)
            }
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(tint.gradient)
    }
}

extension SummaryBanner where Footer == EmptyView {
    init(title: String, amount: String, caption: String? = nil, alert: String? = nil, tint: Color, action: (() -> Void)? = nil) {
        self.init(title: title, amount: amount, caption: caption, alert: alert, tint: tint, action: action, footer: { EmptyView() })
    }
}

/// Small figures under a banner headline
struct BannerFigures: View {
    let figures: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(figures, id: \.label) { f in
                VStack(spacing: 2) {
                    Text(f.value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(f.label).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
    }
}

extension View {
    /// Places a banner edge to edge as a list row
    func bannerRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

// MARK: - Rows

struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol.isEmpty ? "circle" : symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Icon, title, caption and something on the right
struct ListRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var symbol: String? = nil
    var color: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { IconBadge(symbol: symbol, color: color) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(2)
                if let caption, !caption.isEmpty {
                    Text(caption).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            trailing().layoutPriority(1)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum PillStyle { case neutral, positive, negative, warning }

struct AmountPill: View {
    let text: String
    var style: PillStyle = .neutral

    init(_ money: Money, style: PillStyle? = nil) {
        self.text = money.compact
        self.style = style ?? (money.isNegative ? .negative : .neutral)
    }

    /// A card or loan balance: what's owed, as a positive amount and in words, never a minus sign
    init(owed balance: Money) {
        self.text = balance.isNegative ? "\(balance.magnitude.compact) owed" : balance.compact
        self.style = balance.isNegative ? .warning : .neutral
    }

    init(text: String, style: PillStyle = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .negative: return .white
        case .positive: return .green
        case .warning: return .orange
        case .neutral: return .primary
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return Color.gray.opacity(0.15)
        case .positive: return Color.green.opacity(0.15)
        case .warning: return Color.orange.opacity(0.15)
        case .negative: return .red
        }
    }
}

/// Posted, scheduled, estimate, overdue, stale…
struct StatusBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().stroke(color.opacity(0.5)))
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = .green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.18))
                Capsule().fill(tint).frame(width: geo.size.width * CGFloat(min(max(value.isFinite ? value : 0, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int((value.isFinite ? value : 0) * 100)) percent")
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// An error shown right under the field it's about
struct FieldError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Explanations

/// A plain-language explanation of a number: definition, then every part it's made of
struct Explanation: Identifiable {
    let id = UUID()
    let title: String
    let total: Money?
    let definition: String
    var sections: [(heading: String, items: [BreakdownItem], sign: String)] = []
    var notes: [String] = []
}

struct ExplanationSheet: View {
    let explanation: Explanation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let total = explanation.total {
                        Text(total.formatted).font(.title.bold()).monospacedDigit()
                    }
                    Text(explanation.definition).font(.subheadline)
                }
                ForEach(explanation.sections, id: \.heading) { section in
                    Section(section.heading) {
                        if section.items.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        }
                        ForEach(section.items) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.label)
                                    if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(section.sign + item.amount.compact).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !explanation.notes.isEmpty {
                    Section("Good to know") {
                        ForEach(explanation.notes, id: \.self) { Text($0).font(.footnote) }
                    }
                }
            }
            .navigationTitle(explanation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
