//
//  ImportStatementView.swift
//  Nokael Money
//
//  Bring in a bank or card statement saved as CSV. Rows already recorded are
//  set aside; the rest wait in an inbox to be given a category, a transfer or
//  the bill they pay, then are added in one go. Importing the same statement
//  again only offers what's still missing.
//

import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import NokaelCore

struct ImportStatementView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let accountId: UUID

    @State private var fileText: String?
    @State private var fileName = ""
    @State private var choosingFile = false
    @State private var flipSigns = false
    @State private var rows: [StatementRow] = []
    @State private var matched: [Int: UUID] = [:]
    @State private var targets: [Int: LedgerStore.ImportedRow.Target] = [:]
    @State private var skipped: Set<Int> = []
    @State private var error: String?
    @State private var added: Int?

    private var snapshot: FinanceSnapshot { store.snapshot }
    private var account: LedgerAccountRecord? { snapshot.account(accountId) }
    private var inbox: [StatementRow] { rows.filter { matched[$0.id] == nil } }
    private var ready: [StatementRow] { inbox.filter { !skipped.contains($0.id) && targets[$0.id] != nil } }
    private var unsorted: [StatementRow] { inbox.filter { !skipped.contains($0.id) && targets[$0.id] == nil } }
    private var allSelected: Bool { inbox.allSatisfy { !skipped.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Group {
                if let added {
                    ContentUnavailableView {
                        Label(added == 0 ? "Nothing new to add" : "Added \(added) \(added == 1 ? "entry" : "entries")",
                              systemImage: "checkmark.circle")
                    } description: {
                        Text("Check the balance against your statement to be sure everything's in.")
                    } actions: {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else if fileText == nil {
                    intro
                } else {
                    review
                }
            }
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(added == nil ? "Cancel" : "Close") { dismiss() } }
            }
            #if DEBUG
            .onAppear { if fileText == nil { debugLoad() } }
            #endif
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure: error = "Couldn't open that file."
                }
            }
        }
    }

    // MARK: - Steps

    private var intro: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(Palette.home)
                    Text("Bring in \(account?.name ?? "this account")'s statement").font(.title3.bold())
                    Text("Download a statement from your bank's website or app as a CSV file, then choose it here. Rows you've already recorded are recognised and left alone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Button { choosingFile = true } label: { Label("Choose CSV file", systemImage: "folder") }
                    .accessibilityIdentifier("chooseStatement")
            } footer: {
                Text("The file needs a header row with a date, a description and either an amount or separate money in and money out columns. It stays on this iPhone.")
            }
            if let error { Section { FieldError(message: error) } }
        }
    }

    @ViewBuilder private var review: some View {
        List {
            Section {
                LabeledContent("File", value: fileName)
                LabeledContent("Rows", value: "\(rows.count)")
                LabeledContent("Already recorded", value: "\(matched.count)")
                Toggle("Purchases show as positive numbers", isOn: $flipSigns)
            } footer: {
                Text("Card statements often list purchases without a minus sign. Turn this on if money out appears as money in below.")
            }

            if let error { Section { FieldError(message: error) } }

            if !unsorted.isEmpty { sortTheRest }

            Section {
                if inbox.isEmpty {
                    Text("Everything in this file is already recorded.").foregroundStyle(.secondary)
                }
                ForEach(inbox) { row in
                    InboxRow(row: row, target: binding(row), skipped: skipBinding(row), options: options(for: row),
                             label: label(for: targets[row.id]))
                }
            } header: {
                HStack {
                    Text("To add · \(inbox.count)")
                    Spacer()
                    if !inbox.isEmpty {
                        Button(allSelected ? "Untick all" : "Tick all") {
                            skipped = allSelected ? Set(inbox.map(\.id)) : []
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .accessibilityIdentifier("importSelectAll")
                    }
                }
            } footer: {
                if !inbox.isEmpty {
                    Text("Ticked rows are added once they have a category. Untick a row to leave it out.")
                }
            }

            if !matched.isEmpty {
                Section("Already recorded · \(matched.count)") {
                    DisclosureGroup("Show") {
                        ForEach(rows.filter { matched[$0.id] != nil }) { row in
                            ListRow(title: row.description, caption: row.date.formatted(date: .abbreviated, time: .omitted),
                                    symbol: "checkmark.circle.fill", color: .green) {
                                Text(row.amount.signed).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: flipSigns) { _, _ in parse() }
        .safeAreaInset(edge: .bottom) { if !inbox.isEmpty { addBar } }
    }

    /// One choice for every ticked row that has none yet
    private var sortTheRest: some View {
        let out = unsorted.filter(\.amount.isNegative)
        let into = unsorted.filter { !$0.amount.isNegative }
        return Section {
            if !out.isEmpty {
                bulkMenu("Put \(out.count) money-out \(out.count == 1 ? "row" : "rows") in…",
                         categories: snapshot.expenseCategories, rows: out)
            }
            if !into.isEmpty {
                bulkMenu("Put \(into.count) money-in \(into.count == 1 ? "row" : "rows") in…",
                         categories: snapshot.incomeCategories, rows: into)
            }
        } header: {
            Text("\(unsorted.count) still need a category")
        } footer: {
            Text("Sorts all of them at once. You can still change any single row below.")
        }
    }

    private func bulkMenu(_ title: String, categories: [LedgerAccountRecord], rows: [StatementRow]) -> some View {
        Menu {
            ForEach(categories, id: \.id) { c in
                Button { for row in rows { targets[row.id] = .category(c.id) } } label: { Label(c.name, systemImage: c.icon) }
            }
        } label: {
            Label(title, systemImage: "square.stack.3d.down.right")
        }
    }

    private var addBar: some View {
        VStack(spacing: 6) {
            Text(summary).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: add) {
                Text(ready.isEmpty ? "Choose a category to add" : "Add \(ready.count) \(ready.count == 1 ? "entry" : "entries")")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(ready.isEmpty)
            .accessibilityIdentifier("addImported")
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
    }

    private var summary: String {
        let left = inbox.count - ready.count - unsorted.count
        var parts = ["\(ready.count) ready"]
        if !unsorted.isEmpty { parts.append("\(unsorted.count) need a category") }
        if left > 0 { parts.append("\(left) left out") }
        return parts.joined(separator: " · ")
    }

    #if DEBUG
    /// Screenshot helper: -importSample /path/to/statement.csv
    func debugLoad() {
        if let path = UserDefaults.standard.string(forKey: "importSample") { load(URL(fileURLWithPath: path)) }
    }
    #endif

    // MARK: - Reading

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            error = "Couldn't read that file."
            return
        }
        fileName = url.lastPathComponent
        fileText = text
        // Card statements usually list purchases as positive numbers
        if account?.kind.isLiability == true,
           let raw = try? StatementImport.read(text, currency: store.currency, calendar: store.calendar) {
            flipSigns = raw.filter(\.amount.isPositive).count > raw.count / 2
        }
        parse()
    }

    private func parse() {
        guard let fileText else { return }
        do {
            rows = try StatementImport.read(fileText, currency: store.currency, flipSigns: flipSigns, calendar: store.calendar)
            error = nil
        } catch {
            rows = []
            matched = [:]
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
            self.fileText = nil
            return
        }
        let recorded = snapshot.entries(touching: accountId).filter { $0.kind != .openingBalance }.map { record in
            RecordedMovement(entryId: record.id, date: record.date,
                             amount: record.lines.filter { $0.accountId == accountId }
                                .map { Money(minorUnits: $0.minorUnits, currency: $0.currency) }.sum(store.currency))
        }
        matched = StatementImport.match(rows, with: recorded, calendar: store.calendar)
        suggest()
    }

    /// A bill it pays, else a transfer naming another account, else the category used last time for that shop
    private func suggest() {
        let history: [(memo: String, categoryId: UUID)] = snapshot.entries().compactMap { record in
            guard let c = record.lines.lazy.compactMap({ snapshot.account($0.accountId) }).first(where: { $0.kind.isCategory })
            else { return nil }
            return (record.memo, c.id)
        }
        let others = snapshot.accounts.filter { $0.id != accountId }.map { (id: $0.id, name: $0.name) }
        var next: [Int: LedgerStore.ImportedRow.Target] = [:]
        var billsTaken: Set<UUID> = []
        for row in inbox {
            if let occ = StatementImport.bill(for: row, occurrences: snapshot.occurrences, items: snapshot.items,
                                              accountId: accountId, calendar: store.calendar),
               !billsTaken.contains(occ.id) {
                billsTaken.insert(occ.id)
                next[row.id] = .bill(occ.id)
            } else if let id = StatementImport.account(for: row.description, accounts: others) {
                next[row.id] = .transfer(id)
            } else if let id = StatementImport.category(for: row.description, history: history),
                      let c = snapshot.account(id), c.kind == (row.amount.isNegative ? .expense : .income), !c.archived {
                next[row.id] = .category(id)
            }
        }
        targets = next
    }

    // MARK: - Choices

    struct Option: Identifiable {
        let target: LedgerStore.ImportedRow.Target
        let title: String
        let symbol: String
        var id: LedgerStore.ImportedRow.Target { target }
    }

    private func options(for row: StatementRow) -> [(String, [Option])] {
        let out = row.amount.isNegative
        var groups: [(String, [Option])] = []
        if out {
            let bills = snapshot.upcomingBills(days: 45).filter { occ in
                snapshot.item(for: occ).map { $0.accountId == nil || $0.accountId == accountId } ?? false
            }
            if !bills.isEmpty {
                groups.append(("Pays a bill", bills.compactMap { occ in
                    snapshot.item(for: occ).map {
                        Option(target: .bill(occ.id),
                               title: "\($0.name) · \(occ.dueDate.formatted(.dateTime.day().month(.abbreviated)))", symbol: "calendar")
                    }
                }))
            }
        }
        let categories = out ? snapshot.expenseCategories : snapshot.incomeCategories
        groups.append((out ? "Spending" : "Income", categories.map { Option(target: .category($0.id), title: $0.name, symbol: $0.icon) }))
        let others = snapshot.accounts.filter { $0.id != accountId }
        if !others.isEmpty {
            groups.append((out ? "Moved to" : "Moved from", others.map {
                Option(target: .transfer($0.id), title: $0.name, symbol: $0.icon)
            }))
        }
        return groups
    }

    private func label(for target: LedgerStore.ImportedRow.Target?) -> String? {
        switch target {
        case .category(let id): return snapshot.account(id)?.name
        case .transfer(let id): return snapshot.account(id).map { "Transfer · \($0.name)" }
        case .bill(let occId):
            return snapshot.occurrences.first { $0.id == occId }.flatMap(snapshot.item(for:)).map { "Pays \($0.name)" }
        case nil: return nil
        }
    }

    private func binding(_ row: StatementRow) -> Binding<LedgerStore.ImportedRow.Target?> {
        Binding(get: { targets[row.id] }, set: { targets[row.id] = $0 })
    }

    private func skipBinding(_ row: StatementRow) -> Binding<Bool> {
        Binding(get: { skipped.contains(row.id) }, set: { if $0 { skipped.insert(row.id) } else { skipped.remove(row.id) } })
    }

    // MARK: - Adding

    private func add() {
        let picks = ready.compactMap { row -> LedgerStore.ImportedRow? in
            guard let target = targets[row.id] else { return nil }
            return LedgerStore.ImportedRow(date: row.date, memo: row.description, amount: row.amount, target: target,
                                           key: key(for: row))
        }
        do {
            added = try store.importRows(picks, into: accountId)
        } catch {
            self.error = StoreError.from(error).errorDescription
        }
    }

    /// The same row of the same statement always gets the same key, so a
    /// double tap or a second import can't add it twice
    private func key(for row: StatementRow) -> UUID {
        let twins = rows.filter { $0.date == row.date && $0.amount == row.amount && $0.description == row.description }
        let ordinal = twins.firstIndex { $0.id == row.id } ?? 0
        let text = "\(accountId)|\(row.date.timeIntervalSince1970)|\(row.amount.minorUnits)|\(row.description)|\(ordinal)"
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// One statement row waiting for a decision
private struct InboxRow: View {
    let row: StatementRow
    @Binding var target: LedgerStore.ImportedRow.Target?
    @Binding var skipped: Bool
    let options: [(String, [ImportStatementView.Option])]
    let label: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { skipped.toggle() } label: {
                Image(systemName: skipped ? "square" : "checkmark.square.fill")
                    .font(.title2)
                    .foregroundStyle(skipped ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.description)
            .accessibilityValue(skipped ? "Not ticked" : "Ticked")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.description.isEmpty ? "No description" : row.description).lineLimit(2)
                        .strikethrough(skipped)
                    Spacer(minLength: 8)
                    Text(row.amount.signed).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(row.amount.isNegative ? Color.primary : Palette.positive)
                }
                Text(row.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                if skipped {
                    Text("Left out · tick to add it").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(options, id: \.0) { group in
                            Section(group.0) {
                                ForEach(group.1) { option in
                                    Button { target = option.target } label: {
                                        Label(option.title, systemImage: option.symbol)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(label ?? "Choose a category", systemImage: label == nil ? "exclamationmark.circle.fill" : "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(label == nil ? Color.orange : Color.accentColor)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill((label == nil ? Color.orange : Color.accentColor).opacity(0.15)))
                    }
                }
            }
        }
        .opacity(skipped ? 0.45 : 1)
    }
}
