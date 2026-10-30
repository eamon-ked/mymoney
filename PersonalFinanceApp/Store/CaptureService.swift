//
//  CaptureService.swift
//  Nokael Money
//
//  Turns a purchase that arrived on its own (an Apple Pay tap, a bank SMS, a
//  sentence to Siri) into an entry. Every route ends here, so they all pick
//  accounts and categories the same way and never save the same purchase
//  twice. Automatic entries are saved straight away and flagged for review.
//

import Foundation
import CryptoKit
import NokaelCore

@MainActor
enum CaptureService {
    enum Outcome: Equatable {
        case saved(UUID)
        /// Already recorded, from another source or a retried automation
        case merged(UUID)
        case needsPlus
        /// Not saved, with a sentence saying why
        case skipped(String)

        var message: String {
            switch self {
            case .saved: return "Saved."
            case .merged: return "Already recorded."
            case .needsPlus: return "Automatic capture needs Nokael Plus. Open Nokael Money to upgrade."
            case .skipped(let reason): return reason
            }
        }

        /// How it reads in Settings after "From ADCB:" or "On ENBD Visa:"
        var logLine: String {
            switch self {
            case .saved: return "saved"
            case .merged: return "already recorded"
            case .needsPlus: return "not saved, needs Nokael Plus"
            case .skipped(let reason): return "not saved. \(reason)"
            }
        }
    }

    /// What the person already told us, e.g. through Siri
    struct Choices {
        var accountId: UUID?
        var categoryId: UUID?
    }

    static func record(_ capture: Capture, in store: LedgerStore, isPlus: Bool, choices: Choices = Choices()) async throws -> Outcome {
        if capture.source != .siri && !isPlus { return .needsPlus }
        let snapshot = store.snapshot
        guard snapshot.setupComplete else { return .skipped("Finish setting up Nokael Money first.") }
        guard capture.amount.currency == snapshot.currency else {
            return .skipped("That was \(MoneyFormat.string(capture.amount)). Add it yourself in \(snapshot.currency) so your balances stay right.")
        }
        guard capture.amount.isPositive else { return .skipped("There was no amount to save.") }

        if let existing = CaptureMatcher.duplicate(of: capture, in: recentEntries(snapshot, around: capture.date)) {
            try store.enrichCaptured(existing, cardHint: capture.cardHint)
            return .merged(existing)
        }

        let linked = capture.cardHint.flatMap(store.linkedAccount(forCard:))
        guard let accountId = choices.accountId ?? linked ?? defaultAccount(snapshot),
              let account = snapshot.account(accountId) else {
            return .skipped("Add an account in Nokael Money first.")
        }
        let isIncome = capture.direction == .received
        let category: LedgerAccountRecord
        if let chosen = snapshot.account(choices.categoryId) {
            category = chosen
        } else {
            category = try await self.category(for: capture.merchant, income: isIncome, snapshot: snapshot, store: store)
        }

        let memo = capture.merchant.isEmpty ? category.name : capture.merchant
        let key = idempotencyKey(capture)
        let entry = isIncome
            ? try EntryFactory.income(capture.amount, to: account.info, category: category.info, date: capture.date, memo: memo, key: key)
            : try EntryFactory.expense(capture.amount, from: account.info, category: category.info, date: capture.date, memo: memo, key: key)
        // Siri entries the person spelled out in full don't need a second look
        // One that looks like an unpaid bill is never linked by itself: it waits for the person to say
        let infos = Dictionary(snapshot.accountRecords.map { ($0.id, $0.info) }, uniquingKeysWith: { a, _ in a })
        let looksLikeBill = BillPayment(entry, accounts: infos).map { !snapshot.billCandidates(for: $0).isEmpty } ?? false
        let review = looksLikeBill || capture.source != .siri || choices.accountId == nil || choices.categoryId == nil
        let id = try store.postCaptured(entry, source: capture.source, cardHint: capture.cardHint, needsReview: review)
        return .saved(id)
    }

    // MARK: - Bank messages

    /// Reads an SMS alert. The rule-based reader goes first; Apple Intelligence
    /// helps when it can't make sense of the wording, and its amount is only
    /// trusted when that number really appears in the message.
    static func read(message: String, homeCurrency: String, date: Date) async -> Capture? {
        let parsed = AlertParser.read(message, homeCurrency: homeCurrency, date: date)
        if let parsed, !parsed.merchant.isEmpty { return parsed }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady,
           let ai = try? await MoneyAI.readAlert(message, homeCurrency: homeCurrency, date: date) {
            if var parsed {
                parsed.merchant = ai.merchant
                return parsed
            }
            return ai
        }
        #endif
        return parsed
    }

    /// Whether a message from this sender should be read at all
    static func accepts(sender: String?, settings: SettingsRecord) -> Bool {
        guard !settings.bankSenders.isEmpty, let sender, !sender.isEmpty else { return true }
        return BankSenders.matches(sender, any: settings.bankSenders)
    }

    // MARK: - Choosing

    static func defaultAccount(_ snapshot: FinanceSnapshot) -> UUID? {
        if let last = snapshot.account(snapshot.settings.lastUsedAccountId), last.spendable, !last.archived { return last.id }
        return snapshot.accounts.first(where: \.spendable)?.id
    }

    /// Last time's category for this shop, then well-known shops, then Apple Intelligence, then "Other"
    static func category(for merchant: String, income: Bool, snapshot: FinanceSnapshot, store: LedgerStore) async throws -> LedgerAccountRecord {
        let options = income ? snapshot.incomeCategories : snapshot.expenseCategories
        let kind: AccountKind = income ? .income : .expense
        let history: [(memo: String, categoryId: UUID)] = snapshot.entryRecords.compactMap { record in
            guard record.status == .posted, !record.needsReview,
                  let line = record.lines.first(where: { snapshot.account($0.accountId)?.kind == kind }) else { return nil }
            return (record.memo, line.accountId)
        }
        if !merchant.isEmpty, let id = StatementImport.category(for: merchant, history: history), let found = snapshot.account(id) {
            return found
        }
        if let name = CategoryRules.guess(merchant, income: income, categories: options.map(\.name)),
           let found = options.first(where: { $0.name == name }) {
            return found
        }
        // Money sent to another person is spending on them, even before there's a category for it
        if !income, CategoryRules.isSentToPeople(merchant) {
            let people = store.peopleCategory
            try? store.commit()
            return people
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), !merchant.isEmpty, AppleIntelligence.isReady {
            let examples = history.prefix(40).compactMap { past in snapshot.account(past.categoryId).map { (past.memo, $0.name) } }
            if let name = try? await MoneyAI.category(for: merchant, options: options.map(\.name), examples: examples),
               let found = options.first(where: { $0.name == name }) {
                return found
            }
        }
        #endif
        let fallback = income ? "Other income" : "Other spending"
        if let found = options.first(where: { $0.name == fallback }) { return found }
        return try store.createCategory(name: fallback, kind: kind, group: "Other", icon: "ellipsis.circle.fill")
    }

    /// Captured and typed entries near this time, for spotting the same purchase twice
    static func recentEntries(_ snapshot: FinanceSnapshot, around date: Date) -> [CapturedEntry] {
        snapshot.entryRecords.compactMap { record in
            guard record.status == .posted, abs(record.date.timeIntervalSince(date)) < 36 * 3600 else { return nil }
            let direction: Capture.Direction
            switch record.kind {
            case .expense: direction = .spent
            case .income: direction = .received
            default: return nil
            }
            let moved = record.lines.filter { $0.minorUnits > 0 }.reduce(Int64(0)) { $0 + $1.minorUnits }
            return CapturedEntry(id: record.id, date: record.date, amount: Money(minorUnits: moved, currency: snapshot.currency),
                                 direction: direction, memo: record.memo, source: record.source)
        }
    }

    /// The same message or tap run twice gives the same key, so it saves once
    static func idempotencyKey(_ capture: Capture) -> UUID {
        let minute = Int(capture.date.timeIntervalSince1970 / 60)
        let text = [capture.source.rawValue, capture.text, capture.merchant, capture.cardHint ?? "",
                    String(capture.amount.minorUnits), capture.source == .sms ? "" : String(minute)].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // name-based UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
