//
//  StatementColumnsAI.swift
//  Nokael Money
//
//  When a statement's values can't settle which column is which (two money
//  columns and no balance to tell money out from money in), the on-device model
//  reads the column names and a few rows and answers only that. Its answer is
//  used only if the whole file then reads, and the person sees and can change it.
//

import Foundation
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
extension MoneyAI {

    /// The columns with the open question answered, or nil when the model can't tell
    static func statementColumns(_ question: ColumnQuestion, layout: StatementLayout, partial: StatementColumns) async throws -> StatementColumns? {
        func label(_ i: Int) -> String { "\(i + 1). \(layout.name(i))" }
        let table = ([layout.names.indices.map(label).joined(separator: " | ")]
                     + layout.samples.prefix(5).map { row in layout.names.indices.map { $0 < row.count ? row[$0] : "" }.joined(separator: " | ") })
            .joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You read the columns of a bank statement. The first line names the columns, the rest are rows. \
            The column names and descriptions may be in any language. Answer only from what the rows show.
            """)
        var out = partial
        switch question {
        case .outOrIn(let a, let b):
            let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Column", anyOf: [label(a), label(b)]), dependencies: [])
            let answer = try await session.respond(
                to: "\(table)\n\nColumns \(label(a)) and \(label(b)) hold money. Which one is money going out of the account (spent, withdrawn, paid)?",
                schema: schema, options: GenerationOptions(samplingMode: .greedy))
            let out1 = try answer.content.value(String.self)
            let outColumn = out1 == label(a) ? a : b
            out.amount = nil
            out.debit = outColumn
            out.credit = outColumn == a ? b : a
        case .whichAmount(let columns):
            let none = "none"
            let amount = try GenerationSchema(root: DynamicGenerationSchema(name: "Column", anyOf: columns.map(label)), dependencies: [])
            let a = try await session.respond(
                to: "\(table)\n\nWhich column is the amount of money each row moved (not the balance left afterwards)?",
                schema: amount, options: GenerationOptions(samplingMode: .greedy))
            let chosen = try a.content.value(String.self)
            guard let amountColumn = columns.first(where: { label($0) == chosen }) else { return nil }
            let rest = columns.filter { $0 != amountColumn }
            let balance = try GenerationSchema(root: DynamicGenerationSchema(name: "Balance", anyOf: rest.map(label) + [none]), dependencies: [])
            let b = try await session.respond(
                to: "Which column is the balance left in the account after each row, or none?",
                schema: balance, options: GenerationOptions(samplingMode: .greedy))
            let balanceName = try b.content.value(String.self)
            out.debit = nil
            out.credit = nil
            out.amount = amountColumn
            out.balance = rest.first { label($0) == balanceName }
        }
        return out
    }
}
#endif
