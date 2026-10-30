//
//  OnboardingView.swift
//  Nokael Money
//
//  Five short, resumable steps to a first useful overview, ending with what's
//  actually free to spend. Progress is saved after each step; income, bills and
//  essentials can be skipped; nothing is invented.
//

import SwiftUI
import NokaelCore

struct OnboardingView: View {
    @Environment(LedgerStore.self) private var store
    @State private var step = 0

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: WelcomeStep(next: { go(1) })
                case 1: CurrencyStep(next: { go(2) })
                case 2: FirstAccountStep(next: { go(3) })
                case 3: IncomeStep(next: { go(4) })
                case 4: BillsStep(next: { go(5) })
                default: EssentialsStep(finish: finish)
                }
            }
            // The app's own colours from the very first screen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .canvas()
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { go(step - 1) } label: { Label("Back", systemImage: "chevron.left") }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Step \(step) of 5").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { step = store.settings.onboardingStep }
    }

    /// Saves where the person is, so relaunching resumes here
    private func go(_ s: Int) {
        withAnimation { step = s }
        try? store.updateSettings { $0.onboardingStep = s }
    }

    private func finish() {
        try? store.updateSettings { $0.onboardingDone = true; $0.onboardingStep = 5 }
    }
}

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var restoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("NOKAEL MONEY").font(.caption.weight(.bold)).foregroundStyle(Palette.home).tracking(2)
            Text("Let's make sense of your money.").font(.largeTitle.bold())
            Text("A clearer view of what you have, what you owe, and what you can spend.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Label("See all your accounts in one place", systemImage: "building.columns.fill")
                Label("Plan bills and spending", systemImage: "calendar")
                Label("Build savings and reduce debt", systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.body.weight(.medium))
            .padding(.top, 8)
            Spacer()
            Button(action: next) {
                Text("Get started").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("getStarted")
            Button("Restore from a backup") { restoring = true }
                .frame(maxWidth: .infinity)
            Text("Everything stays on this iPhone for now.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(24)
        .restoreFromBackup(isPresented: $restoring)
    }
}

private struct CurrencyStep: View {
    @Environment(LedgerStore.self) private var store
    let next: () -> Void
    @State private var currency = CurrencyStep.phoneCurrency
    @State private var starters = true

    static var phoneCurrency: String { Locale.current.currency?.identifier ?? "USD" }

    /// The phone's own currency first, then common ones; every other code is listed below them
    private var suggested: [String] {
        var list = [Self.phoneCurrency]
        for code in ["USD", "EUR", "GBP", "INR", "AED", "SAR", "CAD", "AUD", "PKR", "PHP", "NGN", "BRL"] where !list.contains(code) { list.append(code) }
        if !list.contains(currency) { list.insert(currency, at: 1) }
        return list
    }

    private var others: [String] {
        let shown = Set(suggested)
        return Locale.commonISOCurrencyCodes.filter { !shown.contains($0) }
            .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    private func name(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    var body: some View {
        Form {
            Section {
                Text("Your currency").font(.title2.bold())
                Text("Amounts are shown and stored in this currency.").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            Section {
                Picker("Currency", selection: $currency) {
                    Section {
                        ForEach(suggested, id: \.self) { code in Text("\(code) · \(name(code))").tag(code) }
                    }
                    Section("All currencies") {
                        ForEach(others, id: \.self) { code in Text("\(code) · \(name(code))").tag(code) }
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section {
                Toggle("Start with common categories", isOn: $starters)
            } footer: {
                Text("Groceries, rent, transport and a few more. You can rename or remove any of them. No amounts are added.")
            }
            Section {
                Button("Continue") {
                    try? store.updateSettings { $0.currency = currency; $0.localeIdentifier = Locale.current.identifier }
                    if starters { try? store.addStarterCategories() }
                    next()
                }
                .bold()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("continue")
            }
        }
        // Until this step has been saved, the stored currency is only the record's default
        .onAppear { if store.settings.onboardingStep > 1 { currency = store.settings.currency } }
    }
}

private struct FirstAccountStep: View {
    @Environment(LedgerStore.self) private var store
    let next: () -> Void
    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var institution = ""
    @State private var balanceText = ""
    @State private var balanceDate = Date()
    @State private var error: String?

    var body: some View {
        let accounts = store.snapshot.accounts
        Form {
            Section {
                Text("Add an account").font(.title2.bold())
                Text("Start with the account you use most. You can add the rest any time.").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            if !accounts.isEmpty {
                Section("Added") {
                    ForEach(accounts, id: \.id) { a in
                        LabeledContent(a.name, value: store.snapshot.balance(a.id).compact)
                    }
                }
            }

            AccountFormFields(name: $name, kind: $kind, institution: $institution, balanceText: $balanceText,
                              balanceDate: $balanceDate, kinds: [.bank, .cash, .savings, .creditCard, .loan, .investment],
                              currency: store.currency)

            if let error { Section { FieldError(message: error) } }

            Section {
                Button(accounts.isEmpty ? "Add account and continue" : "Add this account too", action: add)
                    .bold().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("addAccount")
                if !accounts.isEmpty {
                    Button("Continue", action: next).frame(maxWidth: .infinity).accessibilityIdentifier("continue")
                }
            }
        }
    }

    private func add() {
        error = nil
        let entered = balanceText.isEmpty ? Money.zero(store.currency) : MoneyFormat.parse(balanceText, currency: store.currency)
        guard let entered else { error = "Enter the balance as a number."; return }
        let wasEmpty = store.snapshot.accounts.isEmpty
        do {
            try store.addAccount(name: name, kind: kind, balance: entered, openingDate: balanceDate,
                                 institution: institution.isEmpty ? nil : institution, colorHex: AccountColors.next(for: kind))
            name = ""; institution = ""; balanceText = ""
            if wasEmpty { next() }
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

private struct IncomeStep: View {
    @Environment(LedgerStore.self) private var store
    let next: () -> Void
    @State private var amountText = ""
    @State private var frequency: Frequency = .monthly(every: 1)
    @State private var nextDate = Date()
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Your pay").font(.title2.bold())
                Text("Helps plan until your next payday. It's never counted as money you have until it arrives.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            Section {
                HStack {
                    Text(store.currency).foregroundStyle(.secondary)
                    TextField("Usual amount", text: $amountText).keyboardType(.decimalPad)
                }
                FrequencyPicker(frequency: $frequency)
                DatePicker("Next payday", selection: $nextDate, in: Date()..., displayedComponents: .date)
            }
            if let error { Section { FieldError(message: error) } }
            Section {
                Button("Save and continue", action: save).bold().frame(maxWidth: .infinity)
                Button("Skip for now", action: next).frame(maxWidth: .infinity).accessibilityIdentifier("skip")
            }
        }
    }

    private func save() {
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency) else {
            error = "Enter your usual pay, or skip."
            return
        }
        do {
            try store.setUpSalary(amount, every: frequency, nextPayday: nextDate)
            next()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

private struct BillsStep: View {
    @Environment(LedgerStore.self) private var store
    let next: () -> Void
    @State private var addingBill = false
    @State private var addingReserve = false

    var body: some View {
        let snapshot = store.snapshot
        Form {
            Section {
                Text("Bills and savings").font(.title2.bold())
                Text("Add rent, loan payments or money you keep aside, so safe-to-spend can account for them. You can do this later in Plan.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(snapshot.items.filter { $0.direction == .outflow }) { PlannedItemRow(item: $0, snapshot: snapshot) }
                Button { addingBill = true } label: { Label("Add a bill", systemImage: "calendar.badge.plus") }
            }
            Section {
                ForEach(snapshot.reserves) { r in LabeledContent(r.name, value: r.amount.compact) }
                Button { addingReserve = true } label: { Label("Set money aside", systemImage: "lock") }
            }
            Section {
                Button(snapshot.items.isEmpty && snapshot.reserves.isEmpty ? "Skip" : "Continue", action: next)
                    .bold().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("continue")
            }
        }
        .sheet(isPresented: $addingBill) { PlannedItemEditor(sheet: .new(.outflow)) }
        .sheet(isPresented: $addingReserve) { ReserveEditor() }
    }
}

/// Plans the essentials for this month, then shows what's left and why
private struct EssentialsStep: View {
    @Environment(LedgerStore.self) private var store
    let finish: () -> Void
    @State private var amounts: [UUID: String] = [:]
    @State private var error: String?

    /// Starter essentials when they exist, otherwise the first few spending categories
    private var categories: [LedgerAccountRecord] {
        let all = store.snapshot.expenseCategories.sorted { $0.sortOrder < $1.sortOrder }
        let essentials = all.filter { $0.group == "Essentials" }
        return essentials.isEmpty ? Array(all.prefix(5)) : essentials
    }

    var body: some View {
        let snapshot = store.snapshot
        let month = snapshot.monthKey
        let result = snapshot.safeToSpend()
        let unplanned = snapshot.budget.availableToAllocate(month: month)
        Form {
            Section {
                Text("Plan the essentials").font(.title2.bold())
                Text("Roughly what you spend each month on the basics. Bills you added are already counted, so leave those empty.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section {
                ForEach(categories, id: \.id) { c in
                    let line = snapshot.budget.line(c.id, month: month)
                    HStack {
                        Label(c.name, systemImage: c.icon).foregroundStyle(.primary)
                        Spacer()
                        if line.fromBills.isPositive {
                            Text("\(line.fromBills.compact) in bills").foregroundStyle(.secondary).font(.subheadline)
                        }
                        TextField("0", text: binding(c.id, current: line.allocated))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
            } footer: {
                Text("Amounts are in \(store.currency). You can change them any time in Budget.")
            }

            if let amount = result.amount {
                Section {
                    LabeledContent("In spending accounts", value: result.spendableTotal.compact)
                    if result.obligationsTotal.isPositive {
                        LabeledContent("Bills before \(result.periodEnd.formatted(.dateTime.day().month(.abbreviated)))", value: "−" + result.obligationsTotal.compact)
                    }
                    if result.categoryReservationsTotal.isPositive {
                        LabeledContent("Planned for essentials", value: "−" + result.categoryReservationsTotal.compact)
                    }
                    if result.reservesTotal.isPositive {
                        LabeledContent("Set aside", value: "−" + result.reservesTotal.compact)
                    }
                    if result.buffer.isPositive { LabeledContent("Buffer", value: "−" + result.buffer.compact) }
                    LabeledContent {
                        Text(amount.isNegative ? "Short by \(amount.magnitude.compact)" : amount.compact)
                            .bold().foregroundStyle(amount.isNegative ? .orange : .primary)
                    } label: {
                        Text("Safe to spend").bold()
                    }
                } header: {
                    Text("What's actually free")
                } footer: {
                    Text(amount.isNegative
                         ? "Bills and plans need more than your spending accounts hold before payday. Home shows what to do about it."
                         : "What you can spend on anything until payday, after bills and the essentials above. It's the big number on Home.")
                }
                if !unplanned.isZero {
                    Section {
                        LabeledContent("Not planned yet", value: unplanned.compact)
                    } footer: {
                        Text(unplanned.isNegative
                             ? "You've planned more than you have this month. Lower an amount above, or adjust it later in Budget."
                             : "Money no budget uses yet. It isn't extra cash: give it a budget later, or leave it.")
                    }
                }
            }

            if let error { Section { FieldError(message: error) } }

            Section {
                Button("Finish") { saveAll(); if error == nil { finish() } }
                    .bold().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("finish")
            }
        }
    }

    private func binding(_ id: UUID, current: Money) -> Binding<String> {
        Binding(get: { amounts[id] ?? MoneyFormat.editable(current, emptyWhenZero: true) },
                // Saved as typed, so the summary below follows along; mistakes are only reported on Finish
                set: { amounts[id] = $0; save(id, quietly: true) })
    }

    private func save(_ id: UUID, quietly: Bool = false) {
        guard let text = amounts[id] else { return }
        guard let amount = MoneyFormat.parse(text.isEmpty ? "0" : text, currency: store.currency), !amount.isNegative else {
            if !quietly { error = "Enter each amount as a number." }
            return
        }
        if !quietly { error = nil }
        do { try store.setAllocation(amount, categoryId: id, month: store.snapshot.monthKey) }
        catch { self.error = StoreError.from(error).errorDescription }
    }

    private func saveAll() {
        error = nil
        for id in amounts.keys { save(id); if error != nil { return } }
    }
}
