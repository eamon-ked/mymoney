import SwiftUI

struct LoansView: View {
    @StateObject private var repository = LoanRepository()
    @State private var showingAddLoan = false
    @State private var showingUpdateLoan = false
    @State private var loanToUpdate: PrivateLoan? = nil
    
    var body: some View {
        NavigationView {
            List {
                ForEach(repository.loans, id: \.id) { loan in
                    LoanRowView(loan: loan)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    repository.deleteLoan(loan)
                                }
                            }
                            Button("Update") {
                                loanToUpdate = loan
                                showingUpdateLoan = true
                            }
                        }
                }
            }
            .navigationTitle("Loans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showingAddLoan = true } }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLoan) {
                AddLoanView(repository: repository)
            }
            .sheet(isPresented: $showingUpdateLoan) {
                if let loan = loanToUpdate {
                    UpdateLoanProgressView(repository: repository, loan: loan)
                }
            }
            .refreshable { repository.loadLoans() }
        }
    }
}

struct LoanRowView: View {
    let loan: PrivateLoan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loan.loanName)
                    .font(.headline)
                Spacer()
                Text(currencyFormatter.string(from: loan.remainingBalance as NSDecimalNumber) ?? "$0.00")
                    .font(.headline)
            }
            
            if let lender = loan.lenderName, !lender.isEmpty {
                Text(lender)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: loan.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .animation(.easeInOut(duration: 0.25), value: loan.progress)
            
            HStack {
                Text("Monthly: \(currencyFormatter.string(from: loan.monthlyPayment as NSDecimalNumber) ?? "$0.00")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let next = loan.nextPaymentDate {
                    Text("Next: \(next, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .transition(.opacity)
    }
}

struct AddLoanView: View {
    @ObservedObject var repository: LoanRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var loanName = ""
    @State private var lenderName = ""
    @State private var originalAmount = ""
    @State private var remainingBalance = ""
    @State private var interestRate = ""
    @State private var monthlyPayment = ""
    @State private var startDate = Date()
    @State private var endDate: Date? = nil
    @State private var nextPaymentDate: Date? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section("Loan Details") {
                    TextField("Loan Name", text: $loanName)
                    TextField("Lender (Optional)", text: $lenderName)
                    TextField("Original Amount", text: $originalAmount).keyboardType(.decimalPad)
                    TextField("Remaining Balance", text: $remainingBalance).keyboardType(.decimalPad)
                    TextField("Interest Rate (%)", text: $interestRate).keyboardType(.decimalPad)
                    TextField("Monthly Payment", text: $monthlyPayment).keyboardType(.decimalPad)
                }
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Has End Date", isOn: Binding(
                        get: { endDate != nil },
                        set: { has in endDate = has ? Date() : nil }
                    ))
                    if let _ = endDate {
                        DatePicker("End Date", selection: Binding(get: { endDate ?? Date() }, set: { endDate = $0 }), displayedComponents: .date)
                    }
                    Toggle("Has Next Payment Date", isOn: Binding(
                        get: { nextPaymentDate != nil },
                        set: { has in nextPaymentDate = has ? Date() : nil }
                    ))
                    if let _ = nextPaymentDate {
                        DatePicker("Next Payment", selection: Binding(get: { nextPaymentDate ?? Date() }, set: { nextPaymentDate = $0 }), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !loanName.isEmpty && Decimal(string: originalAmount) != nil && Decimal(string: remainingBalance) != nil && Decimal(string: monthlyPayment) != nil && Decimal(string: interestRate) != nil
    }
    
    private func save() {
        guard let original = Decimal(string: originalAmount),
              let remaining = Decimal(string: remainingBalance),
              let monthly = Decimal(string: monthlyPayment),
              let rate = Decimal(string: interestRate) else { return }
        
        let loan = PrivateLoan(
            loanName: loanName,
            loanType: nil,
            lenderName: lenderName.isEmpty ? nil : lenderName,
            originalAmount: original,
            remainingBalance: remaining,
            interestRate: rate,
            monthlyPayment: monthly,
            startDate: startDate,
            endDate: endDate,
            nextPaymentDate: nextPaymentDate
        )
        repository.addLoan(loan)
        dismiss()
    }
}

struct UpdateLoanProgressView: View {
    @ObservedObject var repository: LoanRepository
    let loan: PrivateLoan
    @Environment(\.dismiss) private var dismiss

    @State private var newRemainingBalance: String = ""
    @State private var nextPaymentDate: Date? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Update Progress") {
                    TextField("New Remaining Balance", text: $newRemainingBalance)
                        .keyboardType(.decimalPad)
                    Toggle("Update Next Payment Date", isOn: Binding(
                        get: { nextPaymentDate != nil },
                        set: { has in nextPaymentDate = has ? (loan.nextPaymentDate ?? Date()) : nil }
                    ))
                    if let _ = nextPaymentDate {
                        DatePicker("Next Payment", selection: Binding(get: { nextPaymentDate ?? Date() }, set: { nextPaymentDate = $0 }), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Update Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(Decimal(string: newRemainingBalance) == nil)
                }
            }
            .onAppear {
                newRemainingBalance = (loan.remainingBalance as NSDecimalNumber).stringValue
                nextPaymentDate = loan.nextPaymentDate
            }
        }
    }

    private func save() {
        guard let remaining = Decimal(string: newRemainingBalance) else { return }
        loan.remainingBalance = remaining
        if let date = nextPaymentDate { loan.nextPaymentDate = date }
        loan.updatedAt = Date()
        loan.syncStatus = "pending"
        repository.updateLoan(loan)
        dismiss()
    }
}

private var currencyFormatter: NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    f.currencyCode = code.isEmpty ? "USD" : code
    return f
}


