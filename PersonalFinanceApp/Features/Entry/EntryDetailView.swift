//
//  EntryDetailView.swift
//  Nokael Money
//
//  One entry in full: what moved where, its status, the bill it paid, and
//  every change made to it.
//

import SwiftUI
import NokaelCore

struct EntryDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: EntryRecord
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var openBill: Occurrence?
    @State private var payingDebt: LedgerAccountRecord?
    @State private var namingPerson = false
    @State private var personName = ""

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.memo.isEmpty ? kindName : record.memo).font(.title3.bold())
                        Text(record.date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                        HStack {
                            StatusBadge(text: record.status == .void ? "Deleted" : "Posted",
                                        color: record.status == .void ? .red : .green)
                            if record.cleared == .reconciled { StatusBadge(text: "Reconciled") }
                            StatusBadge(text: kindName)
                            if let source = record.source { StatusBadge(text: source.title, color: .blue) }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                if record.status == .posted, let parts = store.debtPaymentParts(record) {
                    debtSplit(parts)
                } else {
                Section("What moved") {
                    ForEach(Array(record.entry.lines.enumerated()), id: \.offset) { _, line in
                        if let account = snapshot.account(line.accountId), !account.isSystem {
                            LabeledContent {
                                Text(effect(line, account)).monospacedDigit()
                            } label: {
                                Label(account.name, systemImage: account.icon.isEmpty ? AccountStyle.icon(for: account.kind) : account.icon)
                            }
                        }
                    }
                }
                }

                if record.needsReview && record.status == .posted {
                    reviewSection
                }

                if !record.notes.isEmpty {
                    Section("Notes") { Text(record.notes) }
                }

                if !debtsItCouldPay.isEmpty {
                    Section {
                        Menu {
                            ForEach(debtsItCouldPay, id: \.id) { debt in
                                Button(debt.name) { payingDebt = debt }
                            }
                        } label: {
                            Label("This was a loan or card payment", systemImage: "creditcard")
                        }
                        .accessibilityIdentifier("wasDebtPayment")
                    } footer: {
                        Text("Records it as a payment instead, so it lowers what you owe rather than counting as spending.")
                    }
                }

                if canBeLending {
                    Section {
                        Menu {
                            ForEach(people, id: \.id) { person in
                                Button(person.name) { recordAsLending(person) }
                            }
                            Button("Someone new…") { personName = ""; namingPerson = true }
                        } label: {
                            Label(record.kind == .expense ? "I lent this to someone" : "This was money paid back to me",
                                  systemImage: "person.crop.circle.badge.clock")
                        }
                        .accessibilityIdentifier("wasLending")
                    } footer: {
                        Text(record.kind == .expense
                             ? "Records it as money they owe you, so it isn't counted as spending."
                             : "Records it as a repayment, so it lowers what they owe you instead of counting as income.")
                    }
                }

                if let occId = record.occurrenceId, let occ = snapshot.occurrences.first(where: { $0.id == occId }),
                   let item = snapshot.item(for: occ) {
                    Section {
                        Button { openBill = occ } label: {
                            LabeledContent(item.name, value: occ.dueDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        Button("Unlink from \(item.name)") { try? store.unlink(entryId: record.id) }
                    } header: {
                        Text("Pays this bill")
                    } footer: {
                        Text("Unlinking reopens the bill. This transaction and your balance stay as they are.")
                    }
                }

                Section("History") {
                    ForEach(history, id: \.id) { audit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audit.summary).font(.subheadline)
                            if let reason = audit.reason { Text("Reason: \(reason)").font(.caption).foregroundStyle(.secondary) }
                            Text(audit.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Added", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let error { Section { FieldError(message: error) } }

                if record.status == .posted && (editable || record.kind == .debtPayment) {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(kindName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if record.status == .posted && (editable || correctable != nil) {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
                }
            }
            .alert("Who did you lend it to?", isPresented: $namingPerson) {
                TextField("Name", text: $personName).accessibilityIdentifier("personName")
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    do { recordAsLending(try store.lentAccount(named: personName)) }
                    catch { self.error = StoreError.from(error).errorDescription }
                }
            }
            .sheet(item: $openBill) { PayScheduledSheet(occurrence: $0) }
            .sheet(item: $payingDebt, onDismiss: { if record.status == .void { dismiss() } }) {
                PayDebtSheet(debt: $0, replacing: record)
            }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
                switch correctable {
                case .payment(let debt): PayDebtSheet(debt: debt, editing: record)
                case .opening(let account): StartingAmountSheet(account: account)
                case nil: EntryEditor(kind: addKind, editing: record)
                }
            }
            .confirmationDialog("Delete this \(kindName.lowercased())?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try store.void(record.id); dismiss() } catch { self.error = StoreError.from(error).errorDescription }
                }
            } message: {
                Text("Balances, budget and safe-to-spend update straight away. A record of it stays in the history.")
            }
        }
    }

    /// A card or loan payment in plain words: what was paid, what came off the debt, what was interest
    private func debtSplit(_ parts: LedgerStore.DebtPaymentParts) -> some View {
        let rate = parts.debt.debtTerms?.rateText
        return Section {
            LabeledContent("You paid", value: parts.total.formatted)
            LabeledContent("From", value: parts.funding.name)
            LabeledContent("Came off \(parts.debt.name)", value: parts.principal.formatted).bold()
            if parts.interest.isPositive { LabeledContent("Interest", value: parts.interest.formatted) }
            if parts.fees.isPositive { LabeledContent("Fees", value: parts.fees.formatted) }
            LabeledContent("You owe now", value: snapshot.owed(parts.debt.id).formatted)
        } header: {
            Text("How this payment was split")
        } footer: {
            Text(parts.interest.isPositive
                 ? "Part of every payment is the lender's interest, which counts as spending; the rest lowers what you owe. The interest here is one month at \(rate ?? "the loan's rate") on what you owed. If your bank's statement shows a different interest figure, tap Edit."
                 : "All of it lowered what you owe. If your bank charged interest on this payment, tap Edit and enter it.")
        }
    }

    /// An automatic entry: confirm it, or teach Nokael which account a new card is
    @ViewBuilder private var reviewSection: some View {
        let account = record.lines.compactMap { snapshot.account($0.accountId) }.first { $0.kind.isBalanceSheet }
        Section {
            Button {
                do { try store.markReviewed(record.id); dismiss() } catch { self.error = StoreError.from(error).errorDescription }
            } label: {
                Label("Looks right", systemImage: "checkmark.circle.fill")
            }
            if let hint = record.cardHint, let account, store.linkedAccount(forCard: hint) != account.id {
                Button {
                    do {
                        try store.linkCard(hint, to: account.id)
                        try store.markReviewed(record.id)
                        dismiss()
                    } catch { self.error = StoreError.from(error).errorDescription }
                } label: {
                    Label("Always use \(account.name) for \(cardName(hint))", systemImage: "creditcard")
                }
            }
        } header: {
            Text("Check this entry")
        } footer: {
            Text("Saved automatically\(record.source.map { " from \($0.title)" } ?? ""). If the category or account is wrong, tap Edit.")
        }
    }

    private func cardName(_ hint: String) -> String {
        hint.count == 4 && hint.allSatisfy(\.isNumber) ? "card ending \(hint)" : hint
    }

    private enum Correction { case payment(LedgerAccountRecord), opening(LedgerAccountRecord) }

    /// Entries with their own editor: a card or loan payment, and the amount an account was added with
    private var correctable: Correction? {
        switch record.kind {
        case .debtPayment: return store.debtPaymentParts(record).map { .payment($0.debt) }
        case .openingBalance:
            return record.lines.compactMap { store.account($0.accountId) }.first { $0.kind.isBalanceSheet }.map { .opening($0) }
        default: return nil
        }
    }

    /// An expense paid from a bank or cash account could have been a card or loan payment
    private var debtsItCouldPay: [LedgerAccountRecord] {
        guard record.status == .posted, record.kind == .expense,
              record.lines.contains(where: { store.account($0.accountId)?.kind.isAsset == true }) else { return [] }
        return snapshot.accounts.filter(\.kind.isLiability)
    }

    /// Spending or income through one of your own accounts could really be money lent or paid back
    private var canBeLending: Bool {
        record.status == .posted && (record.kind == .expense || (record.kind == .income && !people.isEmpty))
            && record.lines.contains { store.account($0.accountId).map { $0.kind.isBalanceSheet && $0.kind != .lent } ?? false }
    }

    private var people: [LedgerAccountRecord] {
        snapshot.accounts.filter { $0.kind == .lent && !$0.archived && (record.kind == .expense || snapshot.balance($0.id).isPositive) }
    }

    private func recordAsLending(_ person: LedgerAccountRecord) {
        do {
            try store.recordAsLending(record.id, person: person.id)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }

    private var editable: Bool {
        [.expense, .income, .transfer, .adjustment].contains(record.kind)
    }

    private var addKind: AddKind {
        switch record.kind {
        case .income: return .income
        case .transfer: return .transfer
        case .adjustment: return .adjustment
        default: return .expense
        }
    }

    private var kindName: String {
        switch record.kind {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        case .adjustment: return "Adjustment"
        case .reconciliation: return "Reconciliation"
        case .openingBalance: return "Opening balance"
        case .debtPayment: return "Debt payment"
        }
    }

    private func effect(_ line: Line, _ account: LedgerAccountRecord) -> String {
        if account.kind.isBalanceSheet { return line.amount.signed }
        // Categories: show what was spent or received, without ledger signs
        return line.amount.magnitude.compact
    }

    private var history: [AuditRecord] {
        let ids = Set([record.id, record.replacesId].compactMap { $0 })
        return store.auditTrail.filter { ids.contains($0.subjectId) }
    }
}
