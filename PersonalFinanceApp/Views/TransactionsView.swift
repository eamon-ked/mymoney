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
    @State private var savedIncome: Transaction?
    @State private var paydayIncome: Transaction?
    @State private var editingTransaction: Transaction?
    @State private var monthIn: Decimal = 0
    @State private var monthOut: Decimal = 0
    
    private var categoriesById: [UUID: Category] {
        Dictionary(categoryRepository.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    
    private var accountNames: [UUID: String] {
        Dictionary(accountRepository.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    
    var filteredTransactions: [Transaction] {
        repository.transactions.filter { t in
            (selectedType == nil || t.type == selectedType) &&
            (searchText.isEmpty
             || t.transactionDescription.localizedCaseInsensitiveContains(searchText)
             || t.notes?.localizedCaseInsensitiveContains(searchText) == true
             || t.categoryId.flatMap { categoriesById[$0] }?.name.localizedCaseInsensitiveContains(searchText) == true)
        }
    }
    
    /// Newest day first
    private var days: [(day: Date, items: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { calendar.startOfDay(for: $0.transactionDate) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    SummaryBanner(
                        amount: monthOut,
                        title: "Spent in \(Date().formatted(.dateTime.month(.wide)))",
                        tint: .orange,
                        details: [("Money in", formatMoneyCompact(monthIn)),
                                  ("Left over", formatMoneyCompact(monthIn - monthOut))])
                    .bannerRow()
                }
                
                Section {
                    Picker("Show", selection: $selectedType) {
                        Text("All").tag(nil as TransactionType?)
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type as TransactionType?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                if days.isEmpty {
                    Section {
                        if repository.transactions.isEmpty {
                            EmptyStateRow(
                                symbol: "list.bullet.rectangle",
                                title: "No transactions yet",
                                message: "Add what you earn and spend, and your balances and budget update on their own.",
                                actionTitle: "Add transaction") { showingAddTransaction = true }
                        } else {
                            Text("Nothing matches").foregroundColor(.secondary)
                        }
                    }
                }
                
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.items, id: \.id) { transaction in
                            Button { editingTransaction = transaction } label: {
                                TransactionRowView(transaction: transaction, accountNames: accountNames, categoriesById: categoriesById)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            repository.deleteTransaction(transaction)
                                            refreshTotals()
                                        }
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(group.day))
                            Spacer()
                            Text(dayNet(group.items)).monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: filteredTransactions.map { $0.id })
            .searchable(text: $searchText, prompt: "Search transactions")
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTransaction = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
            .sheet(isPresented: $showingAddTransaction, onDismiss: offerPayFirst) {
                AddTransactionView(
                    transactionRepository: repository,
                    accountRepository: accountRepository,
                    categoryRepository: categoryRepository,
                    onSaved: { transaction in
                        if transaction.type == .income { savedIncome = transaction }
                    }
                )
                .onAppear {
                    // Ensure the latest accounts are available in the picker
                    accountRepository.loadAccounts()
                }
            }
            .sheet(item: $editingTransaction, onDismiss: refreshTotals) { transaction in
                AddTransactionView(
                    transactionRepository: repository,
                    accountRepository: accountRepository,
                    categoryRepository: categoryRepository,
                    editing: transaction
                )
            }
            .sheet(item: $paydayIncome) { income in
                PaydaySheet(income: income.amount, incomeDate: income.transactionDate)
            }
            .onAppear {
                repository.loadTransactions(limit: 500)
                accountRepository.loadAccounts()
                refreshTotals()
            }
            .refreshable {
                repository.loadTransactions(limit: 500)
                refreshTotals()
            }
        }
    }
    
    private func refreshTotals() {
        guard let month = Calendar.current.dateInterval(of: .month, for: Date()) else { return }
        let rows = ((try? LocalDatabaseManager.shared.fetchAllActiveTransactions()) ?? [])
            .filter { month.contains($0.transactionDate) }
        monthIn = rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        monthOut = rows.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
    
    private func dayNet(_ items: [Transaction]) -> String {
        let net = items.reduce(Decimal(0)) { total, t in
            switch t.type {
            case .income: return total + t.amount
            case .expense: return total - t.amount
            case .transfer: return total
            }
        }
        return net == 0 ? "" : (net > 0 ? "+" : "−") + formatMoneyCompact(abs(net))
    }
    
    /// Payday: offer to fund the pay-first category before anything else
    private func offerPayFirst() {
        refreshTotals()
        guard let income = savedIncome else { return }
        savedIncome = nil
        let onBudget = accountRepository.getAccount(by: income.accountId)?.onBudget ?? true
        let hasPayFirst = categoryRepository.categories.contains { $0.isPayFirst && $0.type == .expense }
        if onBudget && hasPayFirst { paydayIncome = income }
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    var accountNames: [UUID: String] = [:]
    var categoriesById: [UUID: Category] = [:]
    /// When shown inside one account, a transfer reads as money in or out of it
    var viewingAccountId: UUID? = nil
    
    var body: some View {
        ListRow(title: transaction.transactionDescription,
                caption: caption,
                symbol: symbol,
                color: color) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(amountColor)
                if transaction.syncStatus == "pending" && SupabaseManager.shared.isAuthenticated {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Not synced yet")
                }
            }
        }
    }
    
    private var caption: String {
        if transaction.type == .transfer {
            let from = accountNames[transaction.accountId]
            let to = transaction.transferAccountId.flatMap { accountNames[$0] }
            if let from, let to { return "\(from) → \(to)" }
            return "Transfer"
        }
        let parts = [category?.name, accountNames[transaction.accountId], transaction.notes]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    
    private var symbol: String {
        if transaction.type == .transfer { return "arrow.left.arrow.right" }
        return category?.icon ?? (transaction.type == .income ? "arrow.down" : "questionmark")
    }
    
    private var color: Color {
        if transaction.type == .transfer { return .blue }
        if let category { return Color(hex: category.color) ?? .gray }
        return transaction.type == .income ? .green : .gray
    }
    
    private var category: Category? {
        transaction.categoryId.flatMap { categoriesById[$0] } ?? transaction.category
    }
    
    private var isIncomingTransfer: Bool {
        transaction.type == .transfer && viewingAccountId != nil && transaction.transferAccountId == viewingAccountId
    }
    
    private var amountText: String {
        let amount = formatMoneyCompact(transaction.amount)
        switch transaction.type {
        case .income: return "+\(amount)"
        case .expense: return "−\(amount)"
        case .transfer:
            guard viewingAccountId != nil else { return amount }
            return isIncomingTransfer ? "+\(amount)" : "−\(amount)"
        }
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .income: return .green
        case .expense: return .primary
        case .transfer: return isIncomingTransfer ? .green : .secondary
        }
    }
}

struct AddTransactionView: View {
    @ObservedObject var transactionRepository: TransactionRepository
    @ObservedObject var accountRepository: AccountRepository
    @ObservedObject var categoryRepository: CategoryRepository
    var onSaved: (Transaction) -> Void = { _ in }
    /// When set, the form edits this transaction instead of adding a new one
    var editing: Transaction? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var didPrefill = false
    @State private var confirmingDelete = false
    
    @State private var description = ""
    @State private var amount = ""
    @State private var selectedType = TransactionType.expense
    @State private var selectedAccount: Account?
    @State private var selectedDestinationAccount: Account?
    @State private var selectedCategory: Category?
    @State private var notes = ""
    @State private var date = Date()
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isRecurring = false
    @State private var recurringFrequency = "Monthly"
    
    var availableCategories: [Category] {
        let categoryType: CategoryType = (selectedType == .income) ? .income : .expense
        return categoryRepository.getCategoriesByType(categoryType)
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
                    .onChange(of: selectedType) { _, newType in
                        // Keep the category only if it still fits the type
                        if let category = selectedCategory,
                           !availableCategories.contains(where: { $0.id == category.id }) {
                            selectedCategory = nil
                        }
                        if newType != .transfer { selectedDestinationAccount = nil }
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Recurring") {
                    Toggle("Repeat", isOn: $isRecurring)
                        .disabled(selectedType != .income)
                    Picker("Frequency", selection: $recurringFrequency) {
                        Text("Weekly").tag("Weekly")
                        Text("Monthly").tag("Monthly")
                        Text("Yearly").tag("Yearly")
                    }
                    .disabled(!isRecurring || selectedType != .income)
                    Text("Tip: For salary, choose Income and enable Repeat.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Account") {
                    Picker(selectedType == .transfer ? "From" : "Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accountRepository.accounts, id: \.id) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    
                    if selectedType == .transfer {
                        Picker("To", selection: $selectedDestinationAccount) {
                            Text("Select Account").tag(nil as Account?)
                            ForEach(accountRepository.accounts.filter { $0.id != selectedAccount?.id }, id: \.id) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                    }
                }
                .onChange(of: selectedAccount) { _, newValue in
                    if selectedDestinationAccount?.id == newValue?.id {
                        selectedDestinationAccount = nil
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
                
                if editing != nil {
                    Section {
                        Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New transaction" : "Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: prefill)
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing { transactionRepository.deleteTransaction(editing) }
                    dismiss()
                }
            } message: {
                Text("Account balances and your budget update straight away.")
            }
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
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty,
              let value = Money.parse(amount), value > 0,
              let account = selectedAccount else { return false }
        if selectedType == .transfer {
            guard let destination = selectedDestinationAccount, destination.id != account.id else { return false }
        }
        return true
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
    
    /// Fills the form from the transaction being edited, once
    private func prefill() {
        guard let t = editing, !didPrefill else { return }
        didPrefill = true
        description = t.transactionDescription
        amount = Money.plain(t.amount)
        selectedType = t.type
        selectedAccount = accountRepository.accounts.first { $0.id == t.accountId }
        selectedDestinationAccount = t.transferAccountId.flatMap { id in accountRepository.accounts.first { $0.id == id } }
        selectedCategory = t.categoryId.flatMap { id in categoryRepository.categories.first { $0.id == id } }
        notes = t.notes ?? ""
        date = t.transactionDate
        tags = t.tags
        isRecurring = t.isRecurring
        recurringFrequency = t.recurringFrequency ?? "Monthly"
    }
    
    private func saveTransaction() {
        guard let account = selectedAccount, let amountDecimal = Money.parse(amount) else { return }
        let transferAccountId = selectedType == .transfer ? selectedDestinationAccount?.id : nil
        let categoryId = selectedType == .transfer ? nil : selectedCategory?.id
        let recurring = isRecurring && selectedType == .income
        
        if let t = editing {
            // Remember where it was, so both old and new accounts get recomputed
            let previousAccountId = t.accountId
            let previousTransferAccountId = t.transferAccountId
            t.accountId = account.id
            t.transferAccountId = transferAccountId
            t.categoryId = categoryId
            t.amount = amountDecimal
            t.type = selectedType
            t.transactionDescription = description.trimmingCharacters(in: .whitespaces)
            t.notes = notes.isEmpty ? nil : notes
            t.transactionDate = date
            t.isRecurring = recurring
            t.recurringFrequency = recurring ? recurringFrequency : nil
            t.tags = tags
            transactionRepository.updateTransaction(t, previousAccountId: previousAccountId,
                                                    previousTransferAccountId: previousTransferAccountId)
            dismiss()
            return
        }
        
        let transaction = Transaction(
            accountId: account.id,
            transferAccountId: transferAccountId,
            categoryId: categoryId,
            amount: amountDecimal,
            type: selectedType,
            transactionDescription: description.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            transactionDate: date,
            isRecurring: recurring,
            recurringFrequency: recurring ? recurringFrequency : nil,
            tags: tags
        )
        
        transactionRepository.addTransaction(transaction)
        onSaved(transaction)
        dismiss()
    }
}

#Preview {
    TransactionsView()
}