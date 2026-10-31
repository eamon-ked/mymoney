//
//  RedesignKit.swift
//  Nokael Money
//
//  The design's colours and building blocks, ported from the Figma
//  prototype ("Build missing app screens").
//

import SwiftUI

/// Namespace for the app's screens
enum Redesign {}

extension Redesign {
    enum Theme {
        static let background = Color(light: 0xF7F6F1, dark: 0x1D201B)
        static let foreground = Color(light: 0x202B26, dark: 0xF0EEE8)
        static let card = Color(light: 0xFDFCF8, dark: 0x262A23)
        static let primary = Color(light: 0x354E3C, dark: 0xA8B89D)
        static let onPrimary = Color(light: 0xFFFFFF, dark: 0x20281C)
        static let secondary = Color(light: 0xECECE4, dark: 0x30342B)
        static let muted = Color(light: 0x777C74, dark: 0xAAADA2)
        static let destructive = Color(light: 0xB45E58, dark: 0xE0887E)
        static let border = Color(light: 0xE7E7DE, dark: 0x3A3F34)
        static let warmFill = Color(light: 0xFFEBE1, dark: 0x43332B)
        static let warm = Color(light: 0xBD6845, dark: 0xE2A07B)
        static let coolFill = Color(light: 0xEAF0F1, dark: 0x2E3B3D)
        static let cool = Color(light: 0x4D6670, dark: 0xA0B7BD)
        static let amberFill = Color(light: 0xFBEFD9, dark: 0x433A29)
        static let amber = Color(light: 0x98723E, dark: 0xDCC398)
        static let sprout = Color(hex: 0xAD9A76)
        static let intelligence = LinearGradient(colors: [Color(hex: 0xB8C9FA), Color(hex: 0xD1B6EF), Color(hex: 0xF2BDAC)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

// MARK: - Type

extension Redesign {
    /// The preview's one type scale. Each role is used for the same kind of information on every screen,
    /// and every size grows with Dynamic Type from the system text style beside it.
    enum TextRole {
        /// The one figure a screen is about: safe to spend, a bill, a transaction, an amount being entered
        case display
        /// A total at the top of a tab or account
        case balance
        /// A balance inside a card or row
        case figure
        /// A tab's title, and the name in Home's greeting
        case title
        /// A headline inside a page
        case heading
        /// The heading above a card or list
        case section
        /// A row's or card's name
        case cardTitle
        /// Reading text and form values
        case body
        /// Button labels
        case label
        /// Labels, detail rows and supporting lines
        case detail
        /// A small heading inside a card
        case detailStrong
        /// Dates, notes and secondary lines
        case caption
        /// Inline links and status pills
        case captionStrong
        /// Small capitals over a group; the caller uppercases the text
        case overline
        /// The tab bar
        case nav
        /// An amount at the end of a row
        case amount
        /// A figure in a small summary tile
        case stat

        // (size at the default text size, weight, the text style it scales with, tracking, tabular digits)
        private var spec: (CGFloat, Font.Weight, UIFont.TextStyle, CGFloat, Bool) {
            switch self {
            case .display: (36, .regular, .largeTitle, -1.2, true)
            case .balance: (32, .regular, .largeTitle, -1, true)
            case .figure: (22, .medium, .title2, -0.5, true)
            case .title: (28, .medium, .title1, -0.8, false)
            case .heading: (22, .medium, .title2, -0.6, false)
            case .section: (17, .semibold, .headline, 0, false)
            case .cardTitle: (15, .medium, .subheadline, 0, false)
            case .body: (15, .regular, .subheadline, 0, false)
            case .label: (15, .medium, .subheadline, 0, false)
            case .detail: (13, .regular, .footnote, 0, false)
            case .detailStrong: (13, .medium, .footnote, 0, false)
            case .caption: (12, .regular, .caption1, 0, false)
            case .captionStrong: (12, .medium, .caption1, 0, false)
            case .overline: (12, .medium, .caption1, 1.2, false)
            case .nav: (11, .medium, .caption2, 0, false)
            case .amount: (13, .medium, .footnote, 0, true)
            case .stat: (16, .medium, .callout, 0, true)
            }
        }

        var tracking: CGFloat { spec.3 }

        func font(at size: DynamicTypeSize) -> Font {
            let (points, weight, style, _, tabular) = spec
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            let font = Font.system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: points, compatibleWith: traits), weight: weight)
            return tabular ? font.monospacedDigit() : font
        }
    }

    struct Typeset: ViewModifier {
        let role: TextRole
        @Environment(\.dynamicTypeSize) private var size

        func body(content: Content) -> some View {
            content.font(role.font(at: size)).tracking(role.tracking)
        }
    }
}

extension Text {
    /// Text that may hold a concealed figure; VoiceOver says "hidden" in place of the dots
    init(private string: String) {
        if string.contains(Redesign.hiddenDigits) || string.contains("••%") {
            self = Text(string).accessibilityLabel(string.replacing(/(?:[A-Z]{3} )?•{6}|••%/, with: "hidden"))
        } else {
            self = Text(string)
        }
    }
}

// MARK: - Building blocks

extension Redesign {
    /// The rounded card every list and summary sits on
    struct Panel: ViewModifier {
        var padding: CGFloat = 16
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border.opacity(0.6), lineWidth: 1))
        }
    }

    /// A round icon tinted by what it stands for: warm for food and shopping, cool for transport, green otherwise
    struct IconBox: View {
        enum Tone: Equatable { case green, warm, cool, alert }
        let symbol: String
        var tone: Tone = .green
        var small = false

        init(symbol: String, tone: Tone = .green, small: Bool = false) {
            self.symbol = symbol
            self.tone = tone
            self.small = small
        }

        init(_ look: (String, Tone), small: Bool = false) { self.init(symbol: look.0, tone: look.1, small: small) }

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: small ? 17 : 20, weight: .regular))
                .foregroundStyle(colors.fg)
                .frame(width: small ? 40 : 48, height: small ? 40 : 48)
                .background(colors.bg, in: Circle())
                .accessibilityHidden(true)
        }

        private var colors: (bg: Color, fg: Color) {
            switch tone {
            case .warm: (Theme.warmFill, Theme.warm)
            case .cool: (Theme.coolFill, Theme.cool)
            case .alert: (Theme.destructive.opacity(0.1), Theme.destructive)
            case .green: (Theme.primary.opacity(0.075), Theme.primary)
            }
        }
    }

    struct SectionHeading: View {
        let title: String
        var action: String?
        var onTap: (() -> Void)?

        var body: some View {
            HStack {
                Text(title).rdText(.section)
                Spacer()
                if let action {
                    Button(action) { onTap?() }
                        .rdText(.detail)
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.bottom, 4)
        }
    }

    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            PrimaryButtonBody(configuration: configuration)
        }

        private struct PrimaryButtonBody: View {
            let configuration: Configuration
            @Environment(\.isEnabled) private var isEnabled
            var body: some View {
                configuration.label
                    .rdText(.label)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Theme.onPrimary)
                    .background(Theme.primary, in: Capsule())
                    .opacity(isEnabled ? 1 : 0.4)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1)
            }
        }
    }

    /// The outlined pill under a primary button
    struct QuietButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .rdText(.label)
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Theme.primary)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.border.opacity(0.6), lineWidth: 1))
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }

    struct DetailRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).foregroundStyle(Theme.muted)
                Spacer()
                Text(private: value).fontWeight(.medium).monospacedDigit().multilineTextAlignment(.trailing)
            }
            .rdText(.detail)
            .padding(.vertical, 15)
        }
    }

    /// Progress toward a limit; in Enhanced privacy with charts hidden, only the empty track is drawn
    struct ProgressBar: View {
        let value: Double   // 0...1
        @Environment(AppModel.self) private var app

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.secondary)
                    if !app.hidesCharts {
                        Capsule().fill(Theme.primary).frame(width: geo.size.width * min(1, max(0, value)))
                    }
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.5), value: value)
            .accessibilityHidden(app.hidesCharts)
        }
    }

    /// Stands in for a chart in Enhanced privacy, at the chart's own height so nothing below it moves
    struct ChartHidden: View {
        let height: CGFloat
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash").font(.system(size: 18, weight: .light))
                Text("Chart hidden in Privacy Mode").rdText(.caption)
            }
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// The quiet note that Enhanced privacy is on, beside each tab's title. Its space is always kept,
    /// so the eye on Home never moves the page when it fades in or out.
    struct PrivacyBadge: View {
        @Environment(AppModel.self) private var app
        var body: some View {
            Label("Enhanced privacy", systemImage: "eye.slash")
                .labelStyle(TightLabel())
                .rdText(.captionStrong)
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Theme.primary.opacity(0.08), in: Capsule())
                .opacity(app.isEnhanced ? 1 : 0)
                .accessibilityHidden(!app.isEnhanced)
        }
    }

    /// Covers the app in the app switcher and whenever it isn't in front, when the person has asked for that
    struct PrivacyCover: ViewModifier {
        @Environment(AppModel.self) private var app
        @Environment(\.scenePhase) private var phase

        func body(content: Content) -> some View {
            content.overlay {
                if app.privacy.coverInBackground && phase != .active {
                    VStack(spacing: 10) {
                        Image(systemName: "leaf").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.primary)
                        Text("Nokael Money").rdText(.cardTitle).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                    .ignoresSafeArea()
                }
            }
        }
    }

    struct StatusPill: View {
        let bill: Bill
        let today: Date

        var body: some View {
            HStack(spacing: 3) {
                if bill.status == .paid { Image(systemName: "checkmark") }
                Text(label)
            }
            .rdText(.captionStrong)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(colors.fg)
            .background(colors.bg, in: Capsule())
        }

        private var label: String {
            switch bill.status {
            case .paid: return bill.isIncome ? "Received" : "Paid"
            case .overdue: return "Overdue"
            case .partial: return "Part paid"
            case .skipped: return "Skipped"
            case .dueToday: return "Today"
            case .upcoming:
                let days = Calendar.current.dateComponents([.day], from: today, to: bill.due).day ?? 0
                let when = days <= 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
                return bill.isEstimate ? "\(when) · est." : when
            }
        }

        private var colors: (bg: Color, fg: Color) {
            switch bill.status {
            case .paid, .skipped: return (Theme.primary.opacity(0.1), Theme.primary)
            case .overdue: return (Theme.destructive.opacity(0.1), Theme.destructive)
            case .upcoming, .dueToday, .partial: return (Theme.amberFill, Theme.amber)
            }
        }
    }

    struct EmptyNote: View {
        let text: String
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.title2.weight(.light))
                Text(text).multilineTextAlignment(.center)
            }
            .rdText(.detail)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 20)
        }
    }

    /// The segmented filter: one capsule per option, the chosen one filled
    struct Pills: View {
        let options: [String]
        @Binding var selection: String

        var body: some View {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = option }
                    } label: {
                        Text(option)
                            .rdText(.captionStrong)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(selection == option ? Theme.onPrimary : Theme.muted)
                            .background(selection == option ? Theme.primary : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.secondary.opacity(0.8), in: Capsule())
        }
    }

    /// The green card face shown for the credit card
    struct CreditCardFace: View {
        let balance: Text
        let holder: String
        /// The last four digits; nil when unknown or when Enhanced privacy hides them
        var number: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("nokael").font(.system(size: 18, weight: .medium)).tracking(-0.6)
                    Text("CREDIT").font(.system(size: 9)).tracking(2).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.white.opacity(0.65))
                }
                HStack(spacing: 12) {
                    Image(systemName: "creditcard").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(Color(hex: 0xD1C4A7))
                    Image(systemName: "wave.3.right").font(.footnote).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("•••• \(number ?? "••••")").rdText(.detail).tracking(3).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.vertical, 22)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Outstanding balance").rdText(.caption).foregroundStyle(.white.opacity(0.6))
                        balance.rdText(.figure).fontWeight(.regular)
                    }
                    Spacer()
                    Text(holder.uppercased()).rdText(.overline).foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(LinearGradient(colors: [Color(hex: 0x576750), Color(hex: 0x354C3C), Color(hex: 0x24392E)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1)))
            .shadow(color: Color(hex: 0x24392E, opacity: 0.08), radius: 10, y: 8)
        }
    }

    /// Soft green hills behind the safe-to-spend figure, drawn so nothing is downloaded
    struct Hills: View {
        var body: some View {
            Canvas { context, size in
                let w = size.width, h = size.height
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(Gradient(colors: [Color(hex: 0xEEF0E7), Color(hex: 0xE3E5D2)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                func hill(_ base: CGFloat, _ peaks: [(CGFloat, CGFloat)], _ color: Color) {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h * base))
                    var x0: CGFloat = 0, y0 = h * base
                    for (px, py) in peaks {
                        let x1 = w * px, y1 = h * py
                        p.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: x0 + (x1 - x0) * 0.5, y: y0),
                                   control2: CGPoint(x: x0 + (x1 - x0) * 0.5, y: y1))
                        x0 = x1; y0 = y1
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                    context.fill(p, with: .color(color))
                }
                hill(0.62, [(0.35, 0.5), (0.7, 0.62), (1, 0.48)], Color(hex: 0xC9CEB0))
                hill(0.78, [(0.3, 0.66), (0.62, 0.76), (1, 0.64)], Color(hex: 0xB3BC95))
                hill(0.9, [(0.45, 0.8), (0.8, 0.88), (1, 0.82)], Color(hex: 0x9EAA80))
            }
            .overlay(LinearGradient(colors: [Color(hex: 0xEEF0E7, opacity: 0.95), Color(hex: 0xF0EDDD, opacity: 0.7),
                                             Color(hex: 0xCBD0AC, opacity: 0.05)],
                                    startPoint: .top, endPoint: .bottom))
        }
    }

    /// The pastel Apple Intelligence mark
    struct IntelligenceMark: View {
        var size: CGFloat = 24
        var body: some View {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundStyle(Color(hex: 0x5D4F83))
                .frame(width: size, height: size)
                .background(Theme.intelligence, in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
        }
    }
}

extension View {
    func rdPanel(padding: CGFloat = 16) -> some View { modifier(Redesign.Panel(padding: padding)) }
    /// Sets text in one of the preview's type roles
    func rdText(_ role: Redesign.TextRole) -> some View { modifier(Redesign.Typeset(role: role)) }
}
