//
//  NotificationTests.swift
//  Nokael Money
//
//  What the phone schedules and says: buttons that pay, skip and undo, the
//  budget line on a purchase, amounts left out when asked, and the old bill
//  reminder switch carrying over.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
@Suite(.serialized)
struct NotificationTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        LedgerStoreTests.dubai.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    let today = LedgerStoreTests.date(2026, 11, 2)
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord
    let groceries: LedgerAccountRecord
    static let keys = ["billRemindersEnabled", "billRemindersHour", "notify.hideAmounts", "notify.spending", "notify.warnings",
                       "notify.keepingRight", "notify.payday", "notify.monthReview", "notify.friends", "notify.budget"]

    init() throws {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let now = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { now })
        try store.addStarterCategories()
        bank = try store.addAccount(name: "Current", kind: .bank, balance: Self.aed(3000), openingDate: LedgerStoreTests.date(2026, 10, 1))
        try store.updateSettings { $0.onboardingDone = true }
        groceries = try #require(store.snapshot.expenseCategories.first { $0.name == "Groceries" })
    }

    private func rent(_ amount: Decimal = 2500, due: Date) throws -> PlannedItem {
        let item = PlannedItem(name: "Rent", direction: .outflow, amount: Self.aed(amount),
                               schedule: Schedule(start: due, frequency: .monthly(every: 1)), accountId: bank.id,
                               categoryId: store.snapshot.expenseCategories.first?.id)
        try store.savePlannedItem(item)
        return item
    }

    @Test func markPaidFromTheNotificationPaysWhatsLeftOnce() throws {
        let item = try rent(due: LedgerStoreTests.date(2026, 11, 1))
        let occ = try #require(store.snapshot.occurrences.first { $0.itemId == item.id })
        #expect(Notifications.markPaid(occ.id, in: store) == nil)
        #expect(store.snapshot.occurrences.first { $0.id == occ.id }?.remaining.isZero == true)
        #expect(store.snapshot.balance(bank.id) == Self.aed(500))
        // A second tap, or one after paying in the app, changes nothing
        #expect(Notifications.markPaid(occ.id, in: store) == nil)
        #expect(store.snapshot.balance(bank.id) == Self.aed(500))
    }

    @Test func aMissedBillAndRunningShortArePlanned() throws {
        _ = try rent(4000, due: LedgerStoreTests.date(2026, 11, 6))
        let plan = Notifications.plan(store.snapshot, now: Self.at(2026, 11, 2, 8))
        let kinds = Set(plan.map(\.kind))
        #expect(kinds.isSuperset(of: [.billDue, .billMissed, .runningShort]))
        let short = try #require(plan.first { $0.kind == .runningShort })
        #expect(short.amount == Self.aed(1000) && short.name == "Rent")
        // Warnings off: it's left out
        UserDefaults.standard.set(false, forKey: Notifications.Group.warnings.key)
        defer { UserDefaults.standard.removeObject(forKey: Notifications.Group.warnings.key) }
        #expect(!Notifications.plan(store.snapshot, now: Self.at(2026, 11, 2, 8)).contains { $0.kind == .runningShort })
    }

    @Test func theOldBillReminderSwitchCarriesOver() {
        #expect(Notifications.isOn(.bills))
        UserDefaults.standard.set(false, forKey: "billRemindersEnabled")
        #expect(!Notifications.isOn(.bills) && !Notifications.isOn(.billMissed))
        #expect(Notifications.isOn(.purchase) && !Notifications.isOn(NoticeKind.friend) && !Notifications.isOn(NoticeKind.payday))
    }

    @Test func amountsAreLeftOutWhenAsked() throws {
        let item = try rent(due: LedgerStoreTests.date(2026, 11, 5))
        let s = store.snapshot
        let notice = try #require(s.billNotices(hour: 9, now: Self.at(2026, 11, 2, 8)).first { $0.itemId == item.id && $0.kind == .billDue })
        #expect(Notifications.content(for: notice, in: s).body.contains("2,500"))
        UserDefaults.standard.set(true, forKey: Notifications.hideAmountsKey)
        let hidden = Notifications.content(for: notice, in: s)
        #expect(!hidden.body.contains("2,500") && hidden.body.contains("Current"))
        #expect(hidden.categoryIdentifier == Notifications.Category.bill)
    }

    @Test func aPurchaseSaysWhenItsCategoryReachesItsBudgetOnce() throws {
        try store.setAllocation(Self.aed(500), categoryId: groceries.id, month: store.snapshot.monthKey)
        try store.post(EntryFactory.expense(Self.aed(380), from: bank.info, category: groceries.info, date: today, memo: "Spinneys", key: UUID()))
        #expect(Notifications.budgetCrossing(groceries, in: store.snapshot, show: true) == nil)
        try store.post(EntryFactory.expense(Self.aed(40), from: bank.info, category: groceries.info, date: today, memo: "Carrefour", key: UUID()))
        #expect(Notifications.budgetCrossing(groceries, in: store.snapshot, show: true) == "Groceries has used 84% of its budget.")
        #expect(Notifications.budgetCrossing(groceries, in: store.snapshot, show: true) == nil)
        try store.post(EntryFactory.expense(Self.aed(100), from: bank.info, category: groceries.info, date: today, memo: "Lulu", key: UUID()))
        #expect(Notifications.budgetCrossing(groceries, in: store.snapshot, show: true) == "Groceries is \(MoneyFormat.string(Self.aed(20))) over budget.")
    }

    @Test func aDoubleChargeAndPayAreRecognised() throws {
        let first = try store.postCaptured(EntryFactory.expense(Self.aed(85.5), from: bank.info, category: groceries.info,
                                                                date: today, memo: "CARREFOUR MOE", key: UUID()),
                                           source: .sms, cardHint: nil, needsReview: true)
        let second = try store.postCaptured(EntryFactory.expense(Self.aed(85.5), from: bank.info, category: groceries.info,
                                                                 date: today.addingTimeInterval(900), memo: "Carrefour", key: UUID()),
                                            source: .sms, cardHint: nil, needsReview: true)
        let capture = Capture(source: .sms, direction: .spent, amount: Self.aed(85.5), merchant: "Carrefour",
                              date: today.addingTimeInterval(900), text: "")
        let record = try #require(store.entryRecord(second))
        #expect(first != second)
        #expect(Notifications.unusual(record, capture: capture, category: groceries, in: store.snapshot) == .doubleCharge)

        let pay = Capture(source: .sms, direction: .received, amount: Self.aed(12000), merchant: "ACME LLC", date: today,
                          text: "SALARY CREDIT ACME LLC 12,000.00")
        #expect(Notifications.isPay(pay, category: nil, in: store.snapshot))
        let refund = Capture(source: .sms, direction: .received, amount: Self.aed(50), merchant: "Zara", date: today, text: "")
        #expect(!Notifications.isPay(refund, category: nil, in: store.snapshot))
    }

    @Test func undoVoidsWhatArrived() throws {
        let id = try store.postCaptured(EntryFactory.expense(Self.aed(20), from: bank.info, category: groceries.info, date: today,
                                                             memo: "Cafe", key: UUID()), source: .applePay, cardHint: nil, needsReview: true)
        #expect(Notifications.route(for: .purchase, subjectId: nil, entryId: id, memo: nil) == .entry(id))
        try store.void(id, reason: "Undone from a notification")
        #expect(store.snapshot.balance(bank.id) == Self.aed(3000))
        #expect(Notifications.route(for: .foreignCurrency, subjectId: nil, entryId: nil, memo: "Uber") == .addExpense(memo: "Uber"))
    }

    @Test func aBackupNagComesWeeklyOnceThereIsSomethingToLose() throws {
        #expect(!Notifications.keepingRight(store.snapshot, now: today, hour: 9).contains { $0.kind == .backup })
        for i in 0..<5 {
            try store.post(EntryFactory.expense(Self.aed(10), from: bank.info, category: groceries.info, date: today, memo: "Shop \(i)", key: UUID()))
        }
        let first = try #require(Notifications.keepingRight(store.snapshot, now: today, hour: 9).first { $0.kind == .backup })
        let later = try #require(Notifications.keepingRight(store.snapshot, now: first.fireDate.addingTimeInterval(60), hour: 9).first { $0.kind == .backup })
        #expect(LedgerStoreTests.dubai.dateComponents([.day], from: first.fireDate, to: later.fireDate).day == 7)
        try store.updateSettings { $0.lastBackupAt = today }
        #expect(!Notifications.keepingRight(store.snapshot, now: today, hour: 9).contains { $0.kind == .backup })
    }

    @Test func theStatementReminderWaitsForAMonthWithoutOne() throws {
        #expect(!Notifications.keepingRight(store.snapshot, now: today, hour: 9).contains { $0.kind == .statement })
        try store.updateSettings { $0.lastStatementImportAt = LedgerStoreTests.date(2026, 10, 20) }
        // 3 November: October's statement hasn't been imported since the month ended
        let notice = try #require(Notifications.keepingRight(store.snapshot, now: today, hour: 9).first { $0.kind == .statement })
        #expect(notice.fireDate == Self.at(2026, 11, 3, 9))
        // Imported today: nothing on the 3rd, and December's comes once November is behind
        try store.updateSettings { $0.lastStatementImportAt = today }
        #expect(!Notifications.keepingRight(store.snapshot, now: today, hour: 9).contains { $0.kind == .statement })
        let next = try #require(Notifications.keepingRight(store.snapshot, now: Self.at(2026, 11, 4, 9), hour: 9).first { $0.kind == .statement })
        #expect(next.fireDate == Self.at(2026, 12, 3, 9))
    }

    @Test func aTrialIsSavedAndBacksUp() throws {
        let tv = PlannedItem(name: "Streaming", direction: .outflow, amount: Self.aed(45),
                             schedule: Schedule(start: LedgerStoreTests.date(2026, 11, 10), frequency: .monthly(every: 1)), accountId: bank.id)
        try store.savePlannedItem(tv, isTrial: true)
        #expect(store.snapshot.isTrial(tv.id))
        try store.savePlannedItem(tv)
        #expect(store.snapshot.isTrial(tv.id))
        let plan = Notifications.plan(store.snapshot, now: today)
        #expect(plan.first { $0.kind == .trialEnding }?.fireDate == Self.at(2026, 11, 8, 9))
        let backup = try LedgerStore.readBackup(JSONEncoder().encode(store.makeBackup()))
        #expect(backup.plannedItems.first { $0.id == tv.id }?.isTrial == true)
    }
}
