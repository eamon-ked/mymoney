//
//  AccountsView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct AccountsView: View {
    @StateObject private var repository = AccountRepository()
    @StateObject private var loanRepository = LoanRepository()
    @State private var showingAddAccount = false
    @State private var monthIncome: Decimal = 0
    @State private var monthSpending: Decimal = 0
    
    private var accountTotal: Decimal {
        repository.accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }
    
    private var loanDebt: Decimal {
        loanRepository.loans.reduce(Decimal(0)) { $0 + $1.remainingBalance }
    }
    
    private var netWorth: Decimal { accountTotal - loanDebt }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    SummaryBanner(
                        amount: netWorth,
                        title: "Net worth",
                        tint: netWorth < 0 ? .red : .indigo,
                        details: [
                            ("In this month", formatMoneyCompact(monthIncome)),
                            ("Out this month", formatMoneyCompact(monthSpending)),
                            ("Loans", formatMoneyCompact(loanDebt))
                        ])
                    .bannerRow()
                }
                
                if repository.accounts.isEmpty {
                    Section {
                        EmptyStateRow(
                            symbol: "building.columns",
                            title: "No accounts yet",
                            message: "Add your bank accounts, cash and cards to see your balances in one place.",
                            actionTitle: "Add account") { showingAddAccount = true }
                    }
                }
                
                ForEach(AccountGroup.allCases, id: \.self) { group in
                    let accounts = repository.accounts.filter { group.contains($0.type) }
                    if !accounts.isEmpty {
                        Section {
                            ForEach(accounts, id: \.id) { account in
                                NavigationLink(destination: AccountDetailView(account: account, accountRepository: repository)) {
                                    AccountRowView(account: account)
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { accounts[$0] }.forEach(repository.deleteAccount)
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                Spacer()
                                Text(formatMoneyCompact(accounts.reduce(Decimal(0)) { $0 + $1.balance }))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddAccount = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add account")
                }
            }
            .sheet(isPresented: $showingAddAccount, onDismiss: refresh) {
                AddAccountView(repository: repository)
            }
            .onAppear(perform: refresh)
            .refreshable { refresh() }
        }
    }
    
    private func refresh() {
        repository.loadAccounts()
        loanRepository.loadLoans()
        let interval = Calendar.current.dateInterval(of: .month, for: Date())
        let budgetIds = Set(repository.accounts.map(\.id))
        let thisMonth = ((try? LocalDatabaseManager.shared.fetchAllActiveTransactions()) ?? [])
            .filter { t in interval.map { $0.contains(t.transactionDate) } ?? false && budgetIds.contains(t.accountId) }
        monthIncome = thisMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        monthSpending = thisMonth.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
}

enum AccountGroup: CaseIterable {
    case cash, credit, investments
    
    var title: String {
        switch self {
        case .cash: return "Cash & bank"
        case .credit: return "Credit cards"
        case .investments: return "Investments"
        }
    }
    
    func contains(_ type: AccountType) -> Bool {
        switch self {
        case .cash: return [.checking, .savings, .cash].contains(type)
        case .credit: return type == .creditCard
        case .investments: return type == .investment
        }
    }
}

struct AccountRowView: View {
    let account: Account
    
    private var caption: String {
        var parts = [account.institutionName, account.type.displayName].compactMap { $0 }.filter { !$0.isEmpty }
        if !account.onBudget { parts.append("Off budget") }
        return parts.joined(separator: " · ")
    }
    
    var body: some View {
        ListRow(title: account.name,
                caption: caption,
                symbol: account.type.iconName,
                color: Color(hex: account.color) ?? .blue) {
            AmountPill(account.balance)
        }
    }
}

struct AddAccountView: View {
    @ObservedObject var repository: AccountRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedType = AccountType.checking
    @State private var balance = ""
    @State private var institutionName = ""
    @State private var selectedColor = Color.blue
    
    private let colors: [Color] = [
        .blue, .green, .red, .orange, .purple, .pink, .yellow, .indigo
    ]
    
    private var isCard: Bool { selectedType == .creditCard }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Account name", text: $name)
                    Picker("Type", selection: $selectedType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    TextField("Bank (optional)", text: $institutionName)
                }
                
                Section {
                    TextField("0.00", text: $balance)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(isCard ? "Amount owed today" : "Balance today")
                } footer: {
                    Text(isCard
                         ? "Enter what you owe on the card. Spending on it raises this; paying it off is a transfer from your bank account."
                         : selectedType == .investment
                            ? "Investment accounts stay out of your budget."
                            : "Every transaction you add from now on keeps this balance up to date.")
                }
                
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                        .opacity(selectedColor == color ? 1 : 0)
                                )
                                .onTapGesture { selectedColor = color }
                                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveAccount() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func saveAccount() {
        let entered = Money.parse(balance) ?? 0
        // A card's balance is what it holds, so money owed is negative
        let opening = isCard ? -abs(entered) : entered
        
        let account = Account(
            name: name.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            openingBalance: opening,
            institutionName: institutionName.isEmpty ? nil : institutionName,
            color: selectedColor.toHex()
        )
        // The user just entered this balance, so it needs no repair
        account.balanceConfirmedAt = Date()
        
        repository.addAccount(account)
        dismiss()
    }
}

struct AccountDetailView: View {
    let account: Account
    @ObservedObject var accountRepository: AccountRepository
    @StateObject private var transactionRepository = TransactionRepository()
    @StateObject private var categoryRepository = CategoryRepository()
    @State private var onBudget = true
    @State private var editingTransaction: Transaction?
    
    private var accountNames: [UUID: String] {
        Dictionary(accountRepository.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    
    private var categoriesById: [UUID: Category] {
        Dictionary(categoryRepository.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    
    var body: some View {
        List {
            Section {
                SummaryBanner(
                    amount: account.balance,
                    title: account.type == .creditCard && account.balance < 0 ? "Owed on this card" : "Balance",
                    tint: account.balance < 0 ? .red : (Color(hex: account.color) ?? .blue))
                .bannerRow()
            }
            
            Section {
                LabeledContent("Type", value: account.type.displayName)
                if let institution = account.institutionName, !institution.isEmpty {
                    LabeledContent("Bank", value: institution)
                }
                Toggle("Include in budget", isOn: $onBudget)
                    .onChange(of: onBudget) { _, value in
                        guard value != account.onBudget else { return }
                        account.onBudget = value
                        accountRepository.updateAccount(account)
                    }
            } footer: {
                Text("Money in budget accounts counts towards Ready to Assign.")
            }
            
            Section("Transactions") {
                if transactionRepository.transactions.isEmpty {
                    Text("No transactions yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(transactionRepository.transactions, id: \.id) { transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRowView(transaction: transaction,
                                               accountNames: accountNames,
                                               categoriesById: categoriesById,
                                               viewingAccountId: account.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(
                transactionRepository: transactionRepository,
                accountRepository: accountRepository,
                categoryRepository: categoryRepository,
                editing: transaction
            )
        }
        .onAppear {
            onBudget = account.onBudget
            transactionRepository.loadTransactions(for: account.id)
        }
    }
}

extension AccountType {
    var iconName: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "building.columns.fill"
        case .creditCard: return "creditcard"
        case .cash: return "dollarsign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}


#Preview {
    AccountsView()
}