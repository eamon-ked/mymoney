//
//  TransactionsView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct TransactionsView: View {
    @StateObject private var repository = TransactionRepository()
    @StateObject private var accountRepository = AccountRepository()
    @StateObject private var categoryRepository = CategoryRepository()
    @State private var showingAddTransaction = false
    @State private var searchText = ""
    @State private var selectedType: TransactionType? = nil
    
    var filteredTransactions: [Transaction] {
        var transactions = repository.transactions
        
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                transaction.transactionDescription.localizedCaseInsensitiveContains(searchText) ||
                transaction.notes?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        if let type = selectedType {
            transactions = transactions.filter { $0.type == type }
        }
        
        return transactions
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterButton(
                            title: "All",
                            isSelected: selectedType == nil
                        ) {
                            selectedType = nil
                        }
                        
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            FilterButton(
                                title: type.displayName,
                                isSelected: selectedType == type
                            ) {
                                selectedType = type
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                List {
                    ForEach(filteredTransactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    repository.deleteTransaction(transaction)
                                }
                            }
                    }
                }
                .searchable(text: $searchText, prompt: "Search transactions...")
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTransaction = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView(
                    transactionRepository: repository,
                    accountRepository: accountRepository,
                    categoryRepository: categoryRepository
                )
            }
            .refreshable {
                repository.loadTransactions()
            }
        }
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack {
            // Category icon
            Circle()
                .fill(categoryColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: categoryIcon)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.transactionDescription)
                    .font(.headline)
                    .lineLimit(1)
                
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(transaction.transactionDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountString)
                    .font(.headline)
                    .foregroundColor(amountColor)
                
                if transaction.syncStatus == "pending" {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var categoryColor: Color {
        if let category = transaction.category {
            return Color(hex: category.color) ?? .gray
        }
        return .gray
    }
    
    private var categoryIcon: String {
        if let category = transaction.category {
            return category.icon
        }
        return "questionmark"
    }
    
    private var amountString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        let amount = formatter.string(from: transaction.amount as NSDecimalNumber) ?? "$0.00"
        
        switch transaction.type {
        case .income:
            return "+\(amount)"
        case .expense:
            return "-\(amount)"
        case .transfer:
            return amount
        }
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return .green
        case .expense:
            return .red
        case .transfer:
            return .blue
        }
    }
}

struct AddTransactionView: View {
    @ObservedObject var transactionRepository: TransactionRepository
    @ObservedObject var accountRepository: AccountRepository
    @ObservedObject var categoryRepository: CategoryRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var description = ""
    @State private var amount = ""
    @State private var selectedType = TransactionType.expense
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var notes = ""
    @State private var date = Date()
    @State private var tags: [String] = []
    @State private var newTag = ""
    
    var availableCategories: [Category] {
        categoryRepository.getCategoriesByType(selectedType == .transfer ? .expense : selectedType)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    TextField("Description", text: $description)
                    
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: selectedType) { _ in
                        selectedCategory = nil
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accountRepository.accounts, id: \.id) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                }
                
                if selectedType != .transfer {
                    Section("Category") {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Select Category").tag(nil as Category?)
                            ForEach(availableCategories, id: \.id) { category in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: category.color) ?? .gray)
                                        .frame(width: 20, height: 20)
                                    Text(category.name)
                                }
                                .tag(category as Category?)
                            }
                        }
                    }
                }
                
                Section("Additional Info") {
                    TextField("Notes (Optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.headline)
                        
                        if !tags.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack {
                                        Text(tag)
                                            .font(.caption)
                                        Button(action: { removeTag(tag) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Add tag", text: $newTag)
                                .onSubmit {
                                    addTag()
                                }
                            Button("Add", action: addTag)
                                .disabled(newTag.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !description.isEmpty && !amount.isEmpty && selectedAccount != nil
    }
    
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
            tags.append(trimmedTag)
            newTag = ""
        }
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    private func saveTransaction() {
        guard let account = selectedAccount,
              let amountDecimal = Decimal(string: amount) else {
            return
        }
        
        let transaction = Transaction(
            accountId: account.id,
            categoryId: selectedCategory?.id,
            amount: amountDecimal,
            type: selectedType,
            transactionDescription: description,
            notes: notes.isEmpty ? nil : notes,
            transactionDate: date,
            tags: tags
        )
        
        transactionRepository.addTransaction(transaction)
        dismiss()
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

#Preview {
    TransactionsView()
}