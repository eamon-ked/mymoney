//
//  WidgetSummary.swift
//  NokaelCore
//
//  The few figures the home screen widget shows. The app writes this to the
//  shared App Group after each change; the widget only reads it, so it never
//  opens the database.
//

import Foundation

public struct WidgetSummary: Codable, Equatable, Sendable {
    public struct Bill: Codable, Equatable, Sendable {
        public let name: String
        public let amount: String
        public let due: Date
        public let overdue: Bool

        public init(name: String, amount: String, due: Date, overdue: Bool) {
            self.name = name
            self.amount = amount
            self.due = due
            self.overdue = overdue
        }
    }

    /// Already formatted, e.g. "AED 1,240"; nil until setup is complete
    public let safeToSpend: String?
    public let isNegative: Bool
    public let through: Date
    public let bills: [Bill]
    public let billsTotal: String
    public let updated: Date
    /// The widget is a Nokael Plus feature; optional so older files still read
    public let isPlus: Bool?

    public init(safeToSpend: String?, isNegative: Bool, through: Date, bills: [Bill], billsTotal: String, updated: Date,
                isPlus: Bool) {
        self.safeToSpend = safeToSpend
        self.isNegative = isNegative
        self.through = through
        self.bills = bills
        self.billsTotal = billsTotal
        self.updated = updated
        self.isPlus = isPlus
    }

    public static let appGroup = "group.nokael.PersonalFinanceApp"
    static let fileName = "widget-summary.json"

    public static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    public static func load() -> WidgetSummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSummary.self, from: data)
    }

    public func save() throws {
        guard let url = Self.fileURL else { return }
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The places a widget or Control Center button can open in the app. The app reads them back with
/// `AppRoute(url:)`; the scheme is registered in the app's Info.plist.
public enum WidgetLink: String, CaseIterable, Sendable {
    case breakdown, bills, addExpense = "add-expense"

    public static let scheme = "nokaelmoney"

    public var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(), let link = WidgetLink(rawValue: host) else { return nil }
        self = link
    }
}
