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
    /// Rounded to whole units, for the big figure on a summary card, e.g. "AED 1,216"
    var whole: String {
        let unit = Int64((0..<Currency.scale(of: currency)).reduce(1) { r, _ in r * 10 })
        let rounded = (minorUnits + (minorUnits < 0 ? -unit : unit) / 2) / unit * unit
        return Money(minorUnits: rounded, currency: currency).compact
    }
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
    /// The one brand colour: every hero card, every main action. Red and orange are only for alerts.
    static let brand = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.16, green: 0.55, blue: 0.53, alpha: 1)
        : UIColor(red: 0.04, green: 0.40, blue: 0.40, alpha: 1) })
    /// Warm off-white behind the cards; deep neutral at night
    static let canvas = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        : UIColor(red: 0.965, green: 0.957, blue: 0.94, alpha: 1) })
    static let home = brand
    static let budget = brand
    static let activity = brand
    static let accounts = brand
    static let plan = brand
}

extension View {
    /// The calm canvas every tab sits on
    func canvas() -> some View {
        scrollContentBackground(.hidden).background(Palette.canvas.ignoresSafeArea())
    }
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

/// The hero card at the top of each tab: one title, one number, at most one line under it.
/// Tapping it explains the number.
struct SummaryBanner<Footer: View>: View {
    let title: String
    let amount: String
    var caption: String? = nil
    /// Said loudly under the amount, e.g. "Short by AED 103.33"
    var alert: String? = nil
    var tint: Color
    var action: (() -> Void)? = nil
    /// A soft glow, kept for Home so the first screen feels alive
    var glow: Bool = false
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .opacity(0.85)
            AmountText(amount, size: 40)
                .contentTransition(.numericText())
            if let alert {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .opacity(0.8)
            }
            footer()
            if action != nil {
                HStack(spacing: 4) {
                    Text("How it's calculated")
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .opacity(0.85)
                .padding(.top, 4)
            }
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .padding(.horizontal, 22)
        .background {
            if glow {
                LinearGradient(colors: [tint, Color(red: 0.10, green: 0.55, blue: 0.58), Color(red: 0.03, green: 0.30, blue: 0.33)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                tint
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

extension SummaryBanner where Footer == EmptyView {
    init(title: String, amount: String, caption: String? = nil, alert: String? = nil, tint: Color,
         action: (() -> Void)? = nil, glow: Bool = false) {
        self.init(title: title, amount: amount, caption: caption, alert: alert, tint: tint, action: action, glow: glow,
                  footer: { EmptyView() })
    }
}

/// A big figure with the currency code or symbol set smaller, in any locale: "AED 561", "561 €", "-$12"
struct AmountText: View {
    let amount: String
    var size: CGFloat

    init(_ amount: String, size: CGFloat) {
        self.amount = amount
        self.size = size
    }

    var body: some View {
        Text(styled)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var styled: AttributedString {
        var out = AttributedString()
        // Digits, signs and separators stay big; the currency part is set smaller
        let big: (Character) -> Bool = { $0.isNumber || "-−+.,'\u{00A0}\u{202F} ".contains($0) }
        var run = ""
        var runIsBig: Bool?
        func flush() {
            guard let isBig = runIsBig, !run.isEmpty else { return }
            var part = AttributedString(run)
            part.font = .system(size: isBig ? size : size * 0.55, weight: .bold, design: .rounded)
            out += part
        }
        // A hyphen reads as a dash at this size; use a true minus sign
        for ch in amount.replacingOccurrences(of: "-", with: "\u{2212}") {
            let b = big(ch)
            if b != runIsBig { flush(); run = ""; runIsBig = b }
            run.append(ch)
        }
        flush()
        return out
    }
}

/// One soft note under a hero card, when a screen has exactly one thing worth saying
struct NoteCard: View {
    let text: String
    var symbol = "info.circle"
    var link: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text).foregroundStyle(.primary)
                    if let link {
                        HStack(spacing: 4) {
                            Text(link)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.brand)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
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
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol.isEmpty ? "circle" : symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color))
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
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum PillStyle { case neutral, positive, negative, warning }

struct AmountPill: View {
    let text: String
    var style: PillStyle = .neutral
    /// A word under the amount, e.g. "owed"
    var note: String? = nil

    init(_ money: Money, style: PillStyle? = nil) {
        self.text = money.compact
        self.style = style ?? (money.isNegative ? .negative : .neutral)
    }

    /// A card or loan balance: what's owed, as a positive amount and in words, never a minus sign
    init(owed balance: Money) {
        self.text = balance.isNegative ? balance.magnitude.compact : balance.compact
        self.style = .neutral
        self.note = balance.isNegative ? "owed" : nil
    }

    init(text: String, style: PillStyle = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        if let note {
            VStack(alignment: .trailing, spacing: 1) {
                amount
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            amount
        }
    }

    private var amount: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .negative ? 8 : 0)
            .padding(.vertical, style == .negative ? 3 : 0)
            .background(Capsule().fill(style == .negative ? Color.red : .clear))
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
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.brand)
                .padding(.bottom, 4)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.brand)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
