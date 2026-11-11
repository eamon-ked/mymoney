//
//  CaptureService.swift
//  Nokael Money
//
//  Turns a purchase that arrived on its own (an Apple Pay tap, a bank SMS, a
//  sentence to Siri) into an entry. Every route ends here, so they all pick
//  accounts and categories the same way and never save the same purchase
//  twice. Automatic entries are saved straight away and flagged for review.
//
//  `decide` works out what should happen without saving anything; `record`
//  does it. The capture test in Settings shows `decide`'s answer, so what it
//  says is what a real alert would do.
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
        /// Another bank message about a movement already saved from a message: joined into that entry
        case joined(UUID)
        /// The bank gave back an earlier charge, so that charge was removed
        case reversed(UUID)
        case needsPlus
        /// Not saved, with a sentence saying why
        case skipped(String)

        var message: String {
            switch self {
            case .saved: return "Saved."
            case .merged: return "Already recorded."
            case .joined: return "Joined with the bank's earlier message about it."
            case .reversed: return "The earlier charge was reversed, so it was removed."
            case .needsPlus: return "Automatic capture needs Nokael Plus. Open Nokael Money to upgrade."
            case .skipped(let reason): return reason
            }
        }

        /// How it reads in Settings after "From ADCB:" or "On ENBD Visa:"
        var logLine: String {
            switch self {
            case .saved: return "saved"
            case .merged: return "already recorded"
            case .joined: return "joined with the earlier message about it"
            case .reversed: return "reversed an earlier charge"
            case .needsPlus: return "not saved, needs Nokael Plus"
            case .skipped(let reason): return "not saved. \(reason)"
            }
        }

        var entryId: UUID? {
            switch self {
            case .saved(let id), .merged(let id), .joined(let id), .reversed(let id): return id
            case .needsPlus, .skipped: return nil
            }
        }
    }

    /// What the person already told us, e.g. through Siri
    struct Choices {
        var accountId: UUID?
        var categoryId: UUID?
        /// Save it as its own entry even if it looks like one already saved: the person said so
        var separate = false
    }

    /// Which account a capture goes to, and how sure that is
    struct Route: Equatable {
        var accountId: UUID?
        /// Chosen by the person, linked to this card or account number, or the only account there is
        var known: Bool
        /// Shown on the entry when it isn't known: what to check
        var question: String?
        /// The card or account digits that aren't linked yet, to offer "Always use this account"
        var unlinkedHint: String?
    }

    /// What saving a capture would do
    enum Decision: Equatable {
        case duplicate(UUID)
        /// An earlier automatic charge the bank gave back
        case reverse(UUID)
        /// Between two of the person's own accounts; `other` is the account on the far side
        case transfer(other: UUID)
        case save
        case skip(String)
    }

    struct Plan {
        var decision: Decision
        var route: Route
        var category: LedgerAccountRecord?
        var key: UUID
    }

    // MARK: - Recording

    static func record(_ capture: Capture, in store: LedgerStore, isPlus: Bool, choices: Choices = Choices()) async throws -> Outcome {
        if capture.source != .siri && !isPlus { return .needsPlus }
        let plan = try await decide(capture, in: store, choices: choices)
        let snapshot = store.snapshot
        switch plan.decision {
        case .skip(let reason):
            return .skipped(reason)
        case .duplicate(let id):
            if let record = store.entryRecord(id), record.status == .posted,
               record.source == .sms, capture.source == .sms, store.capturedBefore(key: plan.key) == nil {
                try store.joinMessage(id, name: capture.merchant, reference: capture.reference, accountHint: capture.accountHint)
                return .joined(id)
            }
            if let record = store.entryRecord(id), record.status == .posted {
                // Joined only on shop, amount and time, from a different alert: most likely the same purchase,
                // but two real ones look the same, so the entry asks rather than deciding quietly
                let sameReference = capture.reference != nil && capture.reference == record.reference
                let joinedByGuess = record.source != nil && record.source != capture.source && !sameReference
                    && store.capturedBefore(key: plan.key) == nil
                try store.enrichCaptured(id, cardHint: capture.cardHint, from: capture.source, reference: capture.reference)
                if joinedByGuess && record.needsReview {
                    try store.noteReviewReason(id, LedgerStore.joinedAlertsReason)
                }
            }
            return .merged(id)
        case .reverse(let id):
            store.noteReversal(key: plan.key, undid: id)
            try store.void(id, reason: LedgerStore.reversedReason)
            return .reversed(id)
        case .save, .transfer:
            break
        }
        guard let accountId = plan.route.accountId, let account = snapshot.account(accountId), let category = plan.category else {
            return .skipped("Add an account in Nokael Money first.")
        }
        let isIncome = capture.direction == .received
        let memo = capture.merchant.isEmpty ? category.name : capture.merchant
        let entry = isIncome
            ? try EntryFactory.income(capture.amount, to: account.info, category: category.info, date: capture.date, memo: memo, key: plan.key)
            : try EntryFactory.expense(capture.amount, from: account.info, category: category.info, date: capture.date, memo: memo, key: plan.key)
        // Siri entries the person spelled out in full don't need a second look
        // One that looks like an unpaid bill is never linked by itself: it waits for the person to say
        let infos = Dictionary(snapshot.accountRecords.map { ($0.id, $0.info) }, uniquingKeysWith: { a, _ in a })
        let looksLikeBill = BillPayment(entry, accounts: infos).map { !snapshot.billCandidates(for: $0).isEmpty } ?? false
        // A purchase needs no second look when nothing about it was guessed: the card or account number is one
        // the person linked, and the shop's category is the one they confirmed before
        let linked = capture.cardHint.map { store.linkedAccount(forCard: $0) == account.id }
            ?? capture.accountHint.map { store.accountMatching(digits: $0) == account.id } ?? false
        let settled = linked && !capture.isTransfer && !capture.isReversal && reviewReason(capture, plan: plan) == nil
            && confirmedCategory(for: capture.merchant, income: isIncome, snapshot: snapshot) == category.id
        let review = looksLikeBill || (capture.source == .siri ? (choices.accountId == nil || choices.categoryId == nil) : !settled)
        // The card, else the account number, so "Always use this account" can be offered for either
        let hint = capture.cardHint ?? capture.accountHint.map(LedgerStore.accountLinkKey)
        let id = try store.postCaptured(entry, source: capture.source, cardHint: hint, needsReview: review,
                                        reference: capture.reference, reviewReason: reviewReason(capture, plan: plan))

        if case .transfer(let other) = plan.decision {
            // Between your own accounts: one transfer, joined with the other bank's half if that came first
            let hadTwin = store.entryRecord(id).flatMap { store.transferTwin(of: $0, in: other) } != nil
            let transfer = try store.recordAsTransfer(id, other: other)
            return hadTwin ? .merged(transfer) : .saved(transfer)
        }
        // The other bank already told of this move between your accounts
        if let transfer = store.pairOwnTransfer(id) { return .merged(transfer) }
        return .saved(id)
    }

    /// Works out what saving would do, without saving. Only a missing "Other" category may be created.
    static func decide(_ capture: Capture, in store: LedgerStore, choices: Choices = Choices()) async throws -> Plan {
        let snapshot = store.snapshot
        let key = idempotencyKey(capture, calendar: snapshot.calendar)
        let route = self.route(capture, choices: choices, in: store)
        func plan(_ decision: Decision, category: LedgerAccountRecord? = nil) -> Plan {
            Plan(decision: decision, route: route, category: category, key: key)
        }
        guard snapshot.setupComplete else { return plan(.skip("Finish setting up Nokael Money first.")) }
        guard capture.amount.currency == snapshot.currency else {
            return plan(.skip("That was \(MoneyFormat.string(capture.amount)). Add it yourself in \(snapshot.currency) so your balances stay right."))
        }
        guard capture.amount.isPositive, Money.exact(capture.amount.decimal, currency: capture.amount.currency) != nil else {
            return plan(.skip("There was no amount to save."))
        }
        // The same alert or tap again (a retried automation)
        if !choices.separate, let earlier = store.capturedBefore(key: key) { return plan(.duplicate(earlier)) }
        if !choices.separate, capture.isReversal, let undone = store.reversalHandled(key: key) { return plan(.duplicate(undone)) }
        let recent = recentEntries(snapshot, around: capture.date, store: store)
        if !choices.separate, let existing = CaptureMatcher.duplicate(of: capture, in: recent, accountId: route.known ? route.accountId : nil,
                                                   calendar: snapshot.calendar) {
            return plan(.duplicate(existing))
        }
        if capture.isReversal, let original = reversedCharge(capture, route: route, in: store) {
            return plan(.reverse(original))
        }
        guard let accountId = route.accountId, snapshot.account(accountId) != nil else {
            return plan(.skip("Add an account in Nokael Money first."))
        }
        let isIncome = capture.direction == .received
        let category: LedgerAccountRecord
        if let chosen = snapshot.account(choices.categoryId) {
            category = chosen
        } else if capture.isTransfer && !isIncome {
            category = store.peopleCategory
        } else if capture.isTransfer && isIncome && !CategoryRules.saysSalary(capture.merchant) {
            category = store.fromPeopleCategory
        } else {
            category = try await self.category(for: capture.merchant, income: isIncome, snapshot: snapshot, store: store)
        }
        if capture.isTransfer, let hint = capture.otherAccountHint, let other = store.accountMatching(digits: hint),
           other != accountId, let otherAccount = snapshot.account(other), otherAccount.kind.isBalanceSheet, otherAccount.kind != .lent {
            return plan(.transfer(other: other), category: category)
        }
        return plan(.save, category: category)
    }

    /// What the review card asks, when there's something specific to check
    static func reviewReason(_ capture: Capture, plan: Plan) -> String? {
        if let question = plan.route.question { return question }
        if capture.isTransfer, case .save = plan.decision {
            return capture.direction == .spent
                ? "Was this sent to someone, or moved to another of your accounts?"
                : "Was this from someone, or from another of your accounts?"
        }
        if capture.isReversal { return "Money back. If it undoes a purchase, check the purchase too." }
        return nil
    }

    // MARK: - Changing what bank messages did

    /// A message that was joined into an entry, or never saved, becomes an entry of its own.
    /// The new entry is on To check so its account and category get a look.
    @discardableResult
    static func saveOnItsOwn(_ trace: CaptureTrace, in store: LedgerStore) async throws -> UUID {
        guard let read = trace.readDetails(currency: store.currency) else {
            throw StoreError.invalid("This record doesn't say enough about the payment to add it. Add it yourself with +.")
        }
        var capture = read.capture
        capture.text = "on its own \(trace.id)"
        let outcome = try await record(capture, in: store, isPlus: true, choices: Choices(separate: true))
        guard case .saved(let id) = outcome else { throw StoreError.invalid(outcome.message) }
        var changed = trace
        changed.read = changed.read ?? read
        changed.entryId = id
        changed.joined = nil
        changed.maybeSameAs = nil
        changed.add("Added by you", .done, "Saved as its own entry")
        store.updateCaptureTrace(changed)
        return id
    }

    /// Undoes `saveOnItsOwn`: the entry goes and the record says what it said before
    static func undoSaveOnItsOwn(_ entryId: UUID, trace: CaptureTrace, in store: LedgerStore) throws {
        try store.void(entryId, reason: "Undone")
        store.updateCaptureTrace(trace)
    }

    /// "Same payment": the entry flagged as maybe the same goes, and its message counts as joined into the other
    static func confirmSame(_ entryId: UUID, as other: UUID, in store: LedgerStore) throws {
        try store.void(entryId, reason: "The same payment as another bank message")
        try store.markReviewed(other)
        for var trace in store.captureTraces where trace.entryId == entryId {
            trace.entryId = other
            trace.joined = true
            trace.maybeSameAs = nil
            store.updateCaptureTrace(trace)
        }
    }

    /// "Separate payments": both stay, and the question goes
    static func keepSeparate(_ entryId: UUID, in store: LedgerStore) throws {
        try store.markReviewed(entryId)
        for var trace in store.captureTraces where trace.entryId == entryId && trace.maybeSameAs != nil {
            trace.maybeSameAs = nil
            store.updateCaptureTrace(trace)
        }
    }

    // MARK: - Which account

    /// The account a capture belongs to: what the person chose, then a linked Wallet card or card number, then
    /// the account the alert names, then the only account there is. Anything else is a guess, and says so.
    static func route(_ capture: Capture, choices: Choices, in store: LedgerStore) -> Route {
        let snapshot = store.snapshot
        if let chosen = choices.accountId, snapshot.account(chosen) != nil { return Route(accountId: chosen, known: true) }
        if let card = capture.cardHint, let linked = store.linkedAccount(forCard: card) { return Route(accountId: linked, known: true) }
        if let digits = capture.accountHint, let matched = store.accountMatching(digits: digits) {
            return Route(accountId: matched, known: true)
        }
        let candidates = snapshot.accounts.filter { $0.kind.isBalanceSheet && $0.kind != .lent && !$0.archived }
        let spendable = candidates.filter(\.spendable)
        if candidates.count == 1 { return Route(accountId: candidates[0].id, known: true) }
        let fallback = defaultAccount(snapshot)
        if let digits = capture.accountHint {
            return Route(accountId: fallback, known: false, question: "Which of your accounts is ••\(digits)?",
                         unlinkedHint: LedgerStore.accountLinkKey(digits))
        }
        if let card = capture.cardHint {
            let name = card.count == 4 && card.allSatisfy(\.isNumber) ? "card ••\(card)" : card
            return Route(accountId: fallback, known: false, question: "Which account is \(name) on?", unlinkedHint: card)
        }
        guard spendable.count > 1 || candidates.count > 1, capture.source != .siri else {
            return Route(accountId: fallback, known: spendable.count == 1)
        }
        return Route(accountId: fallback, known: false, question: "Check which account this was.")
    }

    static func defaultAccount(_ snapshot: FinanceSnapshot) -> UUID? {
        if let last = snapshot.account(snapshot.settings.lastUsedAccountId), last.spendable, !last.archived { return last.id }
        return snapshot.accounts.first(where: \.spendable)?.id
    }

    /// The automatic charge a reversal gives back: the same amount, on the same card or account, within 60 days,
    /// and still unchecked, so nothing the person already confirmed is removed behind their back
    static func reversedCharge(_ capture: Capture, route: Route, in store: LedgerStore) -> UUID? {
        let snapshot = store.snapshot
        let since = capture.date.addingTimeInterval(-60 * 86_400)
        let words = Set(StatementImport.merchantWords(capture.merchant))
        return snapshot.entryRecords
            .filter { r in
                guard r.status == .posted, r.kind == .expense, r.needsReview, r.source != nil,
                      r.date >= since, r.date <= capture.date,
                      r.lines.contains(where: { $0.minorUnits == -capture.amount.minorUnits && snapshot.account($0.accountId)?.kind.isBalanceSheet == true })
                else { return false }
                if let card = capture.cardHint, let theirs = r.cardHint, card != theirs { return false }
                if route.known, let accountId = route.accountId, !r.lines.contains(where: { $0.accountId == accountId }) { return false }
                return words.isEmpty || !words.isDisjoint(with: StatementImport.merchantWords(r.memo))
            }
            .max { $0.date < $1.date }?.id
    }

    // MARK: - Bank messages

    /// Reads an SMS alert. The rule-based reader goes first and decides on its own what isn't a payment;
    /// Apple Intelligence only helps when the reader found no shop, or couldn't find the amount or direction,
    /// and its amount is only trusted when that number really appears in the message.
    /// `fromBank`: the sender is one of the banks chosen in Settings. Without that, a message must
    /// carry the marks of a bank's alert, so a friend's "I sent you 100" is never saved or shown to the AI.
    static func examine(message: String, store: LedgerStore, date: Date, useAI: Bool = true,
                        fromBank: Bool = false) async -> AlertReading {
        let monthFirst = writesMonthFirst(store.settings.locale)
        let reading = AlertParser.examine(message, homeCurrency: store.currency, date: date, calendar: store.calendar,
                                          monthFirst: monthFirst)
        if case .ignored(let why) = reading, [.oneTimeCode, .declined, .notice, .promotion].contains(why) { return reading }
        if !fromBank, !AlertParser.readsLikeBankAlert(message, homeCurrency: store.currency, arrived: date, calendar: store.calendar) {
            return .ignored(.personal)
        }
        if case .capture(let parsed) = reading, !parsed.merchant.isEmpty { return reading }
        #if canImport(FoundationModels)
        if useAI, #available(iOS 26.0, *), AppleIntelligence.isReady,
           let ai = try? await MoneyAI.readAlert(message, homeCurrency: store.currency, date: date) {
            var ai = ai
            if !believableName(ai.merchant, in: message) { ai.merchant = "" }
            if case .capture(var parsed) = reading {
                parsed.merchant = ai.merchant
                return .capture(parsed)
            }
            return .capture(ai)
        }
        #endif
        return reading
    }

    /// A name the AI found is only kept when it's really in the message and says who or where: not the
    /// bank's short forms ("Cr.", "Dr.", "A/C"), not masked digits ("X" from "XXXX0001"), not two letters
    static func believableName(_ name: String, in message: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.filter(\.isLetter).count >= 3 else { return false }
        let short: Set<String> = ["cr", "dr", "a/c", "ac", "acc", "acct", "txn", "trx", "ref", "avl", "bal", "pos", "atm", "aed", "usd"]
        let words = trimmed.lowercased().split { !$0.isLetter && $0 != "/" }.map(String.init)
        if words.allSatisfy({ short.contains($0) || $0.allSatisfy { $0 == "x" } }) { return false }
        let squash = { (t: String) in t.lowercased().filter { $0.isLetter || $0.isNumber } }
        return squash(message).contains(squash(trimmed))
    }

    static func read(message: String, homeCurrency: String, date: Date) async -> Capture? {
        let parsed = AlertParser.read(message, homeCurrency: homeCurrency, date: date)
        if let parsed, !parsed.merchant.isEmpty { return parsed }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady,
           var ai = try? await MoneyAI.readAlert(message, homeCurrency: homeCurrency, date: date) {
            if !believableName(ai.merchant, in: message) { ai.merchant = "" }
            if var parsed {
                parsed.merchant = ai.merchant
                return parsed
            }
            return ai
        }
        #endif
        return parsed
    }

    /// Whether this phone writes 03/11 meaning 11 March (as in the United States)
    static func writesMonthFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale) ?? "d/M"
        guard let m = format.firstIndex(of: "M"), let d = format.firstIndex(of: "d") else { return false }
        return m < d
    }

    /// Whether a message from this sender should be read at all
    /// The sender as passed in, or nil when it's really the message itself: an automation wired with
    /// the message (or the whole input) as Sender. A sender is a short name or number, never a sentence.
    static func realSender(_ sender: String?, message: String) -> String? {
        guard let s = sender?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = s.split(whereSeparator: \.isWhitespace).count
        if s == text || s.count > 40 || words > 4 { return nil }
        if words > 2, text.localizedCaseInsensitiveContains(s) || s.localizedCaseInsensitiveContains(text) { return nil }
        return s
    }

    static func accepts(sender: String?, settings: SettingsRecord) -> Bool {
        guard !settings.bankSenders.isEmpty, let sender, !sender.isEmpty else { return true }
        return BankSenders.matches(sender, any: settings.bankSenders)
    }

    // MARK: - Choosing

    /// Last time's category for this shop, then well-known shops, then Apple Intelligence, then "Other"
    /// What the person has confirmed before: each checked entry's description and category
    static func confirmedHistory(income: Bool, snapshot: FinanceSnapshot) -> [(memo: String, categoryId: UUID)] {
        let kind: AccountKind = income ? .income : .expense
        return snapshot.entryRecords.compactMap { record in
            guard record.status == .posted, !record.needsReview,
                  let line = record.lines.first(where: { snapshot.account($0.accountId)?.kind == kind }) else { return nil }
            return (record.memo, line.accountId)
        }
    }

    /// The category the person already confirmed for this shop, if they have
    static func confirmedCategory(for merchant: String, income: Bool, snapshot: FinanceSnapshot) -> UUID? {
        guard !merchant.isEmpty else { return nil }
        let history = confirmedHistory(income: income, snapshot: snapshot)
        guard let id = StatementImport.category(for: merchant, history: history), let found = snapshot.account(id),
              CategoryRules.historyFits(categoryName: found.name, description: merchant, income: income) else { return nil }
        return id
    }

    static func category(for merchant: String, income: Bool, snapshot: FinanceSnapshot, store: LedgerStore) async throws -> LedgerAccountRecord {
        let options = income ? snapshot.incomeCategories : snapshot.expenseCategories
        let kind: AccountKind = income ? .income : .expense
        let history = confirmedHistory(income: income, snapshot: snapshot)
        if let id = confirmedCategory(for: merchant, income: income, snapshot: snapshot), let found = snapshot.account(id) {
            return found
        }
        if let name = CategoryRules.guess(merchant, income: income, categories: options.map(\.name)),
           let found = options.first(where: { $0.name == name }) {
            return found
        }
        // Money from family or friends isn't pay or earnings
        if income, CategoryRules.isFromPeople(merchant) {
            let people = store.fromPeopleCategory
            try? store.commit()
            return people
        }
        // A loan instalment, when there's no loan account for it to pay
        if !income, CategoryRules.isLoanPayment(merchant) {
            let loans = store.loanCategory
            try? store.commit()
            return loans
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
            // Only pay is salary: money from friends or a payment app isn't, whatever the guess
            if let name = try? await MoneyAI.category(for: merchant, options: options.map(\.name), examples: examples),
               !(income && CategoryRules.isSalaryCategory(name) && !CategoryRules.saysSalary(merchant)),
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
    static func recentEntries(_ snapshot: FinanceSnapshot, around date: Date, store: LedgerStore? = nil) -> [CapturedEntry] {
        // What each bank message that made or joined an entry looked like, so a later one can be told apart
        var marks: [UUID: [CapturedEntry.MessageMark]] = [:]
        if let store {
            for trace in store.captureTraces where abs(trace.date.timeIntervalSince(date)) < 36 * 3600 {
                guard let read = trace.read, let id = trace.entryId.flatMap(store.currentEntryId(from:)) else { continue }
                marks[id, default: []].append(read.mark)
            }
        }
        return snapshot.entryRecords.flatMap { record -> [CapturedEntry] in
            guard record.status == .posted, abs(record.date.timeIntervalSince(date)) < 36 * 3600 else { return [] }
            let directions: [Capture.Direction]
            switch record.kind {
            case .expense: directions = [.spent]
            case .income: directions = [.received]
            // Money between your own accounts: the bank tells of it going out of one and into the other
            case .transfer: directions = [.spent, .received]
            default: return []
            }
            let moved = record.lines.filter { $0.minorUnits > 0 }.reduce(Int64(0)) { $0 + $1.minorUnits }
            // A transfer sits in two of your accounts, so either side's alert can be it
            let owned = record.lines.filter { snapshot.account($0.accountId)?.kind.isBalanceSheet == true }
            // An entry saved with no name carries its category's ("Sent to people"): that isn't a name
            let named = record.lines.contains { snapshot.account($0.accountId)?.name == record.memo } ? "" : record.memo
            let isTransfer = record.kind == .transfer || record.lines.contains {
                ["people", "fromPeople"].contains(snapshot.account($0.accountId)?.systemRole ?? "")
            }
            let own = owned.count == 1 ? owned[0].accountId : nil
            return directions.map { direction in
                CapturedEntry(id: record.id, date: record.date, amount: Money(minorUnits: moved, currency: snapshot.currency),
                              direction: direction, memo: named, source: record.source, reference: record.reference,
                              alsoFrom: record.alsoFromRaw.flatMap(Capture.Source.init(rawValue:)), accountId: own,
                              messages: marks[record.id] ?? [], isTransfer: isTransfer)
            }
        }
    }

    /// The same message or tap run twice gives the same key, so it saves once. A bank message is the same
    /// message when its words and the date it gives match; one with no date only within the day it arrived,
    /// so the identical "AED 30 at Talabat" tomorrow is a new purchase.
    static func idempotencyKey(_ capture: Capture, calendar: Calendar = .current) -> UUID {
        let minute = Int(capture.date.timeIntervalSince1970 / 60)
        let when: String
        if capture.source == .sms {
            if capture.dateFromMessage {
                when = String(minute)
            } else {
                let day = calendar.dateComponents([.year, .month, .day], from: capture.date)
                when = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            }
        } else {
            when = String(minute)
        }
        // A bank message's own words identify it: the name read from it can differ between runs
        // when Apple Intelligence reads it, so it's left out
        let merchant = capture.source == .sms && !capture.text.isEmpty ? "" : capture.merchant
        let text = [capture.source.rawValue, capture.text, merchant, capture.cardHint ?? "",
                    String(capture.amount.minorUnits), when].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // name-based UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
