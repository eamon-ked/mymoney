//
//  SettingsView.swift
//  Nokael Money
//

import SwiftUI
import NokaelCore

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        let settings = store.settings
        NavigationStack {
            Form {
                Section("Money") {
                    LabeledContent("Currency", value: settings.currency)
                    Picker("Week starts on", selection: binding(\.firstWeekday)) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Saturday").tag(7)
                    }
                    Stepper("Balances count as out of date after \(settings.staleAfterDays) days",
                            value: binding(\.staleAfterDays), in: 7...90, step: 7)
                    NavigationLink("Categories") { CategoryListView() }
                }

                Section {
                    Toggle("Lock with Face ID", isOn: binding(\.biometricLock))
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Asks for Face ID or your passcode when the app opens.")
                }

                AppleIntelligenceSection()

                BackupSection()

                Section {
                    Button { export() } label: { Label("Export all entries (CSV)", systemImage: "square.and.arrow.up") }
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share export", systemImage: "doc.text") }
                    }
                    NavigationLink("Change history") { AuditListView() }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("A spreadsheet of every entry, for your own records. To move or recover your data, use a backup.")
                }

                Section {
                    Button("Delete all data on this iPhone", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Removes every account, entry, budget and bill from this device. Without a backup, this can't be undone.")
                }

                if let error { Section { FieldError(message: error) } }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    do { try store.eraseAllData(); dismiss() } catch { self.error = StoreError.from(error).errorDescription }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<SettingsRecord, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: path] },
                set: { value in try? store.updateSettings { $0[keyPath: path] = value } })
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
