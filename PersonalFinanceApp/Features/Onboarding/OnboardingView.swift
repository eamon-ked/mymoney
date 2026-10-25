//
//  OnboardingView.swift
//  Nokael Money
//
//  Four short, resumable steps to a first useful overview. Progress is saved
//  after each step; income and bills can be skipped; nothing is invented.
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
                default: BillsStep(finish: finish)
                }
            }
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { go(step - 1) } label: { Label("Back", systemImage: "chevron.left") }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Step \(step) of 4").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
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
        try? store.updateSettings { $0.onboardingDone = true; $0.onboardingStep = 4 }
    }
}

private struct WelcomeStep: View {
    let next: () -> Void

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
            Text("Everything stays on this iPhone for now.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

private struct CurrencyStep: View {
    @Environment(LedgerStore.self) private var store
    let next: () -> Void
    @State private var currency = "AED"
    @State private var starters = true

    private let currencies = ["AED", "SAR", "QAR", "KWD", "BHD", "OMR", "USD", "EUR", "GBP", "INR", "PKR", "PHP"]

    var body: some View {
        Form {
            Section {
                Text("Your currency").font(.title2.bold())
                Text("Amounts are shown and stored in this currency.").foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            Section {
                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
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
                    try? store.updateSettings { $0.currency = currency; $0.localeIdentifier = currency == "AED" ? "en_AE" : Locale.current.identifier }
                    if starters { try? store.addStarterCategories() }
                    next()
                }
                .bold()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("continue")
            }
        }
        .onAppear { currency = store.settings.currency }
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
            try store.createAccount(name: name, kind: kind, opening: kind.isLiability ? entered.magnitude.negated : entered,
                                    openingDate: balanceDate, institution: institution.isEmpty ? nil : institution,
                                    colorHex: AccountColors.next(for: kind))
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
        guard let amount = MoneyFormat.parse(amountText, currency: store.currency), amount.isPositive else {
            error = "Enter your usual pay, or skip."
            return
        }
        let snapshot = store.snapshot
        let item = PlannedItem(name: "Salary", direction: .inflow, amount: amount,
                               schedule: Schedule(start: store.calendar.startOfDay(for: nextDate).addingTimeInterval(12 * 3600), frequency: frequency),
                               accountId: snapshot.accounts.first { $0.spendable }?.id,
                               categoryId: snapshot.incomeCategories.first?.id)
        do {
            try store.savePlannedItem(item)
            try store.updateSettings { $0.payFrequencyData = try? JSONEncoder().encode(frequency) }
            next()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

private struct BillsStep: View {
    @Environment(LedgerStore.self) private var store
    let finish: () -> Void
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
                Button(snapshot.items.isEmpty && snapshot.reserves.isEmpty ? "Skip and finish" : "Finish", action: finish)
                    .bold().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("finish")
            }
        }
        .sheet(isPresented: $addingBill) { PlannedItemEditor(sheet: .new(.outflow)) }
        .sheet(isPresented: $addingReserve) { ReserveEditor() }
    }
}
