//
//  SafeToSpendView.swift
//  Nokael Money
//
//  Where safe-to-spend comes from, line by line, with a period you can change,
//  a buffer you can adjust with a live preview, and a projection that is
//  always labelled as one.
//

import SwiftUI
import NokaelCore

struct SafeToSpendView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var period: Period = .automatic
    @State private var customEnd = Date()
    @State private var bufferText = ""
    @State private var addingReserve = false

    enum Period: String, CaseIterable, Identifiable {
        case automatic = "Until payday", week = "7 days", month = "Month end", custom = "Pick a date"
        var id: String { rawValue }
    }

    private var snapshot: FinanceSnapshot { store.snapshot }

    private var periodEnd: Date {
        let s = snapshot
        switch period {
        case .automatic: return s.defaultPeriodEnd
        case .week: return s.endOfDay(s.calendar.date(byAdding: .day, value: 6, to: s.today) ?? s.today)
        case .month: return (BudgetMonth.end(of: s.monthKey, calendar: s.calendar) ?? s.today).addingTimeInterval(-1)
        case .custom: return s.endOfDay(max(customEnd, s.today))
        }
    }

    /// Buffer being edited, previewed before it's saved
    private var previewBuffer: Money {
        MoneyFormat.parse(bufferText.isEmpty ? "0" : bufferText, currency: store.currency) ?? snapshot.settings.buffer
    }

    var body: some View {
        NavigationStack {
            let calc = SafeToSpendCalculator(ledger: snapshot.ledger, items: snapshot.items, occurrences: snapshot.occurrences,
                                             reserves: snapshot.reserves, categoryReservations: snapshot.categoryReservations,
                                             buffer: previewBuffer, lastConfirmed: snapshot.lastConfirmed,
                                             staleAfterDays: snapshot.settings.staleAfterDays, calendar: snapshot.calendar)
            let result = calc.calculate(today: snapshot.today, periodEnd: periodEnd)
            List {
                Section {
                    Picker("Through", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if period == .custom {
                        DatePicker("Date", selection: $customEnd, in: snapshot.today..., displayedComponents: .date)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if let amount = result.amount {
                            Text(amount.isNegative ? Money.zero(store.currency).formatted : amount.formatted)
                                .font(.largeTitle.bold()).monospacedDigit()
                            Text("Safe to spend through \(result.periodEnd.formatted(date: .long, time: .omitted))")
                                .foregroundStyle(.secondary)
                            statusBadges(result)
                        } else {
                            Text("Finish setup to calculate").font(.title3.bold())
                            Text("Add at least one cash or bank account with its balance.").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Money in your spendable accounts, minus what's already committed. Expected income isn't counted until it arrives.")
                }

                if result.amount != nil {
                    breakdown(result)
                    bufferSection
                    projectionSection(calc)
                }
            }
            .navigationTitle("Safe to spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveBuffer(); dismiss() } } }
            .onAppear { bufferText = MoneyFormat.editable(snapshot.settings.buffer, emptyWhenZero: true) }
            .sheet(isPresented: $addingReserve) { ReserveEditor() }
        }
    }

    @ViewBuilder private func statusBadges(_ result: SafeToSpend) -> some View {
        HStack {
            ForEach(Array(result.statuses.enumerated()), id: \.offset) { _, status in
                switch status {
                case .reliable: StatusBadge(text: "Reliable", color: .green)
                case .estimated: StatusBadge(text: "Includes estimates", color: .orange)
                case .stale: StatusBadge(text: "Some balances out of date", color: .orange)
                case .shortfall: StatusBadge(text: "Commitments exceed spendable money", color: .red)
                case .incompleteSetup: StatusBadge(text: "Setup incomplete")
                }
            }
        }
    }

    @ViewBuilder private func breakdown(_ result: SafeToSpend) -> some View {
        Section {
            ForEach(result.spendable) { item in
                LabeledContent(item.label, value: item.amount.compact)
            }
            LabeledContent { Text(result.spendableTotal.compact).bold() } label: { Text("Spendable money").bold() }
        } header: {
            Text("Starting point")
        } footer: {
            if case .stale(let names)? = result.statuses.first(where: { if case .stale = $0 { return true }; return false }) {
                Text("\(names.joined(separator: ", ")) hasn't been updated recently, so this may not match your bank.")
            } else {
                Text("Recorded balances of accounts marked as money you can spend.")
            }
        }

        Section {
            if result.obligations.isEmpty { Text("No unpaid bills in this period").foregroundStyle(.secondary) }
            ForEach(result.obligations) { item in
                LabeledContent {
                    Text("−" + item.amount.compact).monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.label)
                        if let d = item.detail { Text(d).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        } header: {
            Text("Bills & commitments · −\(result.obligationsTotal.compact)")
        } footer: {
            Text("Unpaid bills due by the end of the period, including overdue ones. A bill already paid has reduced your balance and isn't subtracted again.")
        }

        Section {
            if result.reserves.isEmpty { Text("Nothing set aside").foregroundStyle(.secondary) }
            ForEach(result.reserves) { item in
                LabeledContent(item.label, value: "−" + item.amount.compact)
            }
            Button { addingReserve = true } label: { Label("Set money aside", systemImage: "lock") }
        } header: {
            Text("Protected savings · −\(result.reservesTotal.compact)")
        } footer: {
            Text("Money you've set aside stays in its account but isn't free to spend.")
        }

        if !result.categoryReservations.isEmpty {
            Section("Budget kept for essentials · −\(result.categoryReservationsTotal.compact)") {
                ForEach(result.categoryReservations) { item in
                    LabeledContent(item.label, value: "−" + item.amount.compact)
                }
            }
        }
    }

    private var bufferSection: some View {
        Section {
            HStack {
                Text("Safety buffer")
                Spacer()
                Text(store.currency).foregroundStyle(.secondary)
                TextField("0", text: $bufferText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
        } footer: {
            Text("A cushion kept back for surprises. The number above updates as you type.")
        }
    }

    @ViewBuilder private func projectionSection(_ calc: SafeToSpendCalculator) -> some View {
        let projection = calc.project(today: snapshot.today, to: periodEnd)
        if !projection.expectedIncome.isEmpty {
            Section {
                LabeledContent("Projected, if income arrives", value: projection.amount.compact)
                ForEach(projection.expectedIncome) { item in
                    LabeledContent(item.label, value: "+" + item.amount.compact)
                }
            } header: {
                Text("Projection · not money you have yet")
            } footer: {
                Text("Assumes: " + projection.assumptions.joined(separator: "; ") + ".")
            }
        }
    }

    private func saveBuffer() {
        guard let value = MoneyFormat.parse(bufferText.isEmpty ? "0" : bufferText, currency: store.currency), !value.isNegative,
              value != snapshot.settings.buffer else { return }
        try? store.updateSettings { $0.bufferMinor = value.minorUnits }
    }
}

struct ReserveEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editing: Reserve? = nil

    @State private var name = ""
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it's for (e.g. Emergency fund)", text: $name)
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    }
                    AccountPicker(title: "Kept in", accounts: store.snapshot.accounts.filter { $0.kind.isAsset }, selection: $accountId)
                } footer: {
                    Text("Nothing moves: the money stays in the account and is just kept out of safe-to-spend.")
                }
                if let error { Section { FieldError(message: error) } }
                if let editing {
                    Section {
                        Button("Release this money", role: .destructive) {
                            try? store.releaseReserve(editing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Set money aside" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    amountText = MoneyFormat.editable(editing.amount)
                    accountId = editing.accountId
                } else {
                    accountId = store.snapshot.accounts.first { $0.spendable }?.id
                }
            }
        }
    }

    private func save() {
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency) else { error = "Enter an amount."; return }
        guard let accountId else { error = "Choose the account it's kept in."; return }
        let snapshot = store.snapshot
        // Two reserves can't claim the same money without saying so
        let others = snapshot.reserves.filter { $0.accountId == accountId && $0.id != editing?.id }.map(\.amount).sum(store.currency)
        let balance = snapshot.balance(accountId)
        if (others + amount) > balance {
            error = "That's more than \(snapshot.account(accountId)?.name ?? "the account") holds after other money set aside (\((balance - others).compact) free)."
            return
        }
        do {
            try store.saveReserve(Reserve(id: editing?.id ?? UUID(), name: name, amount: amount, accountId: accountId))
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
