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
import NokaelCore

/// The import screen; reading, matching and adding are in StatementReview
struct ImportStatementView: View {
    @Environment(LedgerStore.self) private var store
    let accountId: UUID

    var body: some View {
        ImportStatementScreen(review: StatementReview(accountId: accountId, store: store))
    }
}

private struct ImportStatementScreen: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var review: StatementReview
    @State private var choosingFile = false

    init(review: StatementReview) {
        _review = State(initialValue: review)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let added = review.added {
                    ContentUnavailableView {
                        Label(added == 0 ? "Nothing new to add" : "Added \(added) \(added == 1 ? "entry" : "entries")",
                              systemImage: "checkmark.circle")
                    } description: {
                        Text("Check the balance against your statement to be sure everything's in.")
                    } actions: {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else if review.fileText == nil {
                    intro
                } else {
                    rowsList
                }
            }
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(review.added == nil ? "Cancel" : "Close") { dismiss() } }
            }
            #if DEBUG
            .onAppear { if review.fileText == nil { debugLoad() } }
            #endif
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): review.load(url)
                case .failure: review.error = "Couldn't open that file."
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
                    Text("Bring in \(review.account?.name ?? "this account")'s statement").font(.title3.bold())
                    Text("Download a statement from your bank's website or app as a CSV file, then choose it here. Rows you've already recorded are recognised and left alone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Button { choosingFile = true } label: { Label("Choose CSV file", systemImage: "folder") }
                    .accessibilityIdentifier("chooseStatement")
            } footer: {
                Text("The file needs a header row with a date, a description and either an amount or separate money in and money out columns. It stays on this iPhone.")
            }
            if let error = review.error { Section { FieldError(message: error) } }
        }
    }

    @ViewBuilder private var rowsList: some View {
        List {
            Section {
                LabeledContent("File", value: review.fileName)
                LabeledContent("Rows", value: "\(review.rows.count)")
                LabeledContent("Already recorded", value: "\(review.matched.count)")
                Toggle("Purchases show as positive numbers", isOn: $review.flipSigns)
            } footer: {
                Text("Card statements often list purchases without a minus sign. Turn this on if money out appears as money in below.")
            }

            if let error = review.error { Section { FieldError(message: error) } }

            if review.suggesting > 0 {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suggesting categories… \(review.suggesting) to go").foregroundStyle(.secondary)
                    }
                }
            } else if !review.unsorted.isEmpty { sortTheRest }

            Section {
                if review.inbox.isEmpty {
                    Text("Everything in this file is already recorded.").foregroundStyle(.secondary)
                }
                ForEach(review.inbox) { row in
                    InboxRow(row: row, target: binding(row), skipped: skipBinding(row), options: review.options(for: row),
                             label: review.label(for: row))
                }
            } header: {
                HStack {
                    Text("To add · \(review.inbox.count)")
                    Spacer()
                    if !review.inbox.isEmpty {
                        Button(review.allSelected ? "Untick all" : "Tick all") { review.toggleAll() }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .accessibilityIdentifier("importSelectAll")
                    }
                }
            } footer: {
                if !review.inbox.isEmpty {
                    Text("Categories are suggested for you; tap one to change it. Untick a row to leave it out.")
                }
            }

            if !review.matched.isEmpty {
                Section("Already recorded · \(review.matched.count)") {
                    DisclosureGroup("Show") {
                        ForEach(review.rows.filter { review.matched[$0.id] != nil }) { row in
                            ListRow(title: row.description, caption: row.date.formatted(date: .abbreviated, time: .omitted),
                                    symbol: "checkmark.circle.fill", color: .green) {
                                Text(row.amount.signed).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if !review.inbox.isEmpty { addBar } }
    }

    /// One choice for every ticked row that has none yet
    private var sortTheRest: some View {
        let out = review.unsorted.filter(\.amount.isNegative)
        let into = review.unsorted.filter { !$0.amount.isNegative }
        return Section {
            if !out.isEmpty {
                bulkMenu("Put \(out.count) money-out \(out.count == 1 ? "row" : "rows") in…",
                         categories: store.snapshot.expenseCategories, rows: out)
            }
            if !into.isEmpty {
                bulkMenu("Put \(into.count) money-in \(into.count == 1 ? "row" : "rows") in…",
                         categories: store.snapshot.incomeCategories, rows: into)
            }
        } header: {
            Text("\(review.unsorted.count) still need a category")
        } footer: {
            Text("Sorts all of them at once. You can still change any single row below.")
        }
    }

    private func bulkMenu(_ title: String, categories: [LedgerAccountRecord], rows: [StatementRow]) -> some View {
        Menu {
            ForEach(categories, id: \.id) { c in
                Button { review.put(rows, in: c.id) } label: { Label(c.name, systemImage: c.icon) }
            }
        } label: {
            Label(title, systemImage: "square.stack.3d.down.right")
        }
    }

    private var addBar: some View {
        VStack(spacing: 6) {
            Text(review.summary).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: review.add) {
                Text(review.ready.isEmpty ? "Choose a category to add" : "Add \(review.ready.count) \(review.ready.count == 1 ? "entry" : "entries")")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(review.ready.isEmpty)
            .accessibilityIdentifier("addImported")
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
    }

    #if DEBUG
    /// Screenshot helper: -importSample /path/to/statement.csv
    func debugLoad() {
        if let path = UserDefaults.standard.string(forKey: "importSample") { review.load(URL(fileURLWithPath: path)) }
    }
    #endif

    private func binding(_ row: StatementRow) -> Binding<LedgerStore.ImportedRow.Target?> {
        Binding(get: { review.targets[row.id] }, set: { review.targets[row.id] = $0 })
    }

    private func skipBinding(_ row: StatementRow) -> Binding<Bool> {
        Binding(get: { review.skipped.contains(row.id) }, set: { if $0 { review.skipped.insert(row.id) } else { review.skipped.remove(row.id) } })
    }
}

/// One statement row waiting for a decision
private struct InboxRow: View {
    let row: StatementRow
    @Binding var target: LedgerStore.ImportedRow.Target?
    @Binding var skipped: Bool
    let options: [(String, [StatementReview.Option])]
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
