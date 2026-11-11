//
//  UnusualSpend.swift
//  NokaelCore
//
//  Whether something that just arrived from Apple Pay or a bank message is
//  worth a second look: charged twice, much bigger than usual, a bank fee, or
//  money back from a shop. One reason at most, so the alert stays one line.
//

import Foundation

public enum UnusualSpend {
    public enum Reason: String, Sendable, Equatable {
        case doubleCharge, large, fee, refund
    }

    /// Words banks use for their own charges. "Interest" is left out: a loan payment isn't a surprise
    static let feeWords: Set<String> = ["fee", "fees", "charge", "charges", "commission", "penalty"]

    /// - Parameters:
    ///   - entry: what was just saved
    ///   - recent: other entries around it, from the last few months
    ///   - usual: what this category usually costs, one amount per past entry
    public static func check(_ entry: CapturedEntry, recent: [CapturedEntry], usual: [Money]) -> Reason? {
        let words = Set(StatementImport.merchantWords(entry.memo))
        func sameShop(_ other: CapturedEntry) -> Bool {
            !words.isEmpty && !words.isDisjoint(with: StatementImport.merchantWords(other.memo))
        }
        let others = recent.filter { $0.id != entry.id }

        if entry.direction == .received {
            let paidThere = others.contains { $0.direction == .spent && $0.date < entry.date && sameShop($0) && $0.amount >= entry.amount }
            return paidThere ? .refund : nil
        }
        if others.contains(where: { $0.direction == .spent && $0.amount == entry.amount && sameShop($0)
                                    && abs($0.date.timeIntervalSince(entry.date)) <= 60 * 60 }) {
            return .doubleCharge
        }
        let tokens = entry.memo.lowercased().split { !$0.isLetter }.map(String.init)
        if tokens.contains(where: feeWords.contains) { return .fee }
        // Only once there's enough history to know what usual is
        if usual.count >= 5 {
            let sorted = usual.map(\.minorUnits).sorted()
            let median = sorted[sorted.count / 2]
            if median > 0 && entry.amount.minorUnits >= median * 3 { return .large }
        }
        return nil
    }
}
