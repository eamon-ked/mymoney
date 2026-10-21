//
//  BudgetView.swift
//  PersonalFinanceApp
//
//  Budget tab: give every dirham a job before you spend it.
//

import SwiftUI

struct BudgetView: View {
    @StateObject private var repository = BudgetRepository()
    // Seeds the default categories on first launch, now that Budget is the first tab
    @StateObject private var categoryRepository = CategoryRepository()
    @State private var editingCategory: Category?

    var body: some View {
        NavigationView {
            List {
                Section {
                    ReadyToAssignBanner(amount: repository.readyToAssign)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    if repository.categories.isEmpty {
                        Text("No expense categories yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(repository.categories, id: \.id) { category in
                            Button {
                                editingCategory = category
                            } label: {
                                BudgetCategoryRow(
                                    category: category,
                                    line: repository.line(for: category),
                                    needed: repository.needed(for: category))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MonthSwitcher(month: repository.month,
                                  onPrevious: repository.previousMonth,
                                  onNext: repository.nextMonth)
                }
            }
            .onAppear { repository.reload() }
            .onReceive(categoryRepository.$categories) { _ in repository.reload() }
            .refreshable { repository.reload() }
            .sheet(item: $editingCategory) { category in
                CategoryBudgetDetailView(repository: repository, category: category)
            }
        }
    }
}

// MARK: - Pieces

private struct MonthSwitcher: View {
    let month: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Text(title).font(.headline).frame(minWidth: 120)
            Button(action: onNext) { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
    }

    private var title: String {
        guard let date = BudgetMonth.date(from: month) else { return month }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

private struct ReadyToAssignBanner: View {
    let amount: Decimal

    var body: some View {
        VStack(spacing: 4) {
            Text(formatMoney(amount))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(amount < 0 ? "Assigned more than you have" : "Ready to Assign")
                .font(.subheadline)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(amount < 0 ? Color.red : (amount == 0 ? Color.gray : Color.green))
    }
}

private struct BudgetCategoryRow: View {
    let category: Category
    let line: BudgetCalculator.CategoryLine
    let needed: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: category.color) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(category.name)
                    .font(.body)
                    .lineLimit(1)
                if category.isPayFirst {
                    Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                }
                Spacer(minLength: 8)
                Text(formatMoney(line.available))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(line.available < 0 ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(availableColor))
            }
            HStack(spacing: 12) {
                Text("Assigned \(formatMoney(line.assigned))")
                Text("Spent \(formatMoney(line.spent))")
                if needed > 0 {
                    Text("\(formatMoney(needed)) needed").foregroundColor(.orange)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 18)
        }
        .monospacedDigit()
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    
    private var availableColor: Color {
        if line.available < 0 { return .red }
        if line.available > 0 { return Color.green.opacity(0.25) }
        return Color.gray.opacity(0.15)
    }
}

// MARK: - Category detail: assign, target, move money

struct CategoryBudgetDetailView: View {
    @ObservedObject var repository: BudgetRepository
    let category: Category
    @Environment(\.dismiss) private var dismiss

    @State private var assignedText = ""
    @State private var targetText = ""
    @State private var showingMoveMoney = false

    var body: some View {
        let line = repository.line(for: category)
        NavigationView {
            Form {
                Section("This month") {
                    HStack {
                        Text("Assigned")
                        Spacer()
                        TextField("0.00", text: $assignedText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Spent", value: formatMoney(line.spent))
                    LabeledContent("Available", value: formatMoney(line.available))
                    if line.available < 0 {
                        Text("Overspent. Move money in from another category to cover it.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Button("Move money into \(category.name)") { showingMoveMoney = true }
                }

                Section {
                    HStack {
                        Text("Monthly target")
                        Spacer()
                        TextField("None", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("The budget shows how much more this category needs each month to reach its target.")
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                assignedText = plain(line.assigned)
                targetText = category.monthlyTarget.map(plain) ?? ""
            }
            .sheet(isPresented: $showingMoveMoney) {
                MoveMoneyView(repository: repository, destination: category) {
                    assignedText = plain(repository.line(for: category).assigned)
                }
            }
        }
    }

    private func save() {
        if let assigned = parseMoney(assignedText), assigned != repository.line(for: category).assigned {
            repository.setAssigned(assigned, for: category)
        }
        let target = parseMoney(targetText)
        if target != category.monthlyTarget {
            repository.setTarget(target, for: category)
        }
        dismiss()
    }
}

struct MoveMoneyView: View {
    @ObservedObject var repository: BudgetRepository
    let destination: Category
    var onMoved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var source: Category?
    @State private var amountText = ""

    private var sources: [Category] {
        repository.categories.filter { $0.id != destination.id }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("From", selection: $source) {
                        Text("Select Category").tag(nil as Category?)
                        ForEach(sources, id: \.id) { c in
                            Text("\(c.name) (\(formatMoney(repository.line(for: c).available)))")
                                .tag(c as Category?)
                        }
                    }
                    LabeledContent("To", value: destination.name)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }
                if repository.line(for: destination).available < 0 {
                    Section {
                        Button("Cover the overspending (\(formatMoney(-repository.line(for: destination).available)))") {
                            amountText = plain(-repository.line(for: destination).available)
                        }
                    }
                }
            }
            .navigationTitle("Move money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Move") {
                        guard let source, let amount = parseMoney(amountText) else { return }
                        repository.move(amount, from: source, to: destination)
                        onMoved()
                        dismiss()
                    }
                    .disabled(source == nil || (parseMoney(amountText) ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Pay yourself first

/// Shown after saving an income transaction
struct PaydaySheet: View {
    let income: Decimal
    let incomeDate: Date
    @StateObject private var repository = BudgetRepository()
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    var body: some View {
        NavigationView {
            Form {
                if let category = repository.payFirstCategory {
                    Section {
                        Text("You received \(formatMoney(income)). Pay yourself first: put money into \(category.name) before anything else.")
                    }
                    Section("Assign to \(category.name)") {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Assign to Savings first?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Assign") {
                        if let amount = parseMoney(amountText) {
                            repository.assignPayFirst(amount, incomeDate: incomeDate)
                        }
                        dismiss()
                    }
                    .disabled((parseMoney(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                amountText = plain(BudgetRepository.suggestedPayFirst(for: income))
            }
        }
        .presentationDetents([.medium])
    }
}

/// Settings section: which category is funded first, and with what share of each paycheck
struct PayFirstSettingsSection: View {
    @StateObject private var repository = BudgetRepository()
    @State private var selected: Category?
    @State private var percentText = ""

    var body: some View {
        Section {
            Picker("Savings category", selection: $selected) {
                Text("None").tag(nil as Category?)
                ForEach(repository.categories, id: \.id) { c in
                    Text(c.name).tag(c as Category?)
                }
            }
            .onChange(of: selected) { _, newValue in
                repository.setPayFirst(newValue)
            }
            HStack {
                Text("Share of each paycheck")
                Spacer()
                TextField("10", text: $percentText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onChange(of: percentText) { _, new in
                        if let value = Decimal(string: new), value >= 0, value <= 100 {
                            UserDefaults.standard.set(new, forKey: BudgetRepository.payFirstPercentKey)
                        }
                    }
                Text("%")
            }
        } header: {
            Text("Pay yourself first")
        } footer: {
            Text("When you add income, the app offers to assign this share to your savings category first.")
        }
        .onAppear {
            repository.reload()
            selected = repository.payFirstCategory
            percentText = plain(BudgetRepository.payFirstPercent)
        }
    }
}

// MARK: - Formatting

func formatMoney(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    formatter.currencyCode = code.isEmpty ? "USD" : code
    return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
}

private func plain(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func parseMoney(_ text: String) -> Decimal? {
    let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    guard !cleaned.isEmpty else { return nil }
    return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
}
