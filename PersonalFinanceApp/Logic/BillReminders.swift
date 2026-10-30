//
//  BillReminders.swift
//  Nokael Money
//
//  Local notifications before bills are due. After every data change the
//  pending reminders are replaced with ReminderPlanner's list, so paying,
//  skipping or editing a bill cancels or moves its reminder. Nothing leaves
//  the device.
//

import Foundation
import UserNotifications
import NokaelCore

@MainActor
enum BillReminders {
    static let enabledKey = "billRemindersEnabled"
    static let hourKey = "billRemindersHour"
    private static let prefix = "bill-"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9 }

    /// Demo and UI-test runs use made-up data, so they never schedule anything
    private static var isThrowawayRun: Bool {
        let args = CommandLine.arguments
        return args.contains("-uiTesting") || args.contains("-demoData")
    }

    /// Asks iOS for permission; true when reminders can be shown
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func permissionDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Replaces every pending bill reminder with the current plan
    static func sync(_ snapshot: FinanceSnapshot) async {
        guard !isThrowawayRun else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }

        for reminder in snapshot.billReminders(hour: hour, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = title(reminder, calendar: snapshot.calendar)
            let account = snapshot.items.first { $0.id == reminder.itemId }?.accountId.flatMap { snapshot.account($0)?.name }
            content.body = [(reminder.isEstimate ? "About " : "") + reminder.amount.formatted,
                            account.map { "from \($0)" }].compactMap { $0 }.joined(separator: " ")
            content.sound = .default
            content.threadIdentifier = "bills"
            content.userInfo = ["occurrenceId": reminder.occurrenceId.uuidString]
            let parts = snapshot.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(identifier: prefix + reminder.occurrenceId.uuidString, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }

    static func title(_ reminder: BillReminder, calendar: Calendar) -> String {
        switch reminder.daysBefore {
        case 0: return "\(reminder.name) is due today"
        case 1: return "\(reminder.name) is due tomorrow"
        default: return "\(reminder.name) is due \(reminder.dueDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))"
        }
    }

    /// Choices offered in the bill editor
    static let choices: [(days: Int, label: String)] = [
        (-1, "Don't remind me"), (0, "On the day"), (1, "1 day before"), (2, "2 days before"),
        (3, "3 days before"), (7, "A week before"),
    ]
}

/// Shows reminders while the app is open and opens Bills when one is tapped
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppRouter.shared.open(.bills) }
    }
}

