//
//  AddChooser.swift
//  Nokael Money
//
//  What + opens: "What happened?" in plain words, each choice leading straight
//  to the right form. Paying a loan, a card or a bill is here too, so nobody
//  has to know it lives on the account's page.
//

import SwiftUI
import NokaelCore

struct AddChooser: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable {
        case entry(AddKind)
        case debt(UUID)
        case bill(Occurrence)
        case newDebt
        case payday
        case help
    }

    enum Focus { case debts }

    @State private var step: Step?
    @State private var showDebts = false
    @State private var showBills = false
    var focus: Focus? = nil

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        switch step {
        case .entry(let kind):
            EntryEditor(kind: kind)
        case .debt(let id):
            if let debt = snapshot.account(id) { PayDebtSheet(debt: debt) }
        case .bill(let occurrence):
            PayScheduledSheet(occurrence: occurrence)
        case .newDebt:
            NewLoanSheet()
        case .payday:
            PaydaySheet()
        case .help:
            GuideView()
        case nil:
            chooser
        }
    }

    private var chooser: some View {
        let debts = snapshot.debts.filter { snapshot.owed($0.id).isPositive }
        let bills = Array(snapshot.upcomingBills(days: 31).filter { snapshot.item(for: $0)?.direction == .outflow }.prefix(6))
        return NavigationStack {
            List {
                Section {
                    if let salary = PaydayPlan.salaryItem(snapshot) {
                        choice("I got my \(salary.name.lowercased())", detail: "\(salary.amount.compact) into \(snapshot.account(salary.accountId)?.name ?? "your account"), then plan the month",
                               symbol: "banknote.fill", color: .green) { step = .payday }
                    }
                    choice("I spent money", detail: "Shopping, food, fuel, a bill you paid on the spot",
                           symbol: "cart.fill", color: Palette.home) { step = .entry(.expense) }
                    choice("I received money", detail: "Salary, a refund, money someone sent you",
                           symbol: "arrow.down.circle.fill", color: .green) { step = .entry(.income) }
                    choice("I paid a loan or credit card", detail: debts.isEmpty ? "First tell us about the loan, it takes a minute"
                                                                                 : "Lowers what you owe; interest is worked out for you",
                           symbol: "creditcard.fill", color: .red) {
                        if debts.isEmpty { step = .newDebt }
                        else if debts.count == 1 { step = .debt(debts[0].id) }
                        else { withAnimation { showDebts.toggle() } }
                    }
                    if showDebts {
                        ForEach(debts, id: \.id) { debt in
                            Button { step = .debt(debt.id) } label: {
                                LabeledContent(debt.name, value: "owe \(snapshot.owed(debt.id).compact)")
                                    .padding(.leading, 52)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    if !bills.isEmpty {
                        choice("I paid a bill", detail: "Rent, electricity, phone, anything in your plan",
                               symbol: "calendar.badge.checkmark", color: Palette.plan) { withAnimation { showBills.toggle() } }
                        if showBills {
                            ForEach(bills) { occ in
                                Button { step = .bill(occ) } label: {
                                    LabeledContent(snapshot.item(for: occ)?.name ?? "Bill",
                                                   value: "\(occ.remaining.compact) · \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))")
                                        .padding(.leading, 52)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    choice("I moved money between my accounts", detail: "Bank to savings, cash withdrawal",
                           symbol: "arrow.left.arrow.right.circle.fill", color: .blue) { step = .entry(.transfer) }
                    choice("I have a loan or credit card", detail: "Car loan, personal loan, mortgage or a card: add what you owe",
                           symbol: "plus.rectangle.on.rectangle", color: .orange) { step = .newDebt }
                    choice("A balance is wrong", detail: "Set what an account really holds today",
                           symbol: "slider.horizontal.3", color: .gray) { step = .entry(.adjustment) }
                }

                Section {
                    choice("Not sure? Ask the guide", detail: "Type what happened, e.g. “I paid 2,000 on my car loan”",
                           symbol: "questionmark.circle.fill", color: .purple) { step = .help }
                }
            }
            .navigationTitle("What happened?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if focus == .debts {
                    if debts.count == 1 { step = .debt(debts[0].id) } else if debts.isEmpty { step = .newDebt } else { showDebts = true }
                }
            }
        }
    }

    private func choice(_ title: String, detail: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
        .accessibilityIdentifier("add-\(title)")
    }
}

/// Three big buttons under safe-to-spend, for the things people do most
struct QuickActions: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.addEntry) private var addEntry
    @Environment(\.chooseAdd) private var chooseAdd

    var body: some View {
        let hasDebts = store.snapshot.debts.contains { store.snapshot.owed($0.id).isPositive }
        HStack(spacing: 10) {
            tile("Spent", symbol: "cart.fill", color: Palette.home) { addEntry(.expense) }
            tile("Received", symbol: "arrow.down.circle.fill", color: .green) { addEntry(.income) }
            if hasDebts {
                tile("Pay a loan", symbol: "creditcard.fill", color: .red) { chooseAdd(.debts) }
            } else {
                tile("More", symbol: "ellipsis.circle.fill", color: .gray) { chooseAdd(nil) }
            }
        }
    }

    private func tile(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}
