//
//  PaydaySheet.swift
//  Nokael Money
//
//  Payday in one screen: the salary from Plan already filled in, and the
//  month's routine as switches that are on by default. One tap does it all.
//

import SwiftUI
import NokaelCore

struct PaydaySheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// An amount the person said, which beats the planned one
    var said: Money? = nil

    @State private var plan: PaydayPlan?
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = Date()
    @State private var choices = PaydayPlan.Choices()
    @State private var key = UUID()
    @State private var done: [String]?
    @State private var error: String?
    @State private var addingOther = false

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    finished(done)
                } else if let plan {
                    if let when = plan.alreadyReceived, said == nil {
                        alreadyDone(when)
                    } else {
                        form(plan)
                    }
                }
            }
            .navigationTitle("Payday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if done == nil { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if done != nil {
                        Button("Done") { dismiss() }
                    } else if plan?.alreadyReceived == nil || said != nil {
                        Button("Do it", action: run).bold()
                    }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $addingOther) { EntryEditor(kind: .income) }
        }
    }

    // MARK: - Sections

    @ViewBuilder private func form(_ plan: PaydayPlan) -> some View {
        Section {
            HStack {
                Text(store.currency).foregroundStyle(.secondary)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.bold())
            }
            AccountPicker(title: "Paid into", accounts: snapshot.accounts.filter(\.spendable), selection: $accountId)
            DatePicker("Received", selection: $date, in: ...Date(), displayedComponents: .date)
        } header: {
            Text("Your salary")
        } footer: {
            if let item = plan.item {
                Text("From your plan: \(item.name), \(MoneyFormat.string(item.amount)). Change the amount if this month's was different.")
            } else {
                Text("There's no salary in your plan yet.")
            }
        }

        if plan.item == nil {
            Section {
                Toggle("Remember it as my monthly salary", isOn: $choices.remember)
            } footer: {
                Text("Next month Nokael expects it, and payday is one tap.")
            }
        }

        if plan.budgetFrom != nil || !plan.goals.isEmpty {
            Section {
                if plan.budgetFrom != nil {
                    Toggle(isOn: $choices.copyBudget) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan this month's budget")
                            Text("Same as last month: \(plan.budgetTotal.compact) across \(plan.budgetCount) categories")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(plan.goals) { goal in
                    Toggle(isOn: Binding(get: { choices.goals.contains(goal.id) },
                                         set: { on in if on { choices.goals.insert(goal.id) } else { choices.goals.remove(goal.id) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Put \(goal.amount.compact) into \(goal.name)")
                            if let by = goal.by {
                                Text("To reach it by \(by.formatted(.dateTime.month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Then, for this month")
            }
        }

        if plan.billsBeforeNext.isPositive {
            Section {
                LabeledContent("Bills before next payday", value: plan.billsBeforeNext.compact)
            } footer: {
                Text(plan.nextPayday.map { "Until \($0.formatted(.dateTime.day().month(.wide))). They're already kept aside in Safe to spend." }
                     ?? "They're already kept aside in Safe to spend.")
            }
        }

        if let error { Section { FieldError(message: error) } }
    }

    @ViewBuilder private func alreadyDone(_ when: Date) -> some View {
        Section {
            Label("This month's salary was recorded on \(when.formatted(.dateTime.day().month(.wide))).",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Add other income") { addingOther = true }
        }
    }

    @ViewBuilder private func finished(_ lines: [String]) -> some View {
        Section {
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
            }
        } header: {
            Text("Done")
        } footer: {
            let sts = snapshot.safeToSpend()
            if let amount = sts.amount, snapshot.setupComplete {
                Text("Safe to spend is now \(amount.compact) until \(sts.periodEnd.formatted(.dateTime.day().month(.wide))).")
            }
        }
    }

    // MARK: -

    private func load() {
        guard plan == nil else { return }
        let made = PaydayPlan.make(snapshot, said: said)
        plan = made
        amountText = MoneyFormat.editable(made.amount, emptyWhenZero: true)
        accountId = made.accountId
        choices.goals = Set(made.goals.map(\.id))
        choices.copyBudget = made.budgetFrom != nil
    }

    private func run() {
        guard var plan else { return }
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency) else { error = "Enter the salary you received."; return }
        plan.amount = amount
        plan.accountId = accountId
        do {
            done = try plan.run(store, choices: choices, date: date, key: key)
            error = nil
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }
}
