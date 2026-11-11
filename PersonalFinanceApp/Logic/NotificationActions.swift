//
//  NotificationActions.swift
//  Nokael Money
//
//  What happens when a notification is tapped or one of its buttons used, and
//  the alert for spending that arrives through Shortcuts while the app is
//  closed: what it was, where it went, how the budget stands, and anything
//  that looks off, in one notification.
//

import Foundation
import UserNotifications
import NokaelCore

extension Notifications {
    // MARK: - Taps and buttons

    static func respond(to action: String, info: [AnyHashable: Any]) async {
        let kind = (info["kind"] as? String).flatMap(NoticeKind.init(rawValue:))
        let occurrenceId = (info["occurrenceId"] as? String).flatMap(UUID.init(uuidString:))
        let subjectId = (info["subjectId"] as? String).flatMap(UUID.init(uuidString:))
        let entryId = (info["entryId"] as? String).flatMap(UUID.init(uuidString:))
        let services = AppServices.shared
        let store = services.store

        switch action {
        case Action.markPaid:
            guard let occurrenceId else { return }
            if let problem = markPaid(occurrenceId, in: store) {
                await post("couldntPay-\(occurrenceId)", kind: .billDue, title: String(localized: "Couldn't mark it paid"),
                           body: problem, thread: "bills")
            }
        case Action.skip:
            guard let occurrenceId else { return }
            try? store.skip(occurrenceId: occurrenceId)
        case Action.undo:
            guard let entryId, store.entryRecord(entryId)?.status == .posted else { return }
            try? store.void(entryId, reason: "Undone from a notification")
        case Action.change:
            if let entryId { AppRouter.shared.open(.entry(entryId)) }
            return
        case UNNotificationDefaultActionIdentifier:
            if let route = route(for: kind, subjectId: subjectId, entryId: entryId, memo: info["memo"] as? String) {
                AppRouter.shared.open(route)
            }
            return
        default:
            return
        }
        WidgetSync.update(store.snapshot, isPlus: services.plus.isPlus)
        await sync(store.snapshot)
    }

    /// Where a tap takes the person
    static func route(for kind: NoticeKind?, subjectId: UUID?, entryId: UUID?, memo: String?) -> AppRoute? {
        switch kind {
        case nil, .billDue, .billMissed, .trialEnding: .bills
        case .runningShort: .forecast
        case .payday, .payArrived: .payday
        case .backup: .backup
        case .statement: .importStatement
        case .friend: subjectId.map(AppRoute.person)
        case .monthReview: .tab(.reports)
        case .setUp, .milestone: .tab(.home)
        case .purchase, .unusual, .unknownAccount: entryId.map(AppRoute.entry)
        case .foreignCurrency: .addExpense(memo: memo ?? "")
        }
    }

    /// Pays what's left of the bill from its own account, or the one used last. Nil when done, else why not.
    static func markPaid(_ occurrenceId: UUID, in store: LedgerStore) -> String? {
        let s = store.snapshot
        // Tapped twice, or paid in the app meanwhile: nothing more to do
        guard let occ = s.occurrences.first(where: { $0.id == occurrenceId }), occ.remaining.isPositive else { return nil }
        guard let item = s.item(for: occ),
              let accountId = item.accountId ?? CaptureService.defaultAccount(s) else {
            return String(localized: "Open Bills to choose the account it was paid from.")
        }
        do {
            _ = try store.pay(occurrenceId: occurrenceId, amount: occ.remaining, accountId: accountId, categoryId: item.categoryId,
                              date: store.now(), key: UUID())
            return nil
        } catch {
            return String(localized: "Open Bills to record \(item.name). \(StoreError.from(error).errorDescription ?? "")")
        }
    }

    // MARK: - Spending that just arrived

    /// Called after Apple Pay or a bank message was saved (or couldn't be), while the app may be closed
    static func captured(_ outcome: CaptureService.Outcome, _ capture: Capture, in store: LedgerStore) async {
        let s = store.snapshot
        guard s.setupComplete else { return }
        let show = !hideAmounts

        switch outcome {
        case .skipped where capture.amount.currency != s.currency:
            let shop = capture.merchant.isEmpty ? "" : " " + String(localized: "at \(capture.merchant)")
            await post("foreign-\(capture.date.timeIntervalSince1970)", kind: .foreignCurrency,
                       title: show ? String(localized: "Couldn't add \(MoneyFormat.string(capture.amount))\(shop)")
                                   : String(localized: "Couldn't add a purchase in \(capture.amount.currency)\(shop)"),
                       body: String(localized: "Tap to add it yourself in \(s.currency), so your balances stay right."),
                       thread: "spending", info: ["memo": capture.merchant])
            return
        case .saved(let id):
            guard let record = store.entryRecord(id) else { return }
            await announce(record, capture: capture, in: store, show: show)
        default:
            return
        }
    }

    private static func announce(_ record: EntryRecord, capture: Capture, in store: LedgerStore, show: Bool) async {
        let s = store.snapshot
        let accounts = record.lines.compactMap { s.account($0.accountId) }
        let category = accounts.first { $0.kind.isCategory }
        let account = accounts.first { $0.kind.isBalanceSheet }
        let amount = MoneyFormat.string(capture.amount)
        let shop = capture.merchant.isEmpty ? (category?.name ?? "") : capture.merchant
        let info = ["entryId": record.id.uuidString]
        let safe = SafePeriod.safeToSpend(s).amount.map { String(localized: "Safe to Spend \(MoneyFormat.string($0))") }

        if capture.direction == .received, isPay(capture, category: category, in: s) {
            await post("pay-\(record.id)", kind: .payArrived, title: String(localized: "Pay arrived"),
                       body: [show ? String(localized: "\(amount) into \(account?.name ?? "")") : account?.name, show ? safe : nil]
                        .compactMap { $0 }.joined(separator: " · "),
                       thread: "spending", info: info)
            return
        }

        // What's worth saying, most important first
        var warnings: [String] = []
        switch unusual(record, capture: capture, category: category, in: s) {
        case .doubleCharge?: warnings.append(String(localized: "This looks like a double charge. Check it with your bank."))
        case .large?: warnings.append(String(localized: "Much bigger than your usual \(category?.name ?? "spending")."))
        case .fee?: warnings.append(String(localized: "A bank fee."))
        case .refund?: warnings.append(String(localized: "Money back from \(shop)."))
        case nil: break
        }
        if let category, capture.direction == .spent, let budget = budgetCrossing(category, in: s, show: show) {
            warnings.append(budget)
        }
        var asks: [String] = []
        if let hint = capture.cardHint, store.linkedAccount(forCard: hint) == nil,
           s.accounts.filter(\.spendable).count > 1, firstTimeAsking(about: hint) {
            let card = hint.count == 4 && hint.allSatisfy(\.isNumber) ? "••\(hint)"
                : hint.hasPrefix("account ") ? String(localized: "Account ••\(String(hint.dropFirst(8)))") : hint
            asks.append(String(localized: "Is \(card) yours? Tap to choose its account."))
        }

        if isOn(.purchase) {
            let title = capture.direction == .received
                ? (show ? String(localized: "\(amount) from \(shop)") : String(localized: "Money in from \(shop)"))
                : (show ? String(localized: "\(amount) at \(shop)") : String(localized: "New purchase at \(shop)"))
            let filed = [category?.name, account?.name].compactMap { $0 }.joined(separator: " · ")
            let lines = [filed] + (isOn(.warnings) ? warnings : []) + asks + (show && capture.direction == .spent ? [safe].compactMap { $0 } : [])
            await post("capture-\(record.id)", kind: .purchase, title: title, body: lines.filter { !$0.isEmpty }.joined(separator: "\n"),
                       category: Category.capture, thread: "spending", info: info)
        } else if !warnings.isEmpty {
            await post("unusual-\(record.id)", kind: .unusual, title: show ? String(localized: "\(amount) at \(shop)") : shop,
                       body: warnings.joined(separator: "\n"), category: Category.capture, thread: "warnings", info: info)
        }
    }

    /// Income that's the pay the plan expects, or reads as salary
    static func isPay(_ capture: Capture, category: LedgerAccountRecord?, in s: FinanceSnapshot) -> Bool {
        if PaydayPlan.mentionsSalary(capture.merchant) || PaydayPlan.mentionsSalary(capture.text)
            || category.map({ PaydayPlan.mentionsSalary($0.name) }) == true { return true }
        let tenth = capture.amount.minorUnits / 10
        return s.items.contains { $0.direction == .inflow && abs($0.amount.minorUnits - capture.amount.minorUnits) <= tenth }
    }

    static func unusual(_ record: EntryRecord, capture: Capture, category: LedgerAccountRecord?, in s: FinanceSnapshot) -> UnusualSpend.Reason? {
        let since = s.calendar.date(byAdding: .day, value: -90, to: record.date) ?? record.date
        var recent: [CapturedEntry] = []
        var usual: [Money] = []
        for r in s.entryRecords where r.status == .posted && r.date >= since && r.id != record.id {
            guard r.kind == .expense || r.kind == .income else { continue }
            let moved = r.lines.filter { $0.minorUnits > 0 }.reduce(Int64(0)) { $0 + $1.minorUnits }
            let size = Money(minorUnits: moved, currency: s.currency)
            recent.append(CapturedEntry(id: r.id, date: r.date, amount: size, direction: r.kind == .income ? .received : .spent,
                                        memo: r.memo, source: r.source))
            if r.kind == .expense, let category, r.lines.contains(where: { $0.accountId == category.id }) { usual.append(size) }
        }
        let entry = CapturedEntry(id: record.id, date: record.date, amount: capture.amount, direction: capture.direction,
                                  memo: record.memo, source: capture.source)
        return UnusualSpend.check(entry, recent: recent, usual: usual)
    }

    private static let budgetKey = "notify.budget"

    /// "Groceries is 80% used" or "over budget", the first time this month it gets there
    static func budgetCrossing(_ category: LedgerAccountRecord, in s: FinanceSnapshot, show: Bool) -> String? {
        let line = s.budget.line(category.id, month: s.monthKey)
        guard line.planned.isPositive else { return nil }
        let percent = Int(line.spent.minorUnits * 100 / line.planned.minorUnits)
        let level = percent >= 100 ? 100 : percent >= 80 ? 80 : 0
        let key = "\(category.id)-\(s.monthKey)"
        var sent = UserDefaults.standard.dictionary(forKey: budgetKey) as? [String: Int] ?? [:]
        guard level > (sent[key] ?? 0) else { return nil }
        // Old months aren't needed again
        sent = sent.filter { $0.key.hasSuffix(s.monthKey) }
        sent[key] = level
        UserDefaults.standard.set(sent, forKey: budgetKey)
        if level == 100 {
            return show && line.remaining.isNegative
                ? String(localized: "\(category.name) is \(MoneyFormat.string(line.remaining.magnitude)) over budget.")
                : String(localized: "\(category.name) has used all of its budget.")
        }
        return String(localized: "\(category.name) has used \(percent)% of its budget.")
    }

    private static let askedCardsKey = "notify.askedCards"

    /// Each unknown card is asked about once
    private static func firstTimeAsking(about hint: String) -> Bool {
        var asked = UserDefaults.standard.stringArray(forKey: askedCardsKey) ?? []
        guard !asked.contains(hint) else { return false }
        asked.append(hint)
        UserDefaults.standard.set(asked, forKey: askedCardsKey)
        return true
    }
}

/// Shows notifications while the app is open too, and acts on taps and buttons
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        nonisolated(unsafe) let info = response.notification.request.content.userInfo
        await Notifications.respond(to: action, info: info)
    }
}
