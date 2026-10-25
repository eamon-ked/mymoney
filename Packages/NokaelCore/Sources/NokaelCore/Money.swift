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

    /// Parses what a person types ("1,250.5", "85") into Money; nil when it isn't a number
    public static func parse(_ text: String, currency: String) -> Money? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: currency, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let d = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Money(d, currency: currency)
    }

    /// Plain editable text for a field, e.g. "1250.50". Zero can be left empty
    /// so typing doesn't land beside a "0" the field already holds.
    public static func editable(_ money: Money, emptyWhenZero: Bool = false) -> String {
        if emptyWhenZero && money.isZero { return "" }
        return NSDecimalNumber(decimal: money.decimal).stringValue
    }
}
