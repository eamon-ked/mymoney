//
//  Notifications.swift
//  Nokael Money
//
//  Everything the app tells the person while it's closed, all scheduled or
//  sent by this phone; nothing leaves the device. After every data change the
//  waiting notifications are replaced with NotificationPlanner's list, so
//  paying, skipping or editing something cancels or moves its notice. Spending
//  that arrives through Shortcuts is announced the moment it's saved.
//

import Foundation
import UIKit
import UserNotifications
import NokaelCore

@MainActor
enum Notifications {
    // MARK: - Choices (kept on this phone, like Privacy Mode)

    /// What the switches on the Notifications page turn on and off
    enum Group: String, CaseIterable, Identifiable {
        case bills, spending, warnings, keepingRight
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bills: String(localized: "Bills")
            case .spending: String(localized: "Spending as it happens")
            case .warnings: String(localized: "Warnings")
            case .keepingRight: String(localized: "Keeping things right")
            }
        }

        var detail: String {
            switch self {
            case .bills: String(localized: "Before a bill is due, and the day after if it isn't marked paid. Free trials before their first charge.")
            case .spending: String(localized: "Each purchase from Apple Pay or a bank message, with its category and how the budget stands. Pay arriving.")
            case .warnings: String(localized: "Money that may run short before a bill. A double charge, a bank fee, a refund or an unusually big purchase.")
            case .keepingRight: String(localized: "Backups, setup left unfinished, and the monthly statement. Goals reached and loans paid off.")
            }
        }

        var key: String { rawValue == "bills" ? BillsKey.legacy : "notify.\(rawValue)" }
    }

    /// The ones that are off unless asked for
    enum Extra: String, CaseIterable, Identifiable {
        case payday, monthReview, friends
        var id: String { rawValue }
        var key: String { "notify.\(rawValue)" }
        var title: String {
            switch self {
            case .payday: String(localized: "On payday")
            case .monthReview: String(localized: "Month in review, on the 1st")
            case .friends: String(localized: "Money friends owe you")
            }
        }
    }

    private enum BillsKey {
        /// Bill reminders were all there was before; their switch carries over
        static let legacy = "billRemindersEnabled"
    }

    static let hourKey = "billRemindersHour"
    static let hideAmountsKey = "notify.hideAmounts"

    static func isOn(_ group: Group) -> Bool { UserDefaults.standard.object(forKey: group.key) as? Bool ?? true }
    static func isOn(_ extra: Extra) -> Bool { UserDefaults.standard.bool(forKey: extra.key) }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9 }
    static var hideAmounts: Bool { UserDefaults.standard.bool(forKey: hideAmountsKey) }

    static func isOn(_ kind: NoticeKind) -> Bool {
        switch kind {
        case .billDue, .billMissed, .trialEnding: isOn(.bills)
        case .purchase, .payArrived, .unknownAccount, .foreignCurrency: isOn(.spending)
        case .runningShort, .unusual: isOn(.warnings)
        case .backup, .setUp, .statement, .milestone: isOn(.keepingRight)
        case .payday: isOn(Extra.payday)
        case .monthReview: isOn(Extra.monthReview)
        case .friend: isOn(Extra.friends)
        }
    }

    /// Demo and UI-test runs use made-up data, so they never schedule anything
    private static var isThrowawayRun: Bool {
        let args = CommandLine.arguments
        return args.contains("-uiTesting") || args.contains("-demoData")
    }

    // MARK: - Permission

    /// After setup: quiet delivery to Notification Centre, which iOS allows without asking
    static func startQuietly() async {
        guard !isThrowawayRun else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.provisional, .alert, .sound, .badge])
    }

    /// Asks iOS for full permission (banners and sounds); true when notifications can be shown
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func permission() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func permissionDenied() async -> Bool { await permission() == .denied }

    // MARK: - Buttons

    enum Category {
        static let bill = "BILL"
        static let capture = "CAPTURE"
    }

    enum Action {
        static let markPaid = "markPaid"
        static let skip = "skip"
        static let change = "change"
        static let undo = "undo"
    }

    /// Changing money always needs the phone unlocked
    static func registerCategories() {
        let bill = UNNotificationCategory(identifier: Category.bill, actions: [
            UNNotificationAction(identifier: Action.markPaid, title: String(localized: "Mark paid"), options: [.authenticationRequired],
                                 icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
            UNNotificationAction(identifier: Action.skip, title: String(localized: "Skip this time"), options: [.authenticationRequired],
                                 icon: UNNotificationActionIcon(systemImageName: "forward")),
        ], intentIdentifiers: [])
        let capture = UNNotificationCategory(identifier: Category.capture, actions: [
            UNNotificationAction(identifier: Action.change, title: String(localized: "Change"), options: [.foreground],
                                 icon: UNNotificationActionIcon(systemImageName: "pencil")),
            UNNotificationAction(identifier: Action.undo, title: String(localized: "Undo"), options: [.destructive, .authenticationRequired],
                                 icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.backward")),
        ], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([bill, capture])
    }

    // MARK: - Scheduled

    private static let scheduledPrefixes = ["bill-", "missed-", "short-", "payday-", "trial-", "backup-", "setUp-", "statement-",
                                            "friend-", "review-"]

    /// Replaces every waiting notice with the current plan, and keeps the badge and milestones up to date
    static func sync(_ snapshot: FinanceSnapshot, now: Date = Date()) async {
        guard !isThrowawayRun else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { id in scheduledPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for notice in plan(snapshot, now: now) {
            let parts = snapshot.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notice.fireDate)
            let request = UNNotificationRequest(identifier: notice.id, content: content(for: notice, in: snapshot),
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
        try? await center.setBadgeCount(badge(snapshot))
        await milestones(snapshot)
    }

    /// What should be waiting right now, most urgent first, within what iOS holds
    static func plan(_ s: FinanceSnapshot, now: Date) -> [PlannedNotice] {
        guard s.setupComplete else { return [] }
        let hour = hour
        let cal = s.calendar
        var all: [PlannedNotice] = []
        all += s.billNotices(hour: hour, now: now)
        all += NotificationPlanner.trials(items: s.items, occurrences: s.occurrences, trialIds: s.trialItemIds, now: now, hour: hour, calendar: cal)
        if let short = NotificationPlanner.runningShort(s.cashForecast(days: 14), now: now, hour: hour, calendar: cal) { all.append(short) }
        if let pay = NotificationPlanner.payday(items: s.items, occurrences: s.occurrences, now: now, hour: hour, calendar: cal) { all.append(pay) }
        all += keepingRight(s, now: now, hour: hour)
        return NotificationPlanner.fit(all.filter { isOn($0.kind) }, calendar: cal)
    }

    /// Backups, setup, the statement, friends and the month in review: at most one a week each
    static func keepingRight(_ s: FinanceSnapshot, now: Date, hour: Int) -> [PlannedNotice] {
        let cal = s.calendar
        var out: [PlannedNotice] = []

        if HomeTask.needsBackup(s) {
            // Counted from when it became due, so it lands on the same weekday however often data changes
            let since = s.settings.lastBackupAt.flatMap { cal.date(byAdding: .day, value: 31, to: $0) }
                ?? s.entries().map(\.createdAt).sorted().dropFirst(4).first ?? now
            if let fire = NotificationPlanner.weekly(from: cal.date(byAdding: .day, value: 1, to: since) ?? since, after: now, hour: hour, calendar: cal) {
                out.append(PlannedNotice(id: "backup-\(cal.startOfDay(for: fire).timeIntervalSince1970)", kind: .backup, fireDate: fire,
                                         date: s.settings.lastBackupAt))
            }
        }

        // Once, two days after starting, for the first thing still missing
        if let started = s.accounts.map(\.createdAt).min(),
           let fire = NotificationPlanner.morning(after: started, days: 2, hour: hour, calendar: cal), fire > now {
            let missing = HomeTask.all(s).lazy.compactMap { task -> (String, String)? in
                switch task {
                case .setUp(let step): (step.rawValue, "")
                case .finishLoan(let loan): ("loan", loan.name)
                default: nil
                }
            }.first
            if let missing {
                out.append(PlannedNotice(id: "setUp-\(missing.0)", kind: .setUp, fireDate: fire, name: missing.1))
            }
        }

        // The 3rd, for people who keep their records with statements, until this month's is in
        if let last = s.settings.lastStatementImportAt,
           let fire = NotificationPlanner.next(dayOfMonth: 3, after: now, hour: hour, calendar: cal),
           let monthStart = cal.dateInterval(of: .month, for: fire)?.start, last < monthStart,
           let covers = cal.date(byAdding: .month, value: -1, to: monthStart) {
            out.append(PlannedNotice(id: "statement-\(BudgetMonth.key(for: covers, calendar: cal))", kind: .statement, fireDate: fire, date: covers))
        }

        // Money people owe you: on the day they said, else two weeks after the last movement
        for person in s.accounts where person.kind == .lent && !person.archived {
            let owes = s.balance(person.id)
            guard owes.isPositive else { continue }
            let last = s.entryRecords.first {
                $0.status == .posted && $0.kind != .openingBalance && $0.lines.contains { $0.accountId == person.id }
            }?.date
            let day = person.owedBackBy ?? last.flatMap { cal.date(byAdding: .day, value: 14, to: $0) }
            guard let day, let fire = NotificationPlanner.weekly(from: day, after: now, hour: hour, calendar: cal) else { continue }
            out.append(PlannedNotice(id: "friend-\(person.id)-\(cal.startOfDay(for: fire).timeIntervalSince1970)", kind: .friend,
                                     fireDate: fire, name: person.name, amount: owes, date: person.owedBackBy, subjectId: person.id))
        }

        if !s.entryRecords.isEmpty, let fire = NotificationPlanner.next(dayOfMonth: 1, after: now, hour: hour, calendar: cal),
           let month = cal.date(byAdding: .month, value: -1, to: fire) {
            out.append(PlannedNotice(id: "review-\(BudgetMonth.key(for: month, calendar: cal))", kind: .monthReview, fireDate: fire, date: month))
        }
        return out
    }

    /// Bills that are late and entries waiting to be checked
    static func badge(_ s: FinanceSnapshot) -> Int {
        let late = s.upcomingBills(days: 0).filter { s.state(of: $0) == .overdue }.count
        return late + s.entries().filter(\.needsReview).count
    }

    // MARK: - Words

    /// Amounts and balances are left out when the person asked, so a glance at the Lock Screen gives nothing away
    static func content(for notice: PlannedNotice, in s: FinanceSnapshot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let show = !hideAmounts
        let amount = notice.amount.map { (notice.isEstimate ? String(localized: "About ") : "") + MoneyFormat.string($0) }
        let weekday = notice.date.map { $0.formatted(.dateTime.weekday(.wide)) } ?? ""
        let day = notice.date.map { $0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) } ?? ""
        let monthName = notice.date.map { $0.formatted(.dateTime.month(.wide)) } ?? ""
        let account = notice.itemId.flatMap { id in s.items.first { $0.id == id }?.accountId }.flatMap { s.account($0)?.name }
        content.sound = .default
        content.userInfo = ["kind": notice.kind.rawValue]
        if let id = notice.occurrenceId { content.userInfo["occurrenceId"] = id.uuidString }
        if let id = notice.subjectId { content.userInfo["subjectId"] = id.uuidString }

        switch notice.kind {
        case .billDue:
            switch notice.daysBefore {
            case 0: content.title = String(localized: "\(notice.name) is due today")
            case 1: content.title = String(localized: "\(notice.name) is due tomorrow")
            default: content.title = String(localized: "\(notice.name) is due \(day)")
            }
            content.body = [show ? amount : nil, account.map { String(localized: "from \($0)") }].compactMap { $0 }.joined(separator: " ")
            content.categoryIdentifier = Category.bill
            content.threadIdentifier = "bills"
        case .billMissed:
            content.title = String(localized: "Did \(notice.name) go out?")
            content.body = show && amount != nil
                ? String(localized: "\(amount!) was due \(day). Mark it paid, or skip it this time.")
                : String(localized: "It was due \(day). Mark it paid, or skip it this time.")
            content.categoryIdentifier = Category.bill
            content.threadIdentifier = "bills"
        case .trialEnding:
            content.title = String(localized: "Your \(notice.name) trial ends \(weekday)")
            content.body = show && amount != nil
                ? String(localized: "The first charge of \(amount!) is on \(day). Cancel before then if you don't want it.")
                : String(localized: "The first charge is on \(day). Cancel before then if you don't want it.")
            content.threadIdentifier = "bills"
        case .runningShort:
            content.title = String(localized: "Money may run short")
            content.body = show && amount != nil
                ? String(localized: "\(notice.name) on \(weekday) would leave you \(amount!) short.")
                : String(localized: "\(notice.name) on \(weekday) would take you below zero.")
            content.threadIdentifier = "warnings"
        case .payday:
            content.title = String(localized: "Payday")
            content.body = String(localized: "Has \(notice.name) arrived? Tap to record it and plan the month.")
            content.threadIdentifier = "reminders"
        case .backup:
            content.title = String(localized: "Time for a backup")
            if let last = notice.date {
                let days = s.calendar.dateComponents([.day], from: last, to: notice.fireDate).day ?? 30
                content.body = String(localized: "Your last backup was \(days) days ago. Your records only live on this phone.")
            } else {
                content.body = String(localized: "Your records only live on this phone. Save a backup so you can't lose them.")
            }
            content.threadIdentifier = "reminders"
        case .setUp:
            content.title = String(localized: "Finish setting up")
            content.body = switch notice.id {
            case "setUp-payday": String(localized: "Add your payday for a truer Safe to Spend.")
            case "setUp-bills": String(localized: "Add your bills so they're held back from Safe to Spend.")
            default: String(localized: "\(notice.name) still needs what's owed on it.")
            }
            content.threadIdentifier = "reminders"
        case .statement:
            content.title = String(localized: "Import \(monthName)'s statement")
            content.body = String(localized: "It catches anything that wasn't recorded along the way.")
            content.threadIdentifier = "reminders"
        case .friend:
            content.title = show && amount != nil ? String(localized: "\(notice.name) owes you \(amount!)")
                : String(localized: "\(notice.name) still owes you")
            content.body = notice.date != nil ? String(localized: "They said they'd pay you back by \(day).")
                : String(localized: "Nothing's come back in a while. A friendly nudge?")
            content.threadIdentifier = "reminders"
        case .monthReview:
            content.title = String(localized: "Your \(monthName) summary is ready")
            content.body = String(localized: "See where your money went last month.")
            content.threadIdentifier = "reminders"
        case .milestone, .purchase, .payArrived, .unknownAccount, .foreignCurrency, .unusual:
            break   // Sent as they happen, worded where they're sent
        }
        if notice.isUrgent { content.interruptionLevel = .timeSensitive }
        return content
    }

    // MARK: - Sent now

    /// Sends right away; `id` replaces an earlier one with the same id
    static func post(_ id: String, kind: NoticeKind, title: String, body: String, category: String? = nil,
                     thread: String, info: [String: String] = [:]) async {
        guard !isThrowawayRun, isOn(kind) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        if let category { content.categoryIdentifier = category }
        content.userInfo = info.merging(["kind": kind.rawValue]) { a, _ in a }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Milestones

    private static let progressKey = "notify.progress"

    /// Goals reaching halfway and their target, loans paid off. Noticed whenever data changes;
    /// only announced while the app isn't open, since the screen already shows it otherwise.
    static func milestones(_ s: FinanceSnapshot) async {
        var known = UserDefaults.standard.dictionary(forKey: progressKey) as? [String: Int] ?? [:]
        let firstLook = known.isEmpty
        var reached: [(id: String, title: String, body: String)] = []
        for goal in s.goals {
            guard let progress = s.progress(of: goal) else { continue }
            let step = progress.fraction >= 1 ? 100 : progress.fraction >= 0.5 ? 50 : 0
            let key = "goal-\(goal.id)"
            if step > (known[key] ?? step) {
                reached.append(step == 100
                    ? (key, String(localized: "\(goal.name) reached"), String(localized: "You saved everything you set out to. Well done."))
                    : (key, String(localized: "Halfway to \(goal.name)"), String(localized: "Half of it is saved already.")))
            }
            known[key] = step
        }
        for debt in s.debts where debt.kind == .loan {
            let key = "loan-\(debt.id)"
            let paidOff = s.owed(debt.id).isZero || s.owed(debt.id).isNegative ? 1 : 0
            if paidOff > (known[key] ?? paidOff) {
                reached.append((key, String(localized: "\(debt.name) is paid off"), String(localized: "Nothing more is owed on it.")))
            }
            known[key] = paidOff
        }
        UserDefaults.standard.set(known, forKey: progressKey)
        guard !firstLook, UIApplication.shared.applicationState != .active else { return }
        for r in reached {
            await post("milestone-\(r.id)", kind: .milestone, title: r.title, body: r.body, thread: "reminders")
        }
    }

    /// Choices offered in the bill editor
    static let choices: [(days: Int, label: String)] = [
        (-1, String(localized: "Don't remind me")), (0, String(localized: "On the day")), (1, String(localized: "1 day before")),
        (2, String(localized: "2 days before")), (3, String(localized: "3 days before")), (7, String(localized: "A week before")),
    ]
}

#if DEBUG
extension Notifications {
    /// Sends one of each kind that's planned, `seconds` from now, to check the words and buttons
    static func sendSoon(_ snapshot: FinanceSnapshot, in seconds: Int) async {
        var seen = Set<NoticeKind>()
        let notices = plan(snapshot, now: Date()).filter { seen.insert($0.kind).inserted }
        for (i, notice) in notices.enumerated() {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds + i * 2), repeats: false)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "soon-" + notice.id, content: content(for: notice, in: snapshot), trigger: trigger))
        }
        print("notifyIn:", notices.map(\.kind.rawValue))
    }
}
#endif
