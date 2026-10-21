//
//  RepairBalancesView.swift
//  PersonalFinanceApp
//
//  One-time sheet after upgrading to v1.1: v1.0 balances drifted after edits
//  and deletes, so the user confirms each account's real balance once and the
//  opening balance is solved backwards from it.
//

import SwiftUI

enum BalanceRepair {
    static let doneKey = "balanceRepairDone_v11"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    static func markDone() { UserDefaults.standard.set(true, forKey: doneKey) }

    /// Accounts whose opening balance nobody has confirmed yet, on any device
    @MainActor
    static func accountsNeedingRepair() -> [Account] {
        let accounts = (try? LocalDatabaseManager.shared.fetchAccounts()) ?? []
        return accounts.filter { $0.balanceConfirmedAt == nil }
    }
}

struct RepairBalancesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isPulling = true
    @State private var accounts: [Account] = []
    @State private var entries: [UUID: String] = [:]
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isPulling {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Fetching all your transactions…")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Form {
                        Section {
                            Text("We fixed how balances are calculated. Enter what each account really holds today, and the app will keep it correct from now on.")
                                .font(.subheadline)
                        }

                        ForEach(accounts, id: \.id) { account in
                            Section(account.name) {
                                HStack {
                                    Text("Transactions total")
                                    Spacer()
                                    Text(format(transactionTotal(for: account)))
                                        .foregroundColor(.secondary)
                                }
                                HStack {
                                    Text("Your real balance today")
                                    Spacer()
                                    TextField("0.00", text: binding(for: account))
                                        .keyboardType(.numbersAndPunctuation)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }

                        Section {
                            Text("Transactions you deleted earlier may show again; delete them once more and they will stay deleted.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage).foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Check your balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        // Skipping keeps today's stored balances as the starting point
                        BalanceRepair.markDone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isPulling)
                }
            }
        }
        .interactiveDismissDisabled()
        .task { await load() }
    }

    private func load() async {
        // Pull everything first so every transaction is counted
        await SyncManager.shared.forceSyncNow()
        if SupabaseManager.shared.isAuthenticated && SyncManager.shared.syncError != nil {
            // Partial data would give wrong totals; ask again on the next launch
            dismiss()
            return
        }
        accounts = BalanceRepair.accountsNeedingRepair()
        for account in accounts {
            entries[account.id] = NSDecimalNumber(decimal: account.balance).stringValue
        }
        isPulling = false
        if accounts.isEmpty {
            BalanceRepair.markDone()
            dismiss()
        }
    }

    private func save() {
        let localDB = LocalDatabaseManager.shared
        do {
            for account in accounts {
                let text = (entries[account.id] ?? "").replacingOccurrences(of: ",", with: "")
                guard let real = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                    errorMessage = "Enter a number for \(account.name)."
                    return
                }
                account.openingBalance = real - (try localDB.transactionTotal(for: account.id))
                account.balanceConfirmedAt = Date()
                account.updatedAt = Date()
                account.syncStatus = "pending"
            }
            try localDB.recalculateAllBalances()
            BalanceRepair.markDone()
            SyncManager.shared.triggerSync()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func binding(for account: Account) -> Binding<String> {
        Binding(
            get: { entries[account.id] ?? "" },
            set: { entries[account.id] = $0 }
        )
    }

    private func transactionTotal(for account: Account) -> Decimal {
        (try? LocalDatabaseManager.shared.transactionTotal(for: account.id)) ?? 0
    }

    private func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let code = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
        formatter.currencyCode = code.isEmpty ? "USD" : code
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
