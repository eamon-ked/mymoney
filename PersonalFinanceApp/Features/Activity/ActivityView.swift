//
//  ActivityView.swift
//  Nokael Money
//
//  Every money movement, searchable and grouped by date. Scheduled bills and
//  expected income are a separate filter, clearly marked as not yet happened.
//

import SwiftUI
import NokaelCore

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All", review = "To review", expenses = "Expenses", income = "Income", transfers = "Transfers", scheduled = "Scheduled"
    var id: String { rawValue }
}

struct ActivityView: View {
    @Environment(LedgerStore.self) private var store
    @State private var filter: ActivityFilter = .all
    @State private var search = ""
    @State private var selected: EntryRecord?
    @State private var paying: Occurrence?

    private var snapshot: FinanceSnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterChips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    if filter != .scheduled && !days.isEmpty {
                        Text("Tap an entry to change or delete it.")
                    }
                }

                if filter == .scheduled {
                    scheduledSection
                } else if days.isEmpty {
                    Section {
                        if snapshot.entries().isEmpty {
                            EmptyStateView(symbol: "list.bullet.rectangle", title: "Nothing here yet",
                                           message: "Add what you spend and receive. Balances, budget and safe-to-spend update on their own.")
                        } else {
                            Text("Nothing matches \"\(search)\"").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(days, id: \.day) { group in
                        Section {
                            ForEach(group.entries, id: \.id) { record in
                                Button { selected = record } label: { EntryRow(record: record, snapshot: snapshot) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text(dayTitle(group.day))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search descriptions, categories, accounts")
            .navigationTitle("Activity")
            .toolbar { GlobalAddButton() }
            .sheet(item: $selected) { EntryDetailView(record: $0) }
            .sheet(item: $paying) { PayScheduledSheet(occurrence: $0) }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases.filter { $0 != .review || filter == .review || snapshot.entries().contains(where: \.needsReview) }) { f in
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(filter == f ? Palette.activity : Color.gray.opacity(0.15)))
                            .foregroundStyle(filter == f ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var filtered: [EntryRecord] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return snapshot.entries().filter { record in
            let kindMatches: Bool = switch filter {
            case .all, .scheduled: true
            case .review: record.needsReview
            case .expenses: record.kind == .expense || record.kind == .debtPayment
            case .income: record.kind == .income
            case .transfers: record.kind == .transfer
            }
            guard kindMatches else { return false }
            guard !needle.isEmpty else { return true }
            let names = record.lines.compactMap { snapshot.account($0.accountId)?.name.lowercased() }
            return record.memo.lowercased().contains(needle) || record.notes.lowercased().contains(needle)
                || names.contains { $0.contains(needle) }
        }
    }

    private var days: [(day: Date, entries: [EntryRecord])] {
        let cal = snapshot.calendar
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    @ViewBuilder private var scheduledSection: some View {
        let upcoming = snapshot.occurrences.filter { !$0.skipped && !$0.remaining.isZero }
        if upcoming.isEmpty {
            Section {
                EmptyStateView(symbol: "calendar", title: "Nothing scheduled",
                               message: "Bills and expected income you add in Plan show up here until they happen.")
            }
        } else {
            Section {
                ForEach(upcoming) { occ in
                    Button { paying = occ } label: { OccurrenceRow(occurrence: occ, snapshot: snapshot) }
                        .buttonStyle(.plain)
                }
            } footer: {
                Text("Scheduled items haven't happened yet. They don't change any balance until you mark them paid or received.")
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = snapshot.calendar
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// One posted entry: description, category and account, and the signed amount
struct EntryRow: View {
    let record: EntryRecord
    let snapshot: FinanceSnapshot
    /// Inside one account, show the change to that account
    var accountId: UUID? = nil

    var body: some View {
        let entry = record.entry
        let category = entry.lines.compactMap { snapshot.account($0.accountId) }.first { $0.kind.isCategory }
        let sheet = entry.lines.compactMap { line in snapshot.account(line.accountId).map { (record: $0, amount: line.amount) } }
            .filter { $0.record.kind.isBalanceSheet }
        ListRow(title: record.memo.isEmpty ? (category?.name ?? "Entry") : record.memo,
                caption: caption(category: category, sheet: sheet.map(\.record)),
                symbol: symbol(category ?? debt(sheet)),
                color: (category ?? debt(sheet)).map { Color(hex: $0.colorHex) } ?? kindColor) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText(entry, sheet: sheet))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor(entry, sheet: sheet))
                    .strikethrough(record.status == .void)
                if record.status == .void {
                    StatusBadge(text: "Deleted")
                } else if record.needsReview {
                    StatusBadge(text: "New", color: .orange)
                } else if record.cleared == .reconciled {
                    Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Reconciled")
                }
            }
        }
    }

    /// A card or loan payment has no category, so it takes the debt's look
    private func debt(_ sheet: [(record: LedgerAccountRecord, amount: Money)]) -> LedgerAccountRecord? {
        record.kind == .transfer ? nil : sheet.map(\.record).first { $0.kind.isLiability }
    }

    private var kindColor: Color {
        switch record.kind {
        case .transfer: return .blue
        case .adjustment, .reconciliation, .openingBalance: return .gray
        case .income: return .green
        default: return .gray
        }
    }

    private func symbol(_ category: LedgerAccountRecord?) -> String {
        switch record.kind {
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment, .reconciliation: return "slider.horizontal.3"
        case .openingBalance: return "flag.fill"
        default: return category?.icon.isEmpty == false ? category!.icon : "tag.fill"
        }
    }

    private func caption(category: LedgerAccountRecord?, sheet: [LedgerAccountRecord]) -> String {
        if record.kind == .transfer, sheet.count == 2 {
            let entry = record.entry
            let from = sheet.first { r in entry.amount(on: r.id)?.isNegative == true }?.name ?? ""
            let to = sheet.first { r in entry.amount(on: r.id)?.isPositive == true }?.name ?? ""
            return "\(from) → \(to)"
        }
        var parts: [String] = []
        if record.kind == .debtPayment, let interest = category.flatMap({ record.entry.amount(on: $0.id) }) {
            // The whole payment is the row's amount; say how much of it was interest
            parts.append("\(interest.compact) interest")
            parts.append(contentsOf: sheet.filter { !$0.kind.isLiability }.map(\.name))
            return parts.joined(separator: " · ")
        }
        if let category, record.memo != category.name { parts.append(category.name) }
        parts.append(contentsOf: sheet.map(\.name))
        if record.kind == .adjustment || record.kind == .reconciliation { parts.append("Correction") }
        return parts.joined(separator: " · ")
    }

    private func change(_ entry: Entry, sheet: [(record: LedgerAccountRecord, amount: Money)]) -> Money? {
        if let accountId { return entry.amount(on: accountId) }
        switch record.kind {
        case .transfer: return nil
        // What left the paying account, not what's left after paying the loan down
        case .debtPayment: return sheet.filter { $0.record.kind.isAsset }.map(\.amount).sum(snapshot.currency)
        default: return sheet.map(\.amount).sum(snapshot.currency)
        }
    }

    private func amountText(_ entry: Entry, sheet: [(record: LedgerAccountRecord, amount: Money)]) -> String {
        if let c = change(entry, sheet: sheet) { return c.signed }
        return (sheet.first { $0.amount.isPositive }?.amount ?? .zero(snapshot.currency)).compact
    }

    private func amountColor(_ entry: Entry, sheet: [(record: LedgerAccountRecord, amount: Money)]) -> Color {
        guard let c = change(entry, sheet: sheet) else { return .secondary }
        return c.isPositive ? .green : .primary
    }
}

struct OccurrenceRow: View {
    let occurrence: Occurrence
    let snapshot: FinanceSnapshot

    var body: some View {
        let item = snapshot.item(for: occurrence)
        let state = snapshot.state(of: occurrence)
        ListRow(title: item?.name ?? "Scheduled",
                caption: caption(item),
                symbol: item?.direction == .inflow ? "arrow.down.circle.fill" : "calendar.badge.clock",
                color: state == .overdue ? .red : (item?.direction == .inflow ? .green : Palette.plan)) {
            VStack(alignment: .trailing, spacing: 3) {
                Text((item?.direction == .inflow ? "+" : "") + occurrence.remaining.compact)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                OccurrenceBadge(state: state, isEstimate: occurrence.isEstimate)
            }
        }
    }

    private func caption(_ item: PlannedItem?) -> String {
        var parts = [occurrence.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))]
        if let account = snapshot.account(item?.accountId) { parts.append(account.name) }
        if occurrence.paid.isPositive { parts.append("\(occurrence.paid.compact) paid") }
        return parts.joined(separator: " · ")
    }
}

struct OccurrenceBadge: View {
    let state: OccurrenceState
    var isEstimate = false

    var body: some View {
        switch state {
        case .overdue: StatusBadge(text: "Overdue", color: .red)
        case .dueToday: StatusBadge(text: "Due today", color: .orange)
        case .partiallyPaid: StatusBadge(text: "Part paid", color: .orange)
        case .paid: StatusBadge(text: "Paid", color: .green)
        case .skipped: StatusBadge(text: "Skipped")
        case .scheduled: StatusBadge(text: isEstimate ? "Estimate" : "Scheduled", color: isEstimate ? .orange : .secondary)
        }
    }
}
