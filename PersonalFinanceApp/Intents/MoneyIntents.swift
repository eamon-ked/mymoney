//
//  MoneyIntents.swift
//  Nokael Money
//
//  What Siri and Shortcuts can do: add spending or income by voice, say
//  what's safe to spend, and take in Apple Pay taps and bank SMS alerts from
//  the person's own automations. All of them save through CaptureService.
//

import AppIntents
import NokaelCore

// MARK: - By voice (free)

struct LogSpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Spending"
    static let description = IntentDescription("Say what you spent, like \"45 at Carrefour\" or \"got 500 from Sam\".")

    @Parameter(title: "What happened", requestValueDialog: "What did you spend?")
    var sentence: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        let store = services.store
        if PaydayPlan.mentionsSalary(sentence) {
            let said = AlertParser.spoken(sentence, homeCurrency: store.currency, date: store.now())?.amount
            return .result(dialog: IntentDialog(stringLiteral: Self.recordSalary(said: said, store: store, isPlus: services.plus.isPlus)))
        }
        let now = store.now()
        var choices = CaptureService.Choices()
        var capture = AlertParser.spoken(sentence, homeCurrency: store.currency, date: now)
        // Apple Intelligence picks up the account and category when they're said
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady {
            let snapshot = store.snapshot
            if let draft = try? await MoneyAI.draft(from: sentence, categories: snapshot.expenseCategories.map(\.name),
                                                    income: snapshot.incomeCategories.map(\.name),
                                                    accounts: snapshot.accounts.filter(\.spendable).map(\.name), today: now),
               let amount = draft.amount, draft.kind != .transfer {
                let date = Calendar.current.date(byAdding: .day, value: -draft.daysAgo, to: now) ?? now
                capture = Capture(source: .siri, direction: draft.kind == .income ? .received : .spent,
                                  amount: Money(amount, currency: store.currency),
                                  merchant: draft.memo.isEmpty ? capture?.merchant ?? "" : draft.memo, date: date, text: sentence)
                let categories = draft.kind == .income ? snapshot.incomeCategories : snapshot.expenseCategories
                choices.categoryId = categories.first { $0.name == draft.category }?.id
                choices.accountId = snapshot.accounts.first { $0.name == draft.account }?.id
            }
        }
        #endif
        guard let capture else {
            return .result(dialog: "I didn't catch an amount. Try \"45 at Carrefour\".")
        }
        let outcome = try await CaptureService.record(capture, in: store, isPlus: services.plus.isPlus, choices: choices)
        WidgetSync.update(store.snapshot, isPlus: services.plus.isPlus)
        return .result(dialog: IntentDialog(stringLiteral: Self.summary(outcome, store: store)))
    }

    /// Salary from what's saved in Plan; the rest of payday is offered in the app
    @MainActor static func recordSalary(said: Money?, store: LedgerStore, isPlus: Bool) -> String {
        let plan = PaydayPlan.make(store.snapshot, said: said)
        if let when = plan.alreadyReceived, said == nil {
            return "This month's salary is already recorded, on \(when.formatted(.dateTime.day().month(.wide)))."
        }
        guard plan.amount.isPositive else {
            return "How much was it? Say for example “I got my salary, 20,000”."
        }
        var choices = PaydayPlan.Choices()
        choices.copyBudget = false
        do {
            let done = try plan.run(store, choices: choices, date: store.now(), key: UUID())
            WidgetSync.update(store.snapshot, isPlus: isPlus)
            let more = plan.budgetFrom != nil || !plan.goals.isEmpty ? " Open Nokael Money to plan the month." : ""
            return done[0] + "." + more
        } catch {
            return StoreError.from(error).errorDescription ?? "Couldn't record it."
        }
    }

    @MainActor static func summary(_ outcome: CaptureService.Outcome, store: LedgerStore) -> String {
        guard case .saved(let id) = outcome, let record = store.entryRecord(id) else { return outcome.message }
        let snapshot = store.snapshot
        let names = record.lines.compactMap { snapshot.account($0.accountId) }
        let category = names.first { $0.kind.isCategory }?.name ?? ""
        let account = names.first { $0.kind.isBalanceSheet }?.name ?? ""
        let moved = record.lines.filter { $0.minorUnits > 0 }.reduce(Int64(0)) { $0 + $1.minorUnits }
        let amount = MoneyFormat.string(Money(minorUnits: moved, currency: store.currency))
        let verb = record.kind == .income ? "into" : "from"
        return "Saved \(amount) for \(record.memo) under \(category), \(verb) \(account)."
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Add spending with the amount, shop, category and account.")

    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amount: Double

    @Parameter(title: "Shop or description", requestValueDialog: "Where was it?")
    var merchant: String?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Account")
    var account: AccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) at \(\.$merchant)") {
            \.$category
            \.$account
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        let store = services.store
        guard let value = Decimal(string: String(format: "%.2f", amount)) else {
            return .result(dialog: "That amount didn't look right.")
        }
        let capture = Capture(source: .siri, direction: .spent, amount: Money(value, currency: store.currency),
                              merchant: merchant ?? "", date: store.now(), text: "expense")
        let outcome = try await CaptureService.record(capture, in: store, isPlus: services.plus.isPlus,
                                                      choices: .init(accountId: account?.id, categoryId: category?.id))
        WidgetSync.update(store.snapshot, isPlus: services.plus.isPlus)
        return .result(dialog: IntentDialog(stringLiteral: LogSpendingIntent.summary(outcome, store: store)))
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let description = IntentDescription("Add money you received.")

    @Parameter(title: "Amount", requestValueDialog: "How much came in?")
    var amount: Double

    @Parameter(title: "From", requestValueDialog: "Who was it from?")
    var payer: String?

    @Parameter(title: "Account")
    var account: AccountEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        let store = services.store
        guard let value = Decimal(string: String(format: "%.2f", amount)) else {
            return .result(dialog: "That amount didn't look right.")
        }
        if PaydayPlan.mentionsSalary(payer ?? "") {
            let said = Money(value, currency: store.currency)
            return .result(dialog: IntentDialog(stringLiteral: LogSpendingIntent.recordSalary(said: said, store: store, isPlus: services.plus.isPlus)))
        }
        let capture = Capture(source: .siri, direction: .received, amount: Money(value, currency: store.currency),
                              merchant: payer ?? "", date: store.now(), text: "income")
        let outcome = try await CaptureService.record(capture, in: store, isPlus: services.plus.isPlus,
                                                      choices: .init(accountId: account?.id))
        WidgetSync.update(store.snapshot, isPlus: services.plus.isPlus)
        return .result(dialog: IntentDialog(stringLiteral: LogSpendingIntent.summary(outcome, store: store)))
    }
}

struct SafeToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Safe to Spend"
    static let description = IntentDescription("Hear how much you can spend freely until payday.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = AppServices.shared.store.snapshot
        let sts = snapshot.safeToSpend()
        guard snapshot.setupComplete, let amount = sts.amount else {
            return .result(value: "", dialog: "Finish setting up Nokael Money first.")
        }
        let until = sts.periodEnd.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let text = amount.isNegative
            ? "Your bills and plans are \(MoneyFormat.string(amount.magnitude)) more than you have until \(until)."
            : "You can spend \(MoneyFormat.string(amount)) until \(until)."
        return .result(value: MoneyFormat.string(amount), dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - From automations (Plus)

struct LogApplePayIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Apple Pay Purchase"
    static let description = IntentDescription("""
        Use in a Shortcuts automation: Automation › Transaction, then pass in the Card, Merchant and Amount. \
        Each Apple Pay purchase is saved for you to review.
        """)
    static let isDiscoverable = true

    @Parameter(title: "Amount")
    var amount: IntentCurrencyAmount

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) on \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        await services.plus.refresh()
        let code = amount.currencyCode.isEmpty ? services.store.currency : amount.currencyCode.uppercased()
        // Refunds arrive as negative amounts
        let money = Money(amount.amount, currency: code)
        let capture = Capture(source: .applePay, direction: money.isNegative ? .received : .spent, amount: money.magnitude,
                              merchant: merchant ?? "", cardHint: card, date: services.store.now(),
                              text: [card ?? "", merchant ?? "", "\(amount.amount)"].joined(separator: "|"))
        let outcome = try await CaptureService.record(capture, in: services.store, isPlus: services.plus.isPlus)
        WidgetSync.update(services.store.snapshot, isPlus: services.plus.isPlus)
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

struct LogBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Bank Message"
    static let description = IntentDescription("""
        Use in a Shortcuts automation: Automation › Message, then pass in the Message and its Sender. \
        Purchases and deposits in your bank's alerts are saved for you to review; everything else is ignored.
        """)

    @Parameter(title: "Message", inputConnectionBehavior: .connectToPreviousIntentResult)
    var message: String

    @Parameter(title: "Sender")
    var sender: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Read \(\.$message) from \(\.$sender)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        let store = services.store
        await services.plus.refresh()
        // An automation wired with the whole input as Sender passes the message twice; treat that as no sender
        let sender = sender.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty || $0 == message.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : $0 }
        guard CaptureService.accepts(sender: sender, settings: store.settings) else {
            store.noteBankMessage(from: sender, outcome: "ignored, not one of your banks")
            return .result(dialog: "Not from one of your banks, so it was ignored.")
        }
        guard let capture = await CaptureService.read(message: message, homeCurrency: store.currency, date: store.now()) else {
            store.noteBankMessage(from: sender, outcome: "no purchase or deposit found in it")
            return .result(dialog: "No purchase or deposit in that message.")
        }
        let outcome: CaptureService.Outcome
        do {
            outcome = try await CaptureService.record(capture, in: store, isPlus: services.plus.isPlus)
        } catch {
            store.noteBankMessage(from: sender, outcome: "couldn't be saved")
            throw error
        }
        store.noteBankMessage(from: sender, outcome: outcome == .needsPlus ? "not saved, needs Nokael Plus" : outcome.message.lowercased())
        WidgetSync.update(store.snapshot, isPlus: services.plus.isPlus)
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

// MARK: - Siri phrases

struct NokaelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogSpendingIntent(), phrases: [
            "Log spending in \(.applicationName)",
            "Add an expense in \(.applicationName)",
            "Add to \(.applicationName)",
            "I spent money in \(.applicationName)",
        ], shortTitle: "Log Spending", systemImageName: "plus.circle.fill")
        AppShortcut(intent: SafeToSpendIntent(), phrases: [
            "What's safe to spend in \(.applicationName)",
            "How much can I spend in \(.applicationName)",
            "Check my budget in \(.applicationName)",
        ], shortTitle: "Safe to Spend", systemImageName: "checkmark.shield.fill")
        AppShortcut(intent: AddIncomeIntent(), phrases: [
            "Add income in \(.applicationName)",
            "I got paid in \(.applicationName)",
        ], shortTitle: "Add Income", systemImageName: "arrow.down.circle.fill")
        AppShortcut(intent: LogApplePayIntent(), phrases: [
            "Log Apple Pay purchase in \(.applicationName)",
        ], shortTitle: "Log Apple Pay", systemImageName: "wallet.pass.fill")
        AppShortcut(intent: LogBankMessageIntent(), phrases: [
            "Read bank message in \(.applicationName)",
        ], shortTitle: "Read Bank Message", systemImageName: "message.fill")
    }
}
