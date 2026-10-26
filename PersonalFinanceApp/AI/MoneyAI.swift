//
//  MoneyAI.swift
//  Nokael Money
//
//  What the on-device model does for the app: read a sentence into a draft
//  entry, guess a category from a description, sum up the month, and answer
//  questions using tools that read the FinanceDigest. Nothing is saved without
//  the person tapping Save, so a wrong guess costs nothing.
//

import Foundation
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A sentence read into the editor's fields; any part may be missing
struct DraftEntry: Equatable {
    var kind: AddKind = .expense
    var amount: Decimal?
    var memo = ""
    var category: String?
    var account: String?
    var toAccount: String?
    var daysAgo = 0
}

struct MonthInsight: Equatable {
    var headline: String
    var tips: [String]
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
enum MoneyAI {

    // MARK: - Quick add from a sentence

    static func draft(from sentence: String, categories expense: [String], income: [String],
                      accounts: [String], today: Date) async throws -> DraftEntry {
        func choice(_ name: String, _ options: [String]) -> DynamicGenerationSchema {
            options.isEmpty ? DynamicGenerationSchema(type: String.self) : DynamicGenerationSchema(name: name, anyOf: options)
        }
        let categoryNames = Array(Set(expense + income)).sorted()
        let root = DynamicGenerationSchema(name: "Entry", properties: [
            .init(name: "kind", description: "expense for money spent, income for money received, transfer for moving money between own accounts",
                  schema: DynamicGenerationSchema(name: "Kind", anyOf: ["expense", "income", "transfer"])),
            .init(name: "amount", description: "The amount as a plain number, without currency", schema: DynamicGenerationSchema(type: Double.self)),
            .init(name: "description", description: "Short name of the shop, payer or purpose, e.g. Carrefour or October salary",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "category", description: "The best matching category", schema: choice("Category", categoryNames)),
            .init(name: "account", description: "The account paid from or into, only if mentioned", schema: choice("Account", accounts), isOptional: true),
            .init(name: "toAccount", description: "For transfers, the account the money goes to", schema: choice("ToAccount", accounts), isOptional: true),
            .init(name: "daysAgo", description: "0 for today, 1 for yesterday, and so on", schema: DynamicGenerationSchema(type: Int.self)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])
        let session = LanguageModelSession(instructions: """
            Turn one sentence about money into a ledger entry. Today is \(today.formatted(.dateTime.weekday(.wide).day().month(.wide).year())). \
            Expense categories: \(expense.joined(separator: ", ")). Income categories: \(income.joined(separator: ", ")).
            """)
        let response = try await session.respond(to: sentence, schema: schema, options: GenerationOptions(sampling: .greedy))
        let content = response.content

        var draft = DraftEntry()
        let kind = (try? content.value(String.self, forProperty: "kind")) ?? "expense"
        draft.kind = AddKind(rawValue: kind) ?? .expense
        if let amount = try? content.value(Double.self, forProperty: "amount"), amount > 0 {
            draft.amount = Decimal(string: String(format: "%.2f", amount))
        }
        draft.memo = (try? content.value(String.self, forProperty: "description")) ?? ""
        draft.category = try? content.value(String.self, forProperty: "category")
        draft.account = try? content.value(String?.self, forProperty: "account")
        draft.toAccount = try? content.value(String?.self, forProperty: "toAccount")
        draft.daysAgo = max(0, min(60, (try? content.value(Int.self, forProperty: "daysAgo")) ?? 0))
        return draft
    }

    // MARK: - Category from a description

    /// `examples` are past descriptions and the category they were filed under
    static func category(for memo: String, options: [String], examples: [(String, String)]) async throws -> String? {
        guard options.count > 1 else { return options.first }
        let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Category", anyOf: options), dependencies: [])
        let shown = examples.prefix(12).map { "\($0.0) → \($0.1)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            Pick the budget category a purchase or payment belongs in.\(shown.isEmpty ? "" : " Past choices:\n\(shown)")
            """)
        let response = try await session.respond(to: memo, schema: schema, options: GenerationOptions(sampling: .greedy))
        return try response.content.value(String.self)
    }

    // MARK: - Bank SMS alerts

    @Generable
    struct AlertOutput {
        @Guide(description: "True only if money actually left or arrived in the account; false for codes, offers, reminders, declines")
        var isTransaction: Bool
        @Guide(description: "true if money was received or refunded, false if spent or sent")
        var isIncoming: Bool
        @Guide(description: "The amount moved, as a plain number without currency")
        var amount: Double
        @Guide(description: "Three-letter currency code of that amount, e.g. AED")
        var currency: String
        @Guide(description: "The shop, payee or payer, in normal capitalisation; empty if none")
        var merchant: String
        @Guide(description: "Last four digits of the card or account, or empty")
        var cardLast4: String
    }

    /// Reads a bank alert the rule-based reader couldn't. The amount must
    /// appear in the message, so a made-up number is never saved.
    static func readAlert(_ text: String, homeCurrency: String, date: Date) async throws -> Capture? {
        let session = LanguageModelSession(instructions: """
            Read one SMS from a bank and say whether it reports money moving, how much, and where. \
            Ignore available balances and credit limits; they are not the amount moved.
            """)
        let out = try await session.respond(to: text, generating: AlertOutput.self, options: GenerationOptions(sampling: .greedy)).content
        guard out.isTransaction, out.amount > 0 else { return nil }
        let code = out.currency.uppercased().count == 3 ? out.currency.uppercased() : homeCurrency
        let money = Money(Decimal(string: String(format: "%.2f", out.amount)) ?? 0, currency: code)
        let digitsInText = text.filter { $0.isNumber }
        let amountDigits = String(format: "%.2f", out.amount).filter(\.isNumber)
        let whole = String(Int(out.amount))
        guard digitsInText.contains(amountDigits.hasSuffix("00") ? whole : amountDigits) else { return nil }
        let card = out.cardLast4.filter(\.isNumber)
        return Capture(source: .sms, direction: out.isIncoming ? .received : .spent, amount: money,
                       merchant: out.merchant.trimmingCharacters(in: .whitespaces),
                       cardHint: card.count == 4 ? card : nil, date: date, text: text)
    }

    // MARK: - The month in a few lines

    @Generable
    struct InsightOutput {
        @Guide(description: "One or two sentences on how the month is going, with real figures")
        var headline: String
        @Guide(description: "Practical, specific suggestions based on the figures", .maximumCount(2))
        var tips: [String]
    }

    static func insight(_ digest: FinanceDigest) async throws -> MonthInsight {
        let session = LanguageModelSession(instructions: AppleIntelligence.baseInstructions)
        let prompt = """
            Summarise how this person's money is doing right now and suggest up to two useful next steps. \
            Be encouraging but honest; mention overspent categories or overdue bills only if the figures say so. \
            Planned amounts and upcoming bills are not money already spent.

            \(digest.overview)

            \(digest.budget(monthKey: nil))

            \(digest.billsText)

            \(digest.months.prefix(2).map { "\($0.title): income \($0.income), spending \($0.spending)" }.joined(separator: "\n"))
            """
        let response = try await session.respond(to: prompt, generating: InsightOutput.self)
        return MonthInsight(headline: response.content.headline, tips: response.content.tips)
    }

    /// A short story of one month for Reports
    static func monthStory(_ digest: FinanceDigest, monthKey: String) -> LanguageModelSession.ResponseStream<String> {
        let session = LanguageModelSession(instructions: AppleIntelligence.baseInstructions)
        let previous = BudgetMonth.adding(-1, to: monthKey, calendar: .current)
        return session.streamResponse(to: """
            In three or four sentences, explain where this person's money went in the month below compared with the month before, \
            and what stands out. No headings or lists.

            \(digest.monthSummary(monthKey))
            \(digest.monthSummary(previous))
            """)
    }

    // MARK: - Ask about your money

    static func assistantSession(_ digest: FinanceDigest) -> LanguageModelSession {
        LanguageModelSession(
            tools: [BudgetTool(digest: digest), TransactionsTool(digest: digest), TrendTool(digest: digest), BillsTool(digest: digest)],
            instructions: """
                \(AppleIntelligence.baseInstructions) \
                Answer questions about the person's money. Use the tools for budgets, transactions, past months and bills. \
                Keep answers to a few sentences unless asked for detail.

                \(digest.overview)
                """)
    }
}

// MARK: - Tools the assistant can call

@available(iOS 26.0, *)
struct BudgetTool: Tool {
    let digest: FinanceDigest
    let name = "getBudget"
    let description = "Planned, spent and remaining for each spending category this month, or a past month's totals"

    @Generable
    struct Arguments {
        @Guide(description: "Month as yyyy-MM, or empty for this month")
        var month: String?
    }

    func call(arguments: Arguments) async throws -> String {
        digest.budget(monthKey: arguments.month.flatMap { $0.isEmpty ? nil : $0 })
    }
}

@available(iOS 26.0, *)
struct TransactionsTool: Tool {
    let digest: FinanceDigest
    let name = "searchTransactions"
    let description = "Find recorded expenses, income and transfers by description or category, with totals"

    @Generable
    struct Arguments {
        @Guide(description: "Words in the description, e.g. a shop name; empty for any")
        var text: String?
        @Guide(description: "Category name to filter by; empty for any")
        var category: String?
        @Guide(description: "Only the last this many days; empty for all")
        var days: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        digest.search(text: arguments.text, category: arguments.category, days: arguments.days)
    }
}

@available(iOS 26.0, *)
struct TrendTool: Tool {
    let digest: FinanceDigest
    let name = "getMonthlyTotals"
    let description = "Income, spending, money left over and top categories for each of the last six months"

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String { digest.trend }
}

@available(iOS 26.0, *)
struct BillsTool: Tool {
    let digest: FinanceDigest
    let name = "getUpcomingBills"
    let description = "Unpaid bills that are overdue or due in the next 45 days"

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String { digest.billsText }
}

#endif
