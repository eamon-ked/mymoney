//
//  AccountsView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct AccountsView: View {
    @StateObject private var repository = AccountRepository()
    @State private var showingAddAccount = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(repository.accounts, id: \.id) { account in
                    NavigationLink(destination: AccountDetailView(account: account)) {
                        AccountRowView(account: account)
                    }
                }
                .onDelete(perform: deleteAccounts)
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddAccount = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(repository: repository)
            }
            .refreshable {
                repository.loadAccounts()
            }
        }
    }
    
    private func deleteAccounts(offsets: IndexSet) {
        for index in offsets {
            repository.deleteAccount(repository.accounts[index])
        }
    }
}

struct AccountRowView: View {
    let account: Account
    
    var body: some View {
        HStack {
            // Account type icon
            Circle()
                .fill(Color(hex: account.color) ?? .blue)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: account.type.iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                
                if let institution = account.institutionName {
                    Text(institution)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(account.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(currencyFormatter.string(from: account.balance as NSDecimalNumber) ?? "$0.00")
                    .font(.headline)
                    .foregroundColor(account.balance >= 0 ? .primary : .red)
                
                if account.syncStatus == "pending" {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
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
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $name)
                    
                    Picker("Account Type", selection: $selectedType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    TextField("Initial Balance", text: $balance)
                        .keyboardType(.decimalPad)
                    
                    TextField("Institution (Optional)", text: $institutionName)
                }
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAccount()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveAccount() {
        let balanceDecimal = Decimal(string: balance) ?? 0
        
        let account = Account(
            name: name,
            type: selectedType,
            balance: balanceDecimal,
            institutionName: institutionName.isEmpty ? nil : institutionName,
            color: selectedColor.toHex()
        )
        
        repository.addAccount(account)
        dismiss()
    }
}

struct AccountDetailView: View {
    let account: Account
    @StateObject private var transactionRepository = TransactionRepository()
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Circle()
                            .fill(Color(hex: account.color) ?? .blue)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: account.type.iconName)
                                    .foregroundColor(.white)
                                    .font(.system(size: 24, weight: .medium))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let institution = account.institutionName {
                                Text(institution)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(account.type.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text(currencyFormatter.string(from: account.balance as NSDecimalNumber) ?? "$0.00")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(account.balance >= 0 ? .primary : .red)
                }
                .padding(.vertical, 8)
            }
            
            Section("Recent Transactions") {
                if transactionRepository.transactions.isEmpty {
                    Text("No transactions yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(transactionRepository.transactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle("Account Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            transactionRepository.loadTransactions(for: account.id)
        }
    }
}

extension AccountType {
    var iconName: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "piggybank"
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

private let currencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter
}()

#Preview {
    AccountsView()
}