//
//  CaptureTrace.swift
//  Nokael Money
//
//  What became of one bank message or Wallet tap, step by step: it reached the
//  app, it was read, Nokael Plus was on, and it was saved (or exactly why not).
//  Kept in the change history so Settings can show the last few, and so the
//  capture test in Settings can show the same steps before anything is saved.
//  The message itself is never kept.
//

import Foundation
import NokaelCore

struct CaptureTrace: Codable, Equatable, Identifiable {
    static let action = "capture.trace"

    enum Mark: String, Codable { case done, failed, notReached }

    struct Step: Codable, Equatable, Identifiable {
        var title: String
        var mark: Mark
        var detail: String
        var id: String { title }
    }

    /// What was read from the message: enough to add it by hand or split it from an entry it joined.
    /// Never the message itself.
    struct Read: Codable, Equatable {
        var spent: Bool
        var minorUnits: Int64
        var currency: String
        var name: String
        var date: Date
        var cardHint: String?
        var accountHint: String?
        var otherAccountHint: String?
        var reference: String?
        var isTransfer: Bool
        var isReversal: Bool
        var shape: String?
        var balanceMinor: Int64?

        init(_ c: Capture) {
            spent = c.direction == .spent
            minorUnits = c.amount.minorUnits
            currency = c.amount.currency
            name = c.merchant
            date = c.date
            cardHint = c.cardHint
            accountHint = c.accountHint
            otherAccountHint = c.otherAccountHint
            reference = c.reference
            isTransfer = c.isTransfer
            isReversal = c.isReversal
            shape = c.shape
            balanceMinor = c.balance.flatMap { $0.currency == c.amount.currency ? $0.minorUnits : nil }
        }

        var amount: Money { Money(minorUnits: minorUnits, currency: currency) }

        var capture: Capture {
            Capture(source: .sms, direction: spent ? .spent : .received, amount: amount, merchant: name, cardHint: cardHint,
                    date: date, accountHint: accountHint, otherAccountHint: otherAccountHint, reference: reference,
                    isTransfer: isTransfer, isReversal: isReversal, dateFromMessage: true, shape: shape,
                    balance: balanceMinor.map { Money(minorUnits: $0, currency: currency) })
        }

        var mark: CapturedEntry.MessageMark {
            .init(shape: shape, accountHint: accountHint, balance: balanceMinor.map { Money(minorUnits: $0, currency: currency) })
        }

        /// Older records kept only the "Read" line ("Spent AED 150.00 to Sam · transfer · account ••560001 ·
        /// 11 Nov 2026 at 00:57"): what it says, as far as it goes
        init?(line: String, arrived: Date, currency: String) {
            let parts = line.components(separatedBy: " · ")
            guard let head = parts.first, head.hasPrefix("Spent ") || head.hasPrefix("Received ") else { return nil }
            guard let read = AlertParser.read(head, homeCurrency: currency, date: arrived) else { return nil }
            self.init(read)
            spent = head.hasPrefix("Spent ")
            for part in parts.dropFirst() {
                func digits(after prefix: String) -> String? {
                    part.hasPrefix(prefix) ? String(part.dropFirst(prefix.count)) : nil
                }
                if part == "transfer" { isTransfer = true }
                else if part == "money back" { isReversal = true }
                else if let d = digits(after: "card ••") { cardHint = d }
                else if let d = digits(after: "account ••") { accountHint = d }
                else if let d = digits(after: "other account ••") { otherAccountHint = d }
                else if let r = digits(after: "ref ") { reference = r }
                else if let when = try? Date.FormatStyle(date: .abbreviated, time: .shortened).parse(part) { date = when }
            }
            shape = nil
        }
    }

    var id = UUID()
    var date: Date
    var source: Capture.Source
    var steps: [Step]
    var entryId: UUID?
    var read: Read?
    /// It told of a movement already saved from another message, and joined that entry
    var joined: Bool?
    /// Saved on its own, but it may be the same movement as this entry
    var maybeSameAs: UUID?

    /// What was read, from this record or, for older ones, from its "Read" line
    func readDetails(currency: String) -> Read? {
        if let read { return read }
        guard source == .sms, let line = steps.first(where: { $0.title == Self.readTitle && $0.mark == .done })?.detail else { return nil }
        return Read(line: line, arrived: date, currency: currency)
    }

    var saved: Bool { steps.last?.mark == .done && steps.allSatisfy { $0.mark == .done } }

    /// One line for the list: what happened, without the message
    var headline: String {
        if let failed = steps.first(where: { $0.mark == .failed }) { return "\(failed.title): \(failed.detail)" }
        return steps.last.map { "\($0.title): \($0.detail)" } ?? ""
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    init(date: Date, source: Capture.Source, steps: [Step] = [], entryId: UUID? = nil) {
        self.date = date
        self.source = source
        self.steps = steps
        self.entryId = entryId
    }

    init?(audit: AuditRecord) {
        guard let data = audit.reason?.data(using: .utf8), var trace = try? JSONDecoder().decode(CaptureTrace.self, from: data) else { return nil }
        trace.id = audit.id
        self = trace
    }

    mutating func add(_ title: String, _ mark: Mark, _ detail: String) {
        steps.append(Step(title: title, mark: mark, detail: detail))
    }

    // MARK: - Wording

    static let reachedTitle = "Reached Nokael Money"
    static let readTitle = "Read"
    static let plusTitle = "Nokael Plus"
    static let savedTitle = "Saved"

    /// "Spent AED 45.00 at Carrefour · card ••4417 · account ••730001 · ref 4169… · 3 Nov, 12:22"
    static func describe(_ capture: Capture) -> String {
        var parts = [(capture.direction == .spent ? "Spent " : "Received ") + MoneyFormat.string(capture.amount)]
        if !capture.merchant.isEmpty {
            parts[0] += (capture.direction == .received ? " from " : capture.isTransfer ? " to " : " at ") + capture.merchant
        }
        if capture.isTransfer { parts.append("transfer") }
        if capture.isReversal { parts.append("money back") }
        if let card = capture.cardHint { parts.append(card.allSatisfy(\.isNumber) ? "card ••\(card)" : card) }
        if let account = capture.accountHint { parts.append("account ••\(account)") }
        if let other = capture.otherAccountHint { parts.append("other account ••\(other)") }
        if let reference = capture.reference { parts.append("ref \(reference)") }
        if capture.dateFromMessage { parts.append(capture.date.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    /// The last step, from what saving did or would do
    @MainActor static func savedStep(_ outcome: CaptureService.Outcome, plan: CaptureService.Plan?, in store: LedgerStore, dryRun: Bool = false) -> Step {
        func label(_ id: UUID?) -> String { id.flatMap { store.account($0)?.name } ?? "an account" }
        let would = dryRun ? "Would be saved" : savedTitle
        switch outcome {
        case .saved(let id), .merged(let id), .joined(let id), .reversed(let id):
            let record = store.entryRecord(id)
            switch outcome {
            case .joined:
                return Step(title: savedTitle, mark: .done,
                            detail: "Joined with the bank's earlier message about it: \"\(record?.memo ?? "")\", so it isn't counted twice")
            case .merged:
                return Step(title: dryRun ? "Would be saved" : savedTitle, mark: .done,
                            detail: record?.kind == .transfer ? "Joined with the other bank's half of this transfer, as one transfer"
                                                              : "Already recorded, so not saved twice")
            case .reversed:
                return Step(title: would, mark: .done, detail: "Removed the earlier charge \"\(record?.memo ?? "")\" that the bank gave back")
            default:
                break
            }
            let where_ = record.map { r in
                r.kind == .transfer
                    ? "As a transfer between \(r.lines.compactMap { store.account($0.accountId)?.name }.joined(separator: " and "))"
                    : "To \(label(r.lines.first { store.account($0.accountId)?.kind.isBalanceSheet == true }?.accountId)) in \(r.lines.compactMap { store.account($0.accountId) }.first { $0.kind.isCategory }?.name ?? "")"
            } ?? "Saved"
            let ask = record?.reviewReason.map { " · To check: \($0)" } ?? ""
            return Step(title: would, mark: .done, detail: where_ + ask)
        case .needsPlus:
            return Step(title: would, mark: .notReached, detail: "Not tried")
        case .skipped(let reason):
            return Step(title: would, mark: .failed, detail: reason)
        }
    }

    /// The same last step for the capture test, from the plan alone
    @MainActor static func plannedStep(_ plan: CaptureService.Plan, capture: Capture, in store: LedgerStore) -> Step {
        func name(_ id: UUID?) -> String { id.flatMap { store.account($0)?.name } ?? "an account" }
        let title = "Would be saved"
        switch plan.decision {
        case .skip(let reason):
            return Step(title: title, mark: .failed, detail: reason)
        case .duplicate(let id):
            let memo = store.entryRecord(id)?.memo ?? ""
            return Step(title: title, mark: .done, detail: "Already recorded as \"\(memo)\", so it wouldn't be saved twice")
        case .reverse(let id):
            return Step(title: title, mark: .done, detail: "Would remove the earlier charge \"\(store.entryRecord(id)?.memo ?? "")\" that the bank gave back")
        case .transfer(let other):
            let (from, to) = capture.direction == .spent ? (plan.route.accountId, other) : (other, plan.route.accountId)
            return Step(title: title, mark: .done, detail: "As a transfer from \(name(from)) to \(name(to))")
        case .save:
            var detail = "To \(name(plan.route.accountId)) in \(plan.category?.name ?? "")"
            if let ask = CaptureService.reviewReason(capture, plan: plan) { detail += " · To check: \(ask)" }
            return Step(title: title, mark: .done, detail: detail)
        }
    }
}

// MARK: - The whole way through

extension CaptureService {
    struct Run {
        var outcome: Outcome?
        var trace: CaptureTrace
        var capture: Capture?
    }

    /// A bank message from the Shortcuts automation: checked against your banks, read, checked for Plus and
    /// saved, with each step noted for Settings. With `dryRun` nothing is saved or noted: it's the capture test.
    static func runBankMessage(_ message: String, sender: String?, store: LedgerStore, isPlus: Bool,
                               dryRun: Bool = false, useAI: Bool = true) async -> Run {
        let arrived = store.now()
        var trace = CaptureTrace(date: arrived, source: .sms)
        let from = sender.flatMap { $0.isEmpty ? nil : $0 }
        func finish(_ outcome: Outcome?, _ capture: Capture?, _ trace: CaptureTrace) -> Run {
            if !dryRun {
                store.noteCaptureTrace(trace)
                store.noteBankMessage(from: from, outcome: outcome?.logLine ?? trace.headline)
            }
            return Run(outcome: outcome, trace: trace, capture: capture)
        }
        guard accepts(sender: from, settings: store.settings) else {
            trace.add(CaptureTrace.reachedTitle, .failed, "From \(from ?? "an unknown sender"), which isn't one of your banks in Settings, so it was ignored")
            return finish(nil, nil, trace)
        }
        trace.add(CaptureTrace.reachedTitle, .done, from.map { "From \($0)" } ?? "Sender not passed in, so it's read only if it looks like a bank alert")
        let fromBank = from != nil && !store.settings.bankSenders.isEmpty
        let reading = await examine(message: message, store: store, date: arrived, useAI: useAI, fromBank: fromBank)
        guard case .capture(let capture) = reading else {
            if case .ignored(let reason) = reading { trace.add(CaptureTrace.readTitle, .failed, reason.sentence) }
            return finish(.skipped("No purchase or deposit in that message."), nil, trace)
        }
        trace.add(CaptureTrace.readTitle, .done, CaptureTrace.describe(capture))
        return await finishRun(capture, trace: trace, store: store, isPlus: isPlus, dryRun: dryRun, finish: finish)
    }

    /// A Wallet tap from the Transaction automation, the same way
    static func runCardPurchase(_ capture: Capture, store: LedgerStore, isPlus: Bool, dryRun: Bool = false) async -> Run {
        var trace = CaptureTrace(date: store.now(), source: .applePay)
        func finish(_ outcome: Outcome?, _ capture: Capture?, _ trace: CaptureTrace) -> Run {
            if !dryRun {
                store.noteCaptureTrace(trace)
                store.noteCardPurchase(card: capture?.cardHint, outcome: outcome?.logLine ?? trace.headline)
            }
            return Run(outcome: outcome, trace: trace, capture: capture)
        }
        trace.add(CaptureTrace.reachedTitle, .done, capture.cardHint.map { "On \($0)" } ?? "No card name passed in")
        trace.add(CaptureTrace.readTitle, .done, CaptureTrace.describe(capture))
        return await finishRun(capture, trace: trace, store: store, isPlus: isPlus, dryRun: dryRun, finish: finish)
    }

    /// An entry saved from a bank message just before, for the same money, that nothing tells apart from this one
    /// (it came before records kept what a message looked like): saved anyway, but flagged
    static func maybeSame(_ capture: Capture, saved id: UUID, in store: LedgerStore) -> UUID? {
        let recent = recentEntries(store.snapshot, around: capture.date, store: store)
        return recent.first { e in
            e.id != id && e.source == .sms && e.messages.isEmpty && e.amount == capture.amount && e.direction == capture.direction
                && abs(e.date.timeIntervalSince(capture.date)) <= CaptureMatcher.messageWindow
        }?.id
    }

    private static func finishRun(_ capture: Capture, trace start: CaptureTrace, store: LedgerStore, isPlus: Bool, dryRun: Bool,
                                  finish: (Outcome?, Capture?, CaptureTrace) -> Run) async -> Run {
        var trace = start
        if capture.source == .sms { trace.read = CaptureTrace.Read(capture) }
        guard isPlus else {
            trace.add(CaptureTrace.plusTitle, .failed, "Automatic capture needs Nokael Plus, so it wasn't saved")
            trace.add(dryRun ? "Would be saved" : CaptureTrace.savedTitle, .notReached, "Not tried")
            return finish(.needsPlus, capture, trace)
        }
        trace.add(CaptureTrace.plusTitle, .done, "On")
        if dryRun {
            do {
                let plan = try await decide(capture, in: store)
                trace.steps.append(CaptureTrace.plannedStep(plan, capture: capture, in: store))
            } catch {
                trace.add("Would be saved", .failed, (error as? LocalizedError)?.errorDescription ?? "It couldn't be saved.")
            }
            return finish(nil, capture, trace)
        }
        do {
            let outcome = try await record(capture, in: store, isPlus: true)
            trace.steps.append(CaptureTrace.savedStep(outcome, plan: nil, in: store))
            trace.entryId = outcome.entryId
            if case .joined = outcome { trace.joined = true }
            if case .saved(let id) = outcome, capture.source == .sms, let other = maybeSame(capture, saved: id, in: store) {
                try? store.flagMaybeSame(id, as: other)
                trace.maybeSameAs = other
            }
            return finish(outcome, capture, trace)
        } catch {
            trace.add(CaptureTrace.savedTitle, .failed, (error as? LocalizedError)?.errorDescription ?? "It couldn't be saved. Try again.")
            return finish(.skipped("It couldn't be saved."), capture, trace)
        }
    }
}
