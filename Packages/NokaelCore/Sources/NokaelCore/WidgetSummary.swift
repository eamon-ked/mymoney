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

    public init(safeToSpend: String?, isNegative: Bool, through: Date, bills: [Bill], billsTotal: String, updated: Date) {
        self.safeToSpend = safeToSpend
        self.isNegative = isNegative
        self.through = through
        self.bills = bills
        self.billsTotal = billsTotal
        self.updated = updated
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
