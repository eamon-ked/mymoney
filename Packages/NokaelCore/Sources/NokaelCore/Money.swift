import Foundation

/// An exact amount of money: integer minor units (fils, cents) plus an ISO
/// currency code. Never stored or calculated as binary floating point.
public struct Money: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var minorUnits: Int64
    public var currency: String

    public init(minorUnits: Int64, currency: String) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Converts a decimal major amount (e.g. 12.5) to minor units, rounding
    /// half away from zero at the currency's precision.
    public init(_ major: Decimal, currency: String) {
        var scaled = major * Decimal(sign: .plus, exponent: Currency.scale(of: currency), significand: 1)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.minorUnits = NSDecimalNumber(decimal: rounded).int64Value
        self.currency = currency
    }

    public static func zero(_ currency: String) -> Money { Money(minorUnits: 0, currency: currency) }

    /// Nothing anyone really moves is a trillion or more, in any currency; bigger is a typo or a misread number
    public static let largestMajor: Decimal = 1_000_000_000_000

    /// The same check everywhere an amount comes in (typed, Siri, Wallet, an SMS, a statement): a real
    /// number, within range, with no more decimals than the currency has. nil instead of a rounded guess.
    public static func exact(_ major: Decimal, currency: String) -> Money? {
        guard !major.isNaN, major.isFinite, abs(major) < largestMajor else { return nil }
        let money = Money(major, currency: currency)
        return money.decimal == major ? money : nil
    }

    /// A number Siri or Shortcuts passed as a Double: rounded to the currency's own decimals, as the person
    /// said it ("12.5" is never 12.4999…), then checked like any other amount
    public static func spoken(_ value: Double, currency: String) -> Money? {
        guard value.isFinite else { return nil }
        let scale = Currency.scale(of: currency)
        var exactValue = Decimal(string: String(format: "%.\(scale + 3)f", value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exactValue, scale, .plain)
        return exact(rounded, currency: currency)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }
    public var isPositive: Bool { minorUnits > 0 }

    /// The major amount as an exact Decimal
    public var decimal: Decimal {
        Decimal(minorUnits) / Decimal(sign: .plus, exponent: Currency.scale(of: currency), significand: 1)
    }

    public var negated: Money { Money(minorUnits: -minorUnits, currency: currency) }
    public var magnitude: Money { Money(minorUnits: abs(minorUnits), currency: currency) }

    public static prefix func - (m: Money) -> Money { m.negated }

    public static func + (a: Money, b: Money) -> Money {
        precondition(a.currency == b.currency, "Cannot add \(a.currency) and \(b.currency)")
        return Money(minorUnits: a.minorUnits + b.minorUnits, currency: a.currency)
    }

    public static func - (a: Money, b: Money) -> Money { a + b.negated }
    public static func += (a: inout Money, b: Money) { a = a + b }
    public static func -= (a: inout Money, b: Money) { a = a - b }

    public static func < (a: Money, b: Money) -> Bool {
        precondition(a.currency == b.currency, "Cannot compare \(a.currency) and \(b.currency)")
        return a.minorUnits < b.minorUnits
    }

    /// A share of this amount, e.g. percent(10) of a salary, rounded to minor units
    public func percent(_ p: Decimal) -> Money {
        Money(decimal * p / 100, currency: currency)
    }

    public static func max(_ a: Money, _ b: Money) -> Money { a < b ? b : a }
    public static func min(_ a: Money, _ b: Money) -> Money { a < b ? a : b }

    public var description: String { MoneyFormat.string(self) }
}

public extension Sequence where Element == Money {
    func sum(_ currency: String) -> Money { reduce(.zero(currency), +) }
}

public enum Currency {
    /// Number of minor-unit digits for a currency (ISO 4217)
    public static func scale(of code: String) -> Int {
        switch code.uppercased() {
        case "KWD", "BHD", "OMR", "JOD", "TND", "LYD", "IQD": return 3
        case "JPY", "KRW", "VND", "CLP", "ISK", "UGX": return 0
        default: return 2
        }
    }
}

public enum MoneyFormat {
    /// Locale-aware currency string; whole amounts can drop the fraction
    public static func string(_ money: Money, locale: Locale = .current, dropWholeFraction: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = money.currency
        let scale = Currency.scale(of: money.currency)
        f.minimumFractionDigits = scale
        f.maximumFractionDigits = scale
        if dropWholeFraction && money.minorUnits % Int64(pow(10, Double(scale))) == 0 {
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = 0
        }
        return f.string(from: money.decimal as NSDecimalNumber) ?? "\(money.currency) \(money.decimal)"
    }

    /// Parses what a person types into Money: "1,250.5" and "85" everywhere, "12,50" and "1.250,50" where a
    /// comma is the decimal mark, "1 250" and "1'250". nil when it isn't a number, has more decimals than the
    /// currency uses (so nothing is silently rounded), or is too large to be real.
    public static func parse(_ text: String, currency: String, locale: Locale = .current) -> Money? {
        var t = AlertParserDigits.western(text).trimmingCharacters(in: .whitespacesAndNewlines)
        for unit in [currency, currency.lowercased()] { t = t.replacingOccurrences(of: unit, with: "") }
        let negative = t.hasPrefix("-") || t.hasPrefix("−")
        t = t.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" && $0 != "-" && $0 != "−" && $0 != "+" }
        // Currency signs ("$", "€", "د.إ") around the number
        while let first = t.first, !first.isNumber, first != ".", first != "," { t.removeFirst() }
        while let last = t.last, !last.isNumber { t.removeLast() }
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let scale = Currency.scale(of: currency)
        let localDecimal: Character = locale.decimalSeparator?.first ?? "."
        let commas = t.filter { $0 == "," }.count, dots = t.filter { $0 == "." }.count
        var decimalMark: Character?
        if commas > 0 && dots > 0 {
            decimalMark = t.lastIndex(of: ",")! > t.lastIndex(of: ".")! ? "," : "."
        } else if commas + dots == 1 {
            let mark: Character = commas == 1 ? "," : "."
            let after = t.distance(from: t.firstIndex(of: mark)!, to: t.endIndex) - 1
            // "1,500" is fifteen hundred unless this phone writes decimals with a comma (and the reverse for ".")
            decimalMark = after == 3 && mark != localDecimal ? nil : mark
        }
        // Thousands groups must be groups of three: "1,250,000" is a number, "12.50.3" isn't
        let whole = decimalMark.flatMap { t.firstIndex(of: $0) }.map { String(t[..<$0]) } ?? t
        let groups = whole.split(whereSeparator: { $0 == "," || $0 == "." }).map(\.count)
        if groups.count > 1, !(1...3).contains(groups[0]) || groups.dropFirst().contains(where: { $0 != 3 }) { return nil }
        var digits = ""
        var seenMark = false
        for ch in t {
            if ch == decimalMark && !seenMark { digits.append("."); seenMark = true }
            else if ch.isNumber { digits.append(ch) }
            else if ch == decimalMark { return nil }
        }
        guard !digits.isEmpty, digits != ".", let d = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if let fraction = digits.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first,
           fraction.trimmingCharacters(in: CharacterSet(charactersIn: "0")).count > scale { return nil }
        guard let money = Money.exact(d, currency: currency) else { return nil }
        return negative ? money.negated : money
    }

    /// Plain editable text for a field, e.g. "1250.50". Zero can be left empty
    /// so typing doesn't land beside a "0" the field already holds.
    public static func editable(_ money: Money, emptyWhenZero: Bool = false) -> String {
        if emptyWhenZero && money.isZero { return "" }
        return NSDecimalNumber(decimal: money.decimal).stringValue
    }
}

/// Arabic and Persian digits as Western ones, shared by everything that reads numbers
public enum AlertParserDigits {
    public static func western(_ text: String) -> String { AlertParser.westernDigits(text) }
}
