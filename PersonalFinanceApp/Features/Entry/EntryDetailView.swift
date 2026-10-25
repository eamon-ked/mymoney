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
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

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

                if !record.notes.isEmpty {
                    Section("Notes") { Text(record.notes) }
                }

                if let occId = record.occurrenceId, let occ = snapshot.occurrences.first(where: { $0.id == occId }),
                   let item = snapshot.item(for: occ) {
                    Section("Linked to") {
                        LabeledContent(item.name, value: occ.dueDate.formatted(date: .abbreviated, time: .omitted))
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
                if record.status == .posted && editable {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
                }
            }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
                EntryEditor(kind: addKind, editing: record)
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
