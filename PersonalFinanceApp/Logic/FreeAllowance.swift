//
//  FreeAllowance.swift
//  Nokael Money
//
//  The free monthly uses of the Apple Intelligence features, so people can
//  try them before Plus. Counted per calendar month on this phone; answers
//  run on Apple's models, so a use costs nothing, and the count only shapes
//  when the paywall appears.
//

import Foundation

enum FreeAllowance: String {
    case ask, describe

    var limit: Int {
        switch self {
        case .ask: FreePlan.askPerMonth
        case .describe: FreePlan.describePerMonth
        }
    }

    private var key: String {
        let month = Calendar.current.dateComponents([.year, .month], from: Date())
        return "freeUses.\(rawValue).\(month.year ?? 0)-\(month.month ?? 0)"
    }

    var used: Int { UserDefaults.standard.integer(forKey: key) }
    var left: Int { max(0, limit - used) }

    func spend() { UserDefaults.standard.set(used + 1, forKey: key) }

    /// "2 free questions left this month"
    func leftText(_ noun: String) -> String {
        left == 0 ? "No free \(noun)s left this month" : "\(left) free \(noun)\(left == 1 ? "" : "s") left this month"
    }
}
