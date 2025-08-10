import SwiftUI

struct LoansView: View {
    @StateObject private var repository = LoanRepository()
    @State private var showingAddLoan = false
    
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

private var currencyFormatter: NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .currency
    let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    f.currencyCode = code.isEmpty ? "USD" : code
    return f
}


