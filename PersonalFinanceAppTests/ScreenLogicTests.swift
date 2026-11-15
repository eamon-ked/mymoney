//
//  ScreenLogicTests.swift
//  Nokael Money
//
//  The rules that used to live inside screens: what Add records, how a typed
//  balance is signed, saving a category, setting up pay, importing a
//  statement and opening Bills from a reminder. Any redesign keeps these.
//

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct ScreenLogicTests {
    static func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }
    let today = LedgerStoreTests.date(2026, 10, 26)
    let container: ModelContainer
    let store: LedgerStore
    let bank: LedgerAccountRecord

    init() throws {
        container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let today = today
        store = LedgerStore(context: container.mainContext, calendar: LedgerStoreTests.dubai, now: { today })
        try store.addStarterCategories()
        bank = try store.addAccount(name: "Current", kind: .bank, balance: Self.aed(5000), openingDate: today)
    }

    private func category(_ name: String) -> LedgerAccountRecord {
        store.snapshot.accountRecords.first { $0.name == name }!
    }

    private func form(_ kind: AddKind, _ amount: Decimal?) -> EntryForm {
        EntryForm(kind: kind, amount: amount.map(Self.aed), accountId: bank.id, categoryId: category("Groceries").id, date: today)
    }

    // MARK: - Add

    @Test func anExpenseTakesItsNameFromTheCategoryWhenLeftBlank() throws {
        let id = try store.save(form(.expense, 120))
        #expect(store.snapshot.balance(bank.id) == Self.aed(4880))
        #expect(store.entryRecord(id)?.memo == "Groceries")
    }

    @Test func amountProblemsAreToldApartFromTheRest() throws {
        #expect(throws: EntryForm.AmountProblem(message: "Enter an amount.")) { try store.save(form(.expense, nil)) }
        #expect(throws: EntryForm.AmountProblem(message: "Enter an amount greater than zero.")) { try store.save(form(.expense, 0)) }
        var noAccount = form(.expense, 10)
        noAccount.accountId = nil
        #expect(throws: StoreError.invalid("Choose an account.")) { try store.save(noAccount) }
        #expect(store.snapshot.balance(bank.id) == Self.aed(5000))
    }

    @Test func aBalanceAdjustmentRecordsTheDifference() throws {
        var fix = form(.adjustment, 4750)
        fix.reason = "Bank fee"
        try store.save(fix)
        #expect(store.snapshot.balance(bank.id) == Self.aed(4750))
        // The same form again is a retry: what it saved, nothing more
        try store.save(fix)
        #expect(store.snapshot.balance(bank.id) == Self.aed(4750))
        // A new correction to what's already recorded has nothing to record
        var again = fix
        again.key = UUID()
        #expect(throws: StoreError.invalid("That's already the recorded balance.")) { try store.save(again) }
    }

    @Test func repeatsPaysTheFirstAndIsDueOneStepLater() throws {
        var rent = form(.expense, 3000)
        rent.memo = "Rent"
        rent.repeats = true
        let id = try store.save(rent)
        let item = try #require(store.snapshot.items.first { $0.name == "Rent" })
        #expect(item.direction == .outflow)
        #expect(item.amount == Self.aed(3000))
        // Anchored on the day it was entered, which this entry pays, so it keeps that day of the month
        #expect(item.schedule.start == rent.date)
        let occurrences = store.snapshot.occurrences.filter { $0.itemId == item.id }.sorted { $0.dueDate < $1.dueDate }
        #expect(occurrences.first?.paidEntryIds == [id])
        #expect(occurrences.first { $0.paidEntryIds.isEmpty }?.dueDate == LedgerStoreTests.date(2026, 11, 26))
    }

    @Test func editingReplacesTheOriginalAndNeverRepeats() throws {
        let original = try store.save(form(.expense, 120))
        var fixed = form(.expense, 95)
        fixed.repeats = true
        try store.save(fixed, replacing: original)
        #expect(store.snapshot.balance(bank.id) == Self.aed(4905))
        #expect(store.entryRecord(original)?.status == .void)
        #expect(store.snapshot.items.isEmpty)
    }

    @Test func theSameFormCantBeSavedTwice() throws {
        let once = form(.expense, 50)
        try store.save(once)
        _ = try? store.save(once)
        #expect(store.snapshot.balance(bank.id) == Self.aed(4950))
    }

    // MARK: - Accounts, categories, pay

    @Test func whatsOwedIsTypedPositiveAndKeptNegative() throws {
        let card = try store.addAccount(name: "Card", kind: .creditCard, balance: Self.aed(1200), openingDate: today)
        let loan = try store.addAccount(name: "Car", kind: .loan, balance: Self.aed(-30000), openingDate: today)
        #expect(store.snapshot.balance(card.id) == Self.aed(-1200))
        #expect(store.snapshot.balance(loan.id) == Self.aed(-30000))
        #expect(store.snapshot.balance(bank.id) == Self.aed(5000))
    }

    @Test func aNewCategoryKeepsItsBudgetSettings() throws {
        let gifts = try store.saveCategory(nil, name: " Gifts ", isIncome: false, group: "Lifestyle", policy: .reset,
                                           reserve: true, icon: "gift.fill", colorHex: "#FF0000")
        #expect(gifts.name == "Gifts")
        #expect(gifts.policy == .reset)
        #expect(gifts.reserveInSafeToSpend)

        try store.saveCategory(gifts, name: "Presents", isIncome: false, group: "Other", policy: .rollover,
                               reserve: false, icon: "gift.fill", colorHex: "#FF0000")
        #expect(gifts.name == "Presents" && gifts.group == "Other" && gifts.policy == .rollover)
        #expect(throws: StoreError.invalid("Give the category a name.")) {
            try store.saveCategory(gifts, name: "  ", isIncome: false, group: "Other", policy: .rollover,
                                   reserve: false, icon: "gift.fill", colorHex: "#FF0000")
        }
    }

    @Test func aPlanCantBeNegative() {
        #expect(throws: StoreError.invalid("The plan can't be negative.")) {
            try store.setAllocation(Self.aed(-10), categoryId: category("Groceries").id, month: store.snapshot.monthKey)
        }
    }

    @Test func settingUpPayAddsTheSalaryAndHowOftenItComes() throws {
        #expect(throws: StoreError.invalid("Enter your usual pay, or skip.")) {
            try store.setUpSalary(Self.aed(0), every: .monthly(every: 1), nextPayday: today)
        }
        try store.setUpSalary(Self.aed(20000), every: .monthly(every: 1), nextPayday: LedgerStoreTests.date(2026, 10, 28))
        let salary = try #require(store.snapshot.items.first { $0.name == "Salary" })
        #expect(salary.direction == .inflow)
        #expect(salary.accountId == bank.id)
        #expect(salary.categoryId == category("Salary").id)
        let saved = try #require(store.settings.payFrequencyData)
        #expect(try JSONDecoder().decode(Frequency.self, from: saved) == .monthly(every: 1))
    }

    // MARK: - Statement import

    @Test func importingSkipsWhatsRecordedAndNeverAddsARowTwice() throws {
        try store.save(EntryForm(kind: .expense, amount: Self.aed(245.5), accountId: bank.id,
                                 categoryId: category("Groceries").id, memo: "Carrefour", date: LedgerStoreTests.date(2026, 10, 5)))
        let csv = """
        Date,Description,Amount
        05/10/2026,CARREFOUR CITY,-245.50
        12/10/2026,ZZ UNKNOWN SHOP,-30.00
        """
        let review = StatementReview(accountId: bank.id, store: store)
        review.load(csv, named: "october.csv")
        #expect(review.rows.count == 2)
        #expect(review.matched.count == 1)
        let new = try #require(review.inbox.first)
        #expect(new.description == "ZZ UNKNOWN SHOP")

        review.targets[new.id] = .category(category("Groceries").id)
        review.add()
        #expect(review.added == 1)
        #expect(store.snapshot.balance(bank.id) == Self.aed(5000 - 245.5 - 30))

        // The same file again, matched or not, adds nothing
        let again = StatementReview(accountId: bank.id, store: store)
        again.load(csv, named: "october.csv")
        for row in again.inbox { again.targets[row.id] = .category(category("Groceries").id) }
        again.add()
        #expect(store.snapshot.balance(bank.id) == Self.aed(5000 - 245.5 - 30))
    }

    @Test func cardStatementsWithPositivePurchasesAreFlipped() throws {
        let card = try store.addAccount(name: "Card", kind: .creditCard, balance: Self.aed(0), openingDate: today)
        let review = StatementReview(accountId: card.id, store: store)
        review.load("Date,Description,Amount\n03/10/2026,NOON,99.00\n04/10/2026,TALABAT,40.00\n", named: "card.csv")
        #expect(review.flipSigns)
        #expect(review.rows.allSatisfy { $0.amount.isNegative })
    }

    // MARK: - Opening places

    @Test func aTappedReminderWaitsUntilTheScreensTakeIt() {
        let router = AppRouter()
        #expect(router.pending == nil)
        router.open(.bills)
        #expect(router.pending == .bills)
    }

    /// Capture results read as one word: ignored with why, needs review with what to check, or detected
    @Test("The guide answers questions about adding a debt with how to add one, not how to pay one",
          arguments: ["How do I add a debt", "I owe my brother money", "add my car loan", "where do I add a credit card"])
    func guideFindsAddingADebt(question: String) {
        #expect(AppGuide.match(question).first?.id == "addLoan")
    }

    @Test("The guide sends setup questions to the right automation, and problems to the fix",
          arguments: [("How do I set up Apple Pay", "applePay"), ("save my wallet purchases automatically", "applePay"),
                      ("read my bank sms", "bankMessages"), ("bank alert messages", "bankMessages"),
                      ("my apple pay automation isn't working", "automationOff"),
                      ("bank messages are not saving", "automationOff"), ("the automation is disabled", "automationOff")])
    func guideFindsAutomations(question: String, topic: String) {
        #expect(AppGuide.match(question).first?.id == topic)
    }

    @Test func automationStepsSayWhichAutomationToTurnOn() {
        let pay = AppGuide.applePaySetupSteps.joined(separator: " ")
        #expect(pay.contains("Add Shortcut") && pay.contains("Library") && pay.contains("Automation") && pay.contains("Wallet pass"))
        let bank = AppGuide.bankSetupSteps(keyword: "SAR").joined(separator: " ")
        #expect(bank.contains("Message Containing") && bank.contains("SAR"))
        // No country is assumed when the bank's currency isn't known
        #expect(!AppGuide.bankSetupSteps(keyword: nil).joined().contains("AED"))
        // A currency the shared shortcut doesn't cover gets an automation of its own that runs it
        let other = AppGuide.bankSetupSteps(keyword: "CAD").joined(separator: " ")
        #expect(other.contains("CAD") && other.contains("+") && other.contains(AppGuide.bankShortcutName))
    }

    @Test("Crash reports: only the newest five are kept, newest last")
    func crashReportsKeepTheNewest() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for day in 1...7 {
            ProblemReports.save(Data("{\"n\":\(day)}".utf8), at: Date(timeIntervalSince1970: Double(day) * 86_400), in: folder)
        }
        let kept = ProblemReports.reports(in: folder)
        #expect(kept.count == ProblemReports.kept)
        #expect(try Data(contentsOf: kept.last!) == Data("{\"n\":7}".utf8))
        #expect(try Data(contentsOf: kept.first!) == Data("{\"n\":3}".utf8))
    }

    @Test func captureVerdicts() {
        var ignored = CaptureTrace(date: today, source: .sms)
        ignored.add(CaptureTrace.reachedTitle, .done, "From Example Bank")
        ignored.add(CaptureTrace.readTitle, .failed, "It reads like a personal message, not a bank alert")
        ignored.add("Saved", .notReached, "Not tried")
        #expect(ignored.verdict == .ignored)
        #expect(ignored.explanation == "It reads like a personal message, not a bank alert")

        var review = CaptureTrace(date: today, source: .sms)
        review.add(CaptureTrace.savedTitle, .done, "To Checking in Groceries · To check: Check which account this was")
        #expect(review.verdict == .review)
        #expect(review.explanation == "Check which account this was. To Checking in Groceries")

        var saved = CaptureTrace(date: today, source: .applePay)
        saved.add(CaptureTrace.savedTitle, .done, "To Checking in Groceries")
        #expect(saved.verdict == .detected)
        #expect(saved.explanation == "To Checking in Groceries")
    }
}
