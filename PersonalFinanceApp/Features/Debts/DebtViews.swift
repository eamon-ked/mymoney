//
//  DebtViews.swift
//  Nokael Money
//
//  Cards and loans: the rate and monthly payment, when the debt is paid off
//  (and how much sooner with a bit more each month), and payments split into
//  interest, fees and principal.
//

import SwiftUI
import NokaelCore

extension Payoff {
    /// One line for rows, e.g. "Paid off Aug 2029"
    var shortText: String {
        switch self {
        case .alreadyPaidOff: return "Paid off"
        case .paidOff(_, let last, _, _): return "Paid off " + last.formatted(.dateTime.month(.abbreviated).year())
        case .never: return "Payment doesn't cover interest"
        case .beyondHorizon: return "Over 50 years to pay off"
        }
    }
}

extension DebtTerms {
    var rateText: String { "\(annualRatePercent.formatted(.number.precision(.fractionLength(0...2))))% a year" }
}

/// The sheets a debt's page opens; owned by the page, since sheets inside list sections are unreliable
enum DebtSheet: String, Identifiable {
    case terms, pay, plus
    var id: String { rawValue }
}

/// Shown on a card's or loan's page, above its entries
struct DebtSection: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    let debt: LedgerAccountRecord
    @Binding var sheet: DebtSheet?
    @State private var extraText = ""

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        Section {
            Button { sheet = .pay } label: { Label("I made a payment", systemImage: "checkmark.circle.fill") }
                .bold()
                .disabled(!snapshot.owed(debt.id).isPositive)
                .accessibilityIdentifier("payDebt")
            if let terms = debt.debtTerms {
                LabeledContent("Interest", value: terms.rateText)
                LabeledContent("Monthly payment", value: terms.monthlyPayment.compact)
                if let day = terms.dueDay {
                    LabeledContent("Due", value: "Day \(day) of each month")
                }
                if let item = snapshot.paymentItem(for: debt.id), let from = snapshot.account(item.accountId) {
                    LabeledContent("Paid from", value: from.name)
                }
                Button("Change rate or payment") { sheet = .terms }
            } else {
                Button { sheet = .terms } label: {
                    Label("Add the interest rate and monthly payment", systemImage: "percent")
                }
            }
        } header: {
            Text(debt.kind == .creditCard ? "Card" : "Loan")
        } footer: {
            Text(debt.debtTerms == nil
                 ? "With the rate and payment, Nokael works out when you'll be debt-free and splits each payment into interest and principal."
                 : "Only the principal part of a payment lowers what you owe. Interest and fees are counted as spending.")
        }

        if debt.debtTerms != nil, let payoff = snapshot.payoff(for: debt) {
            Section {
                PayoffSummary(payoff: payoff)
                if !plus.isPlus {
                    Button { sheet = .plus } label: {
                        HStack {
                            Text("See what paying extra saves")
                            Spacer()
                            PlusBadge()
                        }
                    }
                } else {
                HStack {
                    Text("Pay extra each month")
                    Spacer()
                    Text(store.currency).foregroundStyle(.secondary)
                    TextField("0", text: $extraText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityIdentifier("extraPayment")
                }
                if let extra = MoneyFormat.parse(extraText, currency: store.currency), extra.isPositive,
                   let faster = snapshot.payoff(for: debt, extra: extra) {
                    PayoffComparison(base: payoff, faster: faster, extra: extra)
                }
                }
            } header: {
                Text("Payoff")
            } footer: {
                Text("An estimate that assumes the rate stays the same and nothing new is added.")
            }
        }
    }
}

struct PayoffSummary: View {
    let payoff: Payoff

    var body: some View {
        switch payoff {
        case .alreadyPaidOff:
            Label("Nothing owed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .paidOff(months, last, interest, final):
            LabeledContent("Debt-free", value: last.formatted(.dateTime.month(.wide).year()))
            LabeledContent("Payments left", value: "\(months)")
            LabeledContent("Interest still to pay", value: interest.compact)
            if months > 1 { LabeledContent("Last payment", value: final.compact) }
        case .never(let monthly):
            Label("At this payment the balance never falls. Interest is about \(monthly.compact) a month, so pay more than that.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .beyondHorizon:
            Label("Paying this off takes more than 50 years at this payment.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

struct PayoffComparison: View {
    let base: Payoff
    let faster: Payoff
    let extra: Money

    var body: some View {
        if case let .paidOff(months, _, interest, _) = faster {
            let saved: (months: Int, interest: Money)? = {
                if case let .paidOff(baseMonths, _, baseInterest, _) = base { return (baseMonths - months, baseInterest - interest) }
                return nil
            }()
            VStack(alignment: .leading, spacing: 4) {
                Text("With \(extra.compact) more a month: debt-free \(faster.shortText.replacingOccurrences(of: "Paid off ", with: ""))")
                    .font(.subheadline.weight(.semibold))
                if let saved, saved.months > 0 {
                    Text("\(saved.months) \(saved.months == 1 ? "month" : "months") sooner, \(saved.interest.compact) less interest")
                        .font(.footnote).foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            PayoffSummary(payoff: faster)
        }
    }
}

// MARK: - Terms

struct DebtTermsEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debt: LedgerAccountRecord

    @State private var rateText = ""
    @State private var paymentText = ""
    @State private var dueDay: Int?
    @State private var addBill = true
    @State private var fundingId: UUID?
    @State private var error: String?

    var body: some View {
        let snapshot = store.snapshot
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Interest rate")
                        Spacer()
                        TextField("0", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .accessibilityIdentifier("debtRate")
                        Text("% a year").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Monthly payment")
                        Spacer()
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("0", text: $paymentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .accessibilityIdentifier("debtPayment")
                    }
                    Picker("Due on", selection: $dueDay) {
                        Text("Not set").tag(nil as Int?)
                        ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0 as Int?) }
                    }
                } footer: {
                    Text(debt.kind == .creditCard
                         ? "Use the rate on your statement, and what you plan to pay each month (at least the minimum)."
                         : "Use the rate and instalment from your loan agreement.")
                }

                Section {
                    Toggle("Add to my bills", isOn: $addBill)
                    if addBill {
                        AccountPicker(title: "Paid from", accounts: snapshot.accounts.filter { $0.kind.isAsset }, selection: $fundingId)
                    }
                } footer: {
                    Text(addBill
                         ? "The payment shows in Plan each month and is set aside in safe-to-spend until it's paid. Needs a due day."
                         : "The payment won't be reserved in safe-to-spend.")
                }

                if debt.debtTerms != nil {
                    Section {
                        Button("Remove rate and payment", role: .destructive) { save(clearing: true) }
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle(debt.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("saveTerms") }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let snapshot = store.snapshot
        let item = snapshot.paymentItem(for: debt.id)
        if let terms = debt.debtTerms {
            rateText = NSDecimalNumber(decimal: terms.annualRatePercent).stringValue
            paymentText = MoneyFormat.editable(terms.monthlyPayment)
            dueDay = terms.dueDay
            addBill = item != nil
        }
        fundingId = item?.accountId ?? snapshot.settings.lastUsedAccountId ?? snapshot.accounts.first { $0.spendable }?.id
    }

    private func save(clearing: Bool = false) {
        let terms: DebtTerms?
        if clearing {
            terms = nil
        } else {
            guard let bps = DebtTerms.rateBps(from: rateText.isEmpty ? "0" : rateText) else {
                error = "Enter the yearly rate as a percentage, e.g. 4.5."; return
            }
            guard let payment = MoneyFormat.parse(paymentText, currency: store.currency), payment.isPositive else {
                error = "Enter the monthly payment."; return
            }
            if addBill && dueDay == nil { error = "Choose the due day so the payment can be added to your bills."; return }
            if addBill && fundingId == nil { error = "Choose the account you pay from."; return }
            terms = DebtTerms(annualRateBps: bps, monthlyPayment: payment, dueDay: dueDay)
        }
        do {
            try store.saveDebtTerms(terms, for: debt.id, paidFrom: addBill ? fundingId : nil)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

// MARK: - Paying

struct PayDebtSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debt: LedgerAccountRecord
    /// The bill this pays, when opened from Plan
    var occurrence: Occurrence? = nil

    @State private var key = UUID()
    @State private var amountText = ""
    @State private var fundingId: UUID?
    @State private var date = Date()
    @State private var fromStatement = false
    @State private var interestText = ""
    @State private var feesText = ""
    @State private var error: String?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var owed: Money { snapshot.owed(debt.id) }
    private var amount: Money? { MoneyFormat.parse(amountText, currency: store.currency) }

    /// The split as it will be recorded
    private var split: PaymentSplit? {
        guard let amount, amount.isPositive else { return nil }
        let zero = Money.zero(store.currency)
        if fromStatement {
            let interest = interestText.isEmpty ? zero : MoneyFormat.parse(interestText, currency: store.currency)
            let fees = feesText.isEmpty ? zero : MoneyFormat.parse(feesText, currency: store.currency)
            guard let interest, let fees else { return nil }
            return DebtCalculator.split(payment: amount, owed: owed, annualRateBps: 0, interest: interest, fees: fees)
        }
        return DebtCalculator.split(payment: amount, owed: owed, annualRateBps: debt.debtRateBps ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("You owe", value: owed.formatted)
                    if let occurrence {
                        LabeledContent("Due", value: occurrence.dueDate.formatted(date: .long, time: .omitted))
                    }
                    HStack {
                        Text(store.currency).foregroundStyle(.secondary)
                        TextField("Payment", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("debtPaymentAmount")
                    }
                    AccountPicker(title: "From", accounts: snapshot.accounts.filter { $0.kind.isAsset }, selection: $fundingId)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Toggle("Use the amounts on my statement", isOn: $fromStatement)
                    if fromStatement {
                        moneyField("Interest charged", text: $interestText)
                        moneyField("Fees charged", text: $feesText)
                    }
                    if let split {
                        LabeledContent(fromStatement || debt.debtRateBps == nil ? "Interest" : "Interest (estimated)",
                                       value: split.interest.compact)
                        if split.fees.isPositive { LabeledContent("Fees", value: split.fees.compact) }
                        LabeledContent("Lowers what you owe by", value: split.principal.compact).bold()
                        LabeledContent("You'll owe after", value: (owed - split.principal).compact)
                        if split.overpaid.isPositive {
                            FieldError(message: "That's \(split.overpaid.compact) more than you owe. Lower the payment.")
                        }
                    }
                } header: {
                    Text("How it's split")
                } footer: {
                    Text(debt.debtRateBps == nil && !fromStatement
                         ? "No interest rate is set, so the whole payment lowers what you owe. Add the rate on the card's or loan's page, or use your statement's amounts."
                         : "The estimate is one month of interest at \(debt.debtTerms?.rateText ?? "the rate"). Your lender's figure can differ a little; use your statement's amounts to match it exactly.")
                }

                if occurrence != nil {
                    Section {
                        Button("Skip this one") {
                            if let occurrence { try? store.skip(occurrenceId: occurrence.id) }
                            dismiss()
                        }
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Pay \(debt.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record", action: record).accessibilityIdentifier("recordDebtPayment")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(store.currency).foregroundStyle(.secondary)
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
    }

    private func load() {
        let item = snapshot.paymentItem(for: debt.id)
        let suggested = occurrence?.remaining ?? debt.debtTerms?.monthlyPayment
        if let suggested {
            // Never suggest more than clears the debt with this month's interest
            let clears = owed + DebtCalculator.monthlyInterest(owed: owed, annualRateBps: debt.debtRateBps ?? 0)
            amountText = MoneyFormat.editable(Money.min(suggested, clears), emptyWhenZero: true)
        }
        fundingId = item?.accountId ?? snapshot.settings.lastUsedAccountId ?? snapshot.accounts.first { $0.spendable }?.id
        if let occurrence { date = min(Date(), max(occurrence.dueDate, snapshot.calendar.startOfDay(for: Date()))) }
    }

    private func record() {
        guard let amount, amount.isPositive else { error = "Enter the payment."; return }
        guard let fundingId else { error = "Choose the account you paid from."; return }
        guard let split else { error = "Enter interest and fees as numbers."; return }
        guard split.overpaid.isZero else { error = "That's more than you owe. Lower the payment."; return }
        do {
            try store.payDebt(debt.id, from: fundingId, amount: amount, interest: split.interest, fees: split.fees,
                              date: date, key: key, occurrenceId: occurrence?.id)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}

// MARK: - Changing a recorded split

/// The lender's own figures for a payment already recorded with an estimate
struct ResplitSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: EntryRecord
    let parts: LedgerStore.DebtPaymentParts

    @State private var interestText = ""
    @State private var feesText = ""
    @State private var error: String?

    private var interest: Money? { interestText.isEmpty ? .zero(store.currency) : MoneyFormat.parse(interestText, currency: store.currency) }
    private var fees: Money? { feesText.isEmpty ? .zero(store.currency) : MoneyFormat.parse(feesText, currency: store.currency) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("You paid", value: parts.total.formatted)
                    moneyField("Interest", text: $interestText)
                    moneyField("Fees", text: $feesText)
                } footer: {
                    Text("Use the interest shown for this payment on your loan or card statement, or in your bank's app.")
                }
                if let interest, let fees, !(parts.total < interest + fees) {
                    Section {
                        LabeledContent("Comes off \(parts.debt.name)", value: (parts.total - interest - fees).formatted).bold()
                    }
                }
                if let error { Section { FieldError(message: error) } }
            }
            .navigationTitle("Change the split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                interestText = MoneyFormat.editable(parts.interest, emptyWhenZero: true)
                feesText = MoneyFormat.editable(parts.fees, emptyWhenZero: true)
            }
        }
    }

    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(store.currency).foregroundStyle(.secondary)
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
        }
    }

    private func save() {
        guard let interest, let fees else { error = "Enter interest and fees as numbers."; return }
        do {
            try store.resplitDebtPayment(record.id, interest: interest, fees: fees)
            dismiss()
        } catch { self.error = StoreError.from(error).errorDescription }
    }
}
