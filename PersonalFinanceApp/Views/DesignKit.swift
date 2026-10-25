//
//  DesignKit.swift
//  PersonalFinanceApp
//
//  Shared building blocks so every tab looks like the Budget tab: one summary
//  banner on top, native grouped lists, two-line rows with the key number in
//  a pill on the right.
//

import SwiftUI

// MARK: - Money helpers

/// Like formatMoney, but drops ".00" on whole amounts so rows stay readable
func formatMoneyCompact(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "AED"
    formatter.currencyCode = code.isEmpty ? "AED" : code
    var rounded = Decimal()
    var copy = value
    NSDecimalRound(&rounded, &copy, 0, .plain)
    if rounded == value { formatter.maximumFractionDigits = 0 }
    return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}

enum Money {
    static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func parse(_ text: String) -> Decimal? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Summary banner

/// The coloured block at the top of each tab
struct SummaryBanner: View {
    let amount: Decimal
    let title: String
    var tint: Color = .accentColor
    var details: [(label: String, value: String)] = []

    var body: some View {
        VStack(spacing: 6) {
            Text(formatMoney(amount))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.subheadline)
            if !details.isEmpty {
                HStack(spacing: 16) {
                    ForEach(details, id: \.label) { item in
                        VStack(spacing: 2) {
                            Text(item.value)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(item.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .opacity(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
        .monospacedDigit()
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(tint)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Places a SummaryBanner edge to edge as the first list row
    func bannerRow() -> some View {
        listRowInsets(EdgeInsets())
    }
}

// MARK: - Rows

/// Round coloured icon used at the start of rows
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white)
            )
            .accessibilityHidden(true)
    }
}

enum PillStyle {
    case neutral, positive, negative, plain
}

/// The key number on the right of a row
struct AmountPill: View {
    let text: String
    var style: PillStyle = .neutral

    init(_ amount: Decimal, style: PillStyle? = nil) {
        self.text = formatMoneyCompact(amount)
        self.style = style ?? (amount < 0 ? .negative : .neutral)
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
            .foregroundColor(foreground)
            .padding(.horizontal, style == .plain ? 0 : 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .negative: return .white
        case .positive: return .green
        default: return .primary
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return Color.gray.opacity(0.15)
        case .positive: return Color.green.opacity(0.15)
        case .negative: return .red
        case .plain: return .clear
        }
    }
}

/// Icon, title, caption and a trailing view: the standard two-line row
struct ListRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var symbol: String? = nil
    var color: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                IconBadge(symbol: symbol, color: color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Slim progress bar for goals and loans
struct ProgressBar: View {
    let value: Double
    var tint: Color = .green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(max(value.isFinite ? value : 0, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int((value.isFinite ? value : 0) * 100)) percent")
    }
}

/// Shown in a section when it has nothing yet
struct EmptyStateRow: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
