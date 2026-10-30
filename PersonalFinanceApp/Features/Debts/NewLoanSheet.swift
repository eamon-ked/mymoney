//
//  NewLoanSheet.swift
//  Nokael Money
//
//  "I have a loan" in one form: what it is, what's owed, and the monthly
//  payment. Nobody needs to know a loan is kept as an account; it's saved
//  there, its payment goes into the bills, and Pay a loan finds it.
//

import SwiftUI
import NokaelCore

struct NewLoanSheet: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var kind: AccountKind = .loan
    @State private var name = ""
    @State private var lender = ""
    @State private var owedText = ""
    @State private var paymentText = ""
    @State private var rateText = ""
    @State private var dueDay: Int?
    @State private var fundingId: UUID?
    /// Loans only; nil is Loan payments
    @State private var categoryId: UUID?
    @State private var error: String?
    @State private var saved: LedgerAccountRecord?

    private var isCard: Bool { kind == .creditCard }

    var body: some View {
        NavigationStack {
            Group {
                if let saved { done(saved) } else { form }
            }
            .navigationTitle(isCard ? "Add a credit card" : "Add a loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(saved == nil ? "Cancel" : "Close") { dismiss() } }
                if saved == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).accessibilityIdentifier("saveLoan")
                    }
                }
            }
            .onAppear {
                fundingId = fundingId ?? store.snapshot.settings.lastUsedAccountId ?? store.snapshot.accounts.first(where: \.spendable)?.id
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("This is a", selection: $kind) {
                    Text("Loan").tag(AccountKind.loan)
                    Text("Credit card").tag(AccountKind.creditCard)
                }
                .pickerStyle(.segmented)
                TextField(isCard ? "Name, e.g. Mashreq Cashback card" : "Name, e.g. Car loan", text: $name)
                    .accessibilityIdentifier("loanName")
                TextField(isCard ? "Bank (optional)" : "Bank or lender (optional)", text: $lender)
            }

            Section {
                amountField(isCard ? "Owed on the card today" : "Still owed today", text: $owedText, id: "loanOwed")
            } footer: {
                Text(isCard ? "The balance from your banking app or latest statement."
                            : "Not the original loan amount: what's left to pay, from your banking app or statement.")
            }

            Section {
                amountField(isCard ? "You pay each month" : "Monthly instalment", text: $paymentText, id: "loanPayment")
                Picker("Paid on", selection: $dueDay) {
                    Text("Not sure").tag(nil as Int?)
                    ForEach(1...31, id: \.self) { Text("Day \($0) of the month").tag($0 as Int?) }
                }
                AccountPicker(title: "Paid from", accounts: store.snapshot.accounts.filter { $0.kind.holdsMoney }, selection: $fundingId)
                HStack {
                    Text("Interest rate")
                    Spacer()
                    TextField("optional", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("% a year").foregroundStyle(.secondary)
                }
            } header: {
                Text("Monthly payment")
            } footer: {
                Text("With a payment day, the payment is added to your bills and kept aside in safe-to-spend. Skip the rate if you don't know it; you can add it later.")
            }

            if !isCard {
                Section {
                    LoanCategoryPicker(selection: $categoryId)
                } footer: {
                    Text("Its payments count here in Budget and Reports. Several loans can share one.")
                }
            }

            if let error { Section { FieldError(message: error) } }
        }
    }

    private func done(_ debt: LedgerAccountRecord) -> some View {
        ContentUnavailableView {
            Label("\(debt.name) added", systemImage: "checkmark.circle")
        } description: {
            Text(debt.debtTerms?.dueDay != nil
                 ? "Its payment is in your bills. When you pay it, tap + and choose I paid a loan or credit card."
                 : "When you make a payment, tap + and choose I paid a loan or credit card. You'll find it under Accounts too.")
        } actions: {
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private func amountField(_ title: String, text: Binding<String>, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(store.currency).foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? (isCard ? "Credit card" : "Loan") : name
        guard let owed = owedText.isEmpty ? Money.zero(store.currency) : MoneyFormat.parse(owedText, currency: store.currency) else {
            error = "Enter what you owe as a number."; return
        }
        let payment = paymentText.isEmpty ? nil : MoneyFormat.parse(paymentText, currency: store.currency)
        if !paymentText.isEmpty && payment?.isPositive != true { error = "Enter the monthly payment as a number."; return }
        guard let bps = DebtTerms.rateBps(from: rateText.isEmpty ? "0" : rateText) else {
            error = "Enter the yearly rate as a percentage, e.g. 4.5, or leave it empty."; return
        }
        do {
            let debt = try store.createAccount(name: title, kind: kind, opening: owed.magnitude.negated, openingDate: Date(),
                                               institution: lender.isEmpty ? nil : lender,
                                               colorHex: AccountColors.next(for: kind))
            if !isCard, categoryId != nil { try store.setLoanCategory(categoryId, for: debt.id) }
            if let payment {
                try store.saveDebtTerms(DebtTerms(annualRateBps: bps, monthlyPayment: payment, dueDay: dueDay),
                                        for: debt.id, paidFrom: dueDay == nil ? nil : fundingId)
            }
            saved = debt
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }
}

/// Which budget category a loan's payments count under: Loan payments, or any spending category
struct LoanCategoryPicker: View {
    @Environment(LedgerStore.self) private var store
    @Binding var selection: UUID?
    @State private var creating = false

    /// Picking this opens the category editor instead of choosing it
    private static let newCategory = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    var body: some View {
        let snapshot = store.snapshot
        let loanPayments = FinanceSnapshot.systemCategory("loanPayments", name: "Loan payments", in: snapshot.accountRecords)
        let interest = FinanceSnapshot.systemCategory("interest", name: "Interest & fees", in: snapshot.accountRecords)
        Picker("Budget category", selection: Binding(get: { selection }, set: { picked in
            if picked == Self.newCategory { creating = true } else { selection = picked }
        })) {
            Text(loanPayments?.name ?? "Loan payments").tag(nil as UUID?)
            ForEach(snapshot.expenseCategories.filter { $0.id != loanPayments?.id && $0.id != interest?.id }, id: \.id) {
                Text($0.name).tag($0.id as UUID?)
            }
            Divider()
            Label("New category…", systemImage: "plus").tag(Self.newCategory as UUID?)
        }
        .accessibilityIdentifier("loanCategory")
        .sheet(isPresented: $creating) {
            CategoryEditor(forLoans: true) { selection = $0 }
        }
    }
}
