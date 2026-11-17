import Foundation

/// An account number as a person types it or a bank shows it. Banks often number one customer's accounts
/// so they differ only in the middle (…810001 and …920001), so matching compares every digit both sides
/// show, never just the last four.
public enum AccountNumber {
    /// The fewest digits worth keeping: fewer would match too much
    public static let minimumDigits = 4

    /// Digits only, so spaces, dashes and an IBAN's letters don't matter. nil when too short to use.
    public static func normalized(_ text: String) -> String? {
        let digits = String(text.filter { $0.isASCII && $0.isNumber })
        return digits.count >= minimumDigits ? digits : nil
    }

    /// Two numbers that could be the same account: one ends with the other, compared digit for digit
    public static func agrees(_ a: String, _ b: String) -> Bool {
        guard a.count >= minimumDigits, b.count >= minimumDigits else { return false }
        return a.hasSuffix(b) || b.hasSuffix(a)
    }

    /// The only account whose number agrees with the digits a message or statement shows. nil when none
    /// does, or more than one could, so the app asks instead of guessing.
    public static func match<ID>(_ digits: String, in numbers: [(id: ID, number: String)]) -> ID? {
        guard let digits = normalized(digits) else { return nil }
        let hits = numbers.filter { agrees($0.number, digits) }
        return hits.count == 1 ? hits[0].id : nil
    }

    /// Other numbers this one can't be told apart from: a message showing the shorter one's digits would fit both
    public static func clashes<ID>(_ number: String, with others: [(id: ID, number: String)]) -> [ID] {
        guard let number = normalized(number) else { return [] }
        return others.filter { agrees($0.number, number) }.map(\.id)
    }

    /// How many digits banks' messages usually show when the last four aren't enough ("XXX810001")
    public static let messageDigits = 6

    /// The ending to show: the last four digits, or, when another number ends the same way, the six a bank
    /// message usually shows ("810001" beside "920001"), or more if even those are shared. Never an odd
    /// length like "10001" that matches nothing the person sees elsewhere.
    public static func shortEnding(_ number: String, among others: [String]) -> String {
        let digits = normalized(number) ?? number
        func shared(_ length: Int) -> Bool {
            others.contains { $0 != digits && $0.count >= length && $0.hasSuffix(String(digits.suffix(length))) }
        }
        guard shared(min(minimumDigits, digits.count)) else { return String(digits.suffix(minimumDigits)) }
        var length = min(messageDigits, digits.count)
        while length < digits.count, shared(length) { length += 1 }
        return String(digits.suffix(length))
    }
}
