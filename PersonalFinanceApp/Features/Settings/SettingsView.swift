//
//  SettingsView.swift
//  Nokael Money
//

import SwiftUI
import StoreKit
import NokaelCore

/// Settings: what people change sits on the first page; the rest is one tap in
struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingPlus = false
    @State private var managingPlan = false

    var body: some View {
        NavigationStack {
            Form {
                PlusSection(showingPaywall: $showingPlus, managing: $managingPlan)

                Section {
                    NavigationLink { CaptureSetupView() } label: {
                        Label("Siri & automatic capture", systemImage: "wallet.pass")
                    }
                    NavigationLink { Form { BillRemindersSection() }.navigationTitle("Bill reminders") } label: {
                        Label("Bill reminders", systemImage: "bell")
                    }
                    NavigationLink { Form { AppleIntelligenceSection() }.navigationTitle("Apple Intelligence") } label: {
                        Label("Apple Intelligence", systemImage: "sparkles")
                    }
                    Toggle(isOn: settingsBinding(store, \.biometricLock)) {
                        Label("Lock with Face ID", systemImage: "faceid")
                    }
                }

                BackupSection()

                Section {
                    NavigationLink { MoneyPreferencesView() } label: {
                        Label("Currency & categories", systemImage: "banknote")
                    }
                    NavigationLink { YourDataView(close: { dismiss() }) } label: {
                        Label("Your data", systemImage: "tray.full")
                    }
                } footer: {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPlus) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $managingPlan)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HelpButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

@MainActor
private func settingsBinding<T>(_ store: LedgerStore, _ path: ReferenceWritableKeyPath<SettingsRecord, T>) -> Binding<T> {
    Binding(get: { store.settings[keyPath: path] },
            set: { value in try? store.updateSettings { $0[keyPath: path] = value } })
}

/// Currency, the week, when balances count as old, and the category list
struct MoneyPreferencesView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        Form {
            Section {
                LabeledContent("Currency", value: store.settings.currency)
                Picker("Week starts on", selection: settingsBinding(store, \.firstWeekday)) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Saturday").tag(7)
                }
            }
            Section {
                NavigationLink("Categories") { CategoryListView() }
            }
        }
        .navigationTitle("Currency & categories")
    }
}

/// Export, the change history, and erasing everything
struct YourDataView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    let close: () -> Void
    @State private var confirmErase = false
    @State private var paywall: PlusFeature?
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Button { if plus.isPlus { export() } else { paywall = .export } } label: {
                    HStack {
                        Label("Export all entries (CSV)", systemImage: "square.and.arrow.up")
                        if !plus.isPlus { Spacer(); PlusBadge() }
                    }
                }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export", systemImage: "doc.text") }
                }
                NavigationLink("Change history") { AuditListView() }
            } footer: {
                Text("A spreadsheet of every entry, for your own records. To move or recover your data, use a backup.")
            }

            Section {
                Button("Delete all data on this iPhone", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Removes every account, entry, budget and bill from this device. Without a backup, this can't be undone.")
            }

            if let error { Section { FieldError(message: error) } }
        }
        .navigationTitle("Your data")
        .paywall($paywall)
        .confirmationDialog("Delete all data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                do { try store.eraseAllData(); close() } catch { self.error = StoreError.from(error).errorDescription }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func export() {
        let snapshot = store.snapshot
        var rows = ["Date,Type,Description,Account,Category,Amount,Currency,Status,Notes"]
        for record in snapshot.entries(includeVoided: true).reversed() {
            let accounts = record.lines.compactMap { snapshot.account($0.accountId) }
            let sheet = record.lines.filter { snapshot.account($0.accountId)?.kind.isBalanceSheet == true }
            let category = accounts.first { $0.kind.isCategory }?.name ?? ""
            for line in sheet {
                let account = snapshot.account(line.accountId)?.name ?? ""
                rows.append([
                    ISO8601DateFormatter.string(from: record.date, timeZone: snapshot.calendar.timeZone, formatOptions: [.withFullDate]),
                    record.kindRaw, record.memo, account, category,
                    "\(Money(minorUnits: line.minorUnits, currency: line.currency).decimal)", line.currency,
                    record.statusRaw, record.notes
                ].map(csv).joined(separator: ","))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nokael-money-entries.csv")
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch { self.error = "Couldn't create the export." }
    }

    private func csv(_ field: String) -> String {
        field.contains(where: { ",\"\n".contains($0) }) ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }
}

struct CategoryListView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: LedgerAccountRecord?
    @State private var adding = false

    var body: some View {
        let categories = store.snapshot.accountRecords.filter { $0.kind.isCategory }
        List {
            ForEach([AccountKind.expense, .income], id: \.self) { kind in
                Section(kind == .expense ? "Spending" : "Income") {
                    ForEach(categories.filter { $0.kind == kind }, id: \.id) { c in
                        Button { editing = c } label: {
                            ListRow(title: c.name, caption: c.archived ? "Archived" : c.group, symbol: c.icon, color: Color(hex: c.colorHex)) {
                                EmptyView()
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { CategoryEditor(editing: $0) }
        .sheet(isPresented: $adding) { CategoryEditor() }
    }
}

struct AuditListView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        List(store.auditTrail, id: \.id) { a in
            VStack(alignment: .leading, spacing: 2) {
                Text(a.summary).font(.subheadline)
                if let reason = a.reason { Text("Reason: \(reason)").font(.caption).foregroundStyle(.secondary) }
                Text(a.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .overlay { if store.auditTrail.isEmpty { ContentUnavailableView("No changes yet", systemImage: "clock") } }
        .navigationTitle("Change history")
    }
}
