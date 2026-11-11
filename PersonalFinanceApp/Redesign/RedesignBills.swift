//
//  RedesignBills.swift
//  Nokael Money
//
//  A bill's page: recording or linking its payment, part payments, skipping
//  one, and its reminder. Adding and editing bills and expected income, and
//  the list of every regular one.
//

import SwiftUI
import NokaelCore

extension Redesign {
    struct BillPage: View {
        let bill: Bill
        @Environment(AppModel.self) private var app
        /// A deliberate look at the amount before recording it; it lasts only while this bill is open
        @State private var revealed = false
        @State private var recording = false
        @State private var key = UUID()
        @State private var amount = ""
        @State private var accountId: UUID?
        @State private var categoryId: UUID?
        @State private var date = Date()
        @State private var problem: String?
        @State private var confirmUnlink: UUID?

        var body: some View {
            let matches = app.matches(for: bill)
            HStack(spacing: 12) {
                IconBox(symbol: bill.isIncome ? "arrow.down.left" : bill.debtId != nil ? "creditcard" : "doc.text")
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name(of: bill)).rdText(.cardTitle)
                    Text("\(bill.isIncome ? "Expected" : "Due") \(app.fullDay(bill.due))").rdText(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 24)
            HStack(spacing: 4) {
                app.amount(bill.amount, revealed: revealed).rdText(.display)
                if app.hidesAmounts && bill.isOpen {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye" : "eye.slash").font(.system(size: 15))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel(revealed ? "Hide amount" : "Show amount")
                }
            }
            .frame(minHeight: 44)
            .padding(.bottom, 8)
            HStack(spacing: 8) {
                StatusPill(bill: bill, today: app.today)
                if bill.status == .partial { Text(private: "\(app.money(bill.paid)) paid of \(app.money(bill.expected))").rdText(.caption).foregroundStyle(Theme.muted) }
            }

            DetailCard {
                DetailRow(label: "Account", value: app.accountLabel(bill.accountId))
                DetailRow(label: "Frequency", value: bill.recurring)
                DetailRow(label: "Category", value: app.hidesDetails ? "Hidden" : bill.category)
                if bill.isEstimate { DetailRow(label: "Amount", value: "Estimate, it can vary") }
                if !bill.isIncome { DetailRow(label: "Reminder", value: reminderText) }
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("Payment history").rdText(.detailStrong)
                if bill.paidEntryIds.isEmpty {
                    Redesign.footnote(bill.status == .skipped ? "Skipped. It isn't held back from safe to spend."
                                      : "No payment linked yet.")
                } else {
                    ForEach(bill.paidEntryIds, id: \.self) { id in
                        if let t = app.transaction(id) {
                            TransactionRow(t: t)
                            Button("Unlink this payment") { confirmUnlink = id }
                                .rdText(.caption).foregroundStyle(Theme.primary)
                        }
                    }
                }
            }
            .padding(.vertical, 20).padding(.horizontal, 4)
            .confirmationDialog("Unlink this payment?", isPresented: Binding(get: { confirmUnlink != nil }, set: { if !$0 { confirmUnlink = nil } }),
                                titleVisibility: .visible) {
                Button("Unlink", role: .destructive) {
                    if let id = confirmUnlink { problem = app.attempt("Unlinked. The bill counts as unpaid again.", closing: false) { try app.store.unlink(entryId: id) } }
                }
            } message: { Text("The payment stays in Activity. The bill goes back to unpaid.") }

            if bill.isOpen {
                VStack(spacing: 12) {
                    if !matches.isEmpty && !bill.isIncome || (!matches.isEmpty && bill.isIncome) {
                        Button { app.open(.link(bill.id)) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "link").foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("An existing payment may match").rdText(.detailStrong)
                                    Text("Link it instead of recording it twice.").rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .padding(16)
                            .background(Theme.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.primary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                    if recording { paymentForm }
                    Button(action: record) {
                        Label(recording ? "Save payment" : bill.isIncome ? "Record It Arrived" : "Record Payment", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { app.open(.link(bill.id)) } label: { Label("Link Existing Payment", systemImage: "link") }
                        .buttonStyle(QuietButtonStyle())
                    if !bill.isIncome {
                        Button(action: remind) { Label("Set Reminder", systemImage: "bell") }.buttonStyle(QuietButtonStyle())
                    }
                    Button("Skip this one") {
                        problem = app.attempt("Skipped. It's no longer held back.", closing: false) { try app.store.skip(occurrenceId: bill.id) }
                    }
                    .rdText(.label).foregroundStyle(Theme.primary).frame(minHeight: 44)
                    Problem(text: problem)
                    Redesign.footnote("Record payments you've already made.\nThis does not send money from your bank.")
                        .multilineTextAlignment(.center).padding(.top, 6)
                }
            } else if bill.status == .skipped {
                Button("Undo skip") {
                    problem = app.attempt("It counts again.", closing: false) { try app.store.unskip(occurrenceId: bill.id) }
                }
                .buttonStyle(QuietButtonStyle())
            }
            Button { app.open(.editBill(bill.itemId)) } label: { Label("Change amount, date or stop", systemImage: "pencil") }
                .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44).padding(.top, 8)
        }

        private var reminderText: String {
            guard Notifications.isOn(.bills) else { return "Off" }
            let days = app.snapshot.reminderDays(for: bill.itemId)
            return Notifications.choices.first { $0.days == days }?.label ?? "\(days) days before"
        }

        @ViewBuilder private var paymentForm: some View {
            VStack(alignment: .leading, spacing: 12) {
                AmountBox(label: "Amount paid in \(app.currency)", text: $amount, autofocus: false)
                AccountChoice(label: bill.isIncome ? "Paid into" : "Paid from", selection: $accountId, accounts: app.accounts.filter { $0.kind != .lent })
                if !bill.isIncome {
                    CategoryChoice(label: "Category", selection: $categoryId, categories: app.expenseChoices(), allowsNone: true)
                }
                Field(label: "Date") { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }
                Redesign.footnote("Less than the bill leaves the rest still due.")
            }
        }

        private func record() {
            // A bill for a card or loan is paid with the interest split off
            if let debt = bill.debtId { app.open(.payDebt(debt, occurrence: bill.id)); return }
            guard recording else {
                recording = true
                amount = MoneyFormat.editable(app.money(from: bill.amount))
                accountId = bill.accountId ?? app.store.settings.lastUsedAccountId ?? app.moneyAccounts.first?.id
                categoryId = bill.categoryId
                date = min(Date(), max(bill.due, app.today))
                return
            }
            guard let value = app.parse(amount), value.isPositive else { problem = "Enter the amount paid."; return }
            problem = app.pay(bill, amount: value, from: accountId, category: categoryId, on: date, key: key)
        }

        private func remind() {
            Task {
                let allowed = await Notifications.permission() == .authorized
                if !Notifications.isOn(.bills) || !allowed {
                    guard await Notifications.requestPermission() else {
                        app.toast = Toast(message: "Notifications are off for Nokael Money. Turn them on in the iPhone's Settings.", isError: true)
                        return
                    }
                    UserDefaults.standard.set(true, forKey: Notifications.Group.bills.key)
                }
                await Notifications.sync(app.snapshot)
                app.toast = Toast(message: "Reminders are on. You'll hear about this one \(reminderText.lowercased()).")
            }
        }
    }

    struct LinkPayment: View {
        let bill: Bill
        @Environment(AppModel.self) private var app

        var body: some View {
            let matches = app.matches(for: bill)
            Text(private: "Choose the payment for \(app.money(bill.amount)). Your cash won't change and no duplicate will be created.")
                .rdText(.body).foregroundStyle(Theme.muted).lineSpacing(3).padding(.bottom, 20)
            VStack(spacing: 12) {
                ForEach(matches) { t in
                    Button { app.link(bill, with: t) } label: {
                        HStack(spacing: 12) {
                            IconBox(app.icon(of: t), small: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name(of: t)).rdText(.cardTitle)
                                Text("\(app.day(t.date)) · \(app.accountLabel(t.accountId))").rdText(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            app.amount(t.amount).rdText(.amount)
                            Image(systemName: "link").foregroundStyle(Theme.primary)
                        }
                        .rdPanel()
                    }
                    .buttonStyle(.plain)
                }
            }
            if matches.isEmpty {
                EmptyNote(text: "No unlinked payments near this date. Add the payment to Activity first, or record a new payment from the bill.")
            }
        }
    }

    /// "Is this your Rent payment?" from Home: link it, or say it isn't
    struct BillLinkPage: View {
        let occurrenceId: UUID
        @Environment(AppModel.self) private var app

        var body: some View {
            if let s = app.snapshot.billSuggestions.first(where: { $0.occurrence.id == occurrenceId }),
               let t = app.transaction(s.entry.id) {
                let name = app.hidesDetails ? "the bill" : s.item.name
                Text(s.isPartial ? "This looks like part of \(name). Linking it leaves the rest still due."
                     : "This looks like \(name). Linking marks the bill paid so it isn't held back or counted twice.")
                    .rdText(.body).foregroundStyle(Theme.muted).padding(.bottom, 16)
                TransactionRow(t: t).rdPanel(padding: 8)
                VStack(spacing: 12) {
                    Button("Link to \(name)") {
                        app.attempt("Payment linked.") { try app.store.match(occurrenceId: s.occurrence.id, entryId: s.entry.id) }
                            .map { app.toast = Toast(message: $0, isError: true) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Not this bill") {
                        app.attempt("Got it. It won't be suggested again.") { try app.store.dismissBillMatch(entryId: s.entry.id, occurrenceId: s.occurrence.id) }
                            .map { app.toast = Toast(message: $0, isError: true) }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 20)
            } else {
                EmptyNote(text: "Already sorted.")
            }
        }
    }

    /// Adds or edits a bill or expected income
    struct BillForm: View {
        let direction: Direction
        let editing: PlannedItem?
        @Environment(AppModel.self) private var app
        @State private var name = ""
        @State private var amount = ""
        @State private var estimate = false
        @State private var due = Date()
        @State private var loadedDue = Date()
        @State private var frequency: Frequency? = .monthly(every: 1)
        @State private var hasEnd = false
        @State private var end = Date()
        @State private var reminderDays = 2
        @State private var isTrial = false
        @State private var accountId: UUID?
        @State private var categoryId: UUID?
        @State private var problem: String?
        @State private var confirmStop = false

        private var income: Bool { direction == .inflow }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                AmountBox(label: "Amount in \(app.currency)", text: $amount, autofocus: editing == nil, identifier: "billAmount")
                ToggleRow(title: "The amount varies", detail: estimate ? "It's kept aside as an estimate until you record the real amount." : nil, isOn: $estimate)
                Field(label: income ? "What is it?" : "Bill name") {
                    TextField(income ? "e.g. Salary" : "e.g. Mobile plan", text: $name).accessibilityIdentifier("billName")
                }
                Field(label: editing == nil ? (income ? "Next expected" : "Next due") : "Next due") {
                    DatePicker("", selection: $due, displayedComponents: .date).labelsHidden()
                }
                .accessibilityIdentifier("billNextDue")
                Field(label: "How often") {
                    Choice(value: $frequency, options: Redesign.frequencies.map { Optional($0) } + [nil]) { $0?.label ?? "One time" }
                }
                if frequency != nil {
                    ToggleRow(title: "It ends", isOn: $hasEnd)
                    if hasEnd { Field(label: "Last one") { DatePicker("", selection: $end, in: due..., displayedComponents: .date).labelsHidden() } }
                }
                AccountChoice(label: income ? "Paid into" : "Paid from", selection: $accountId, accounts: app.accounts.filter { $0.kind != .lent })
                CategoryChoice(label: "Category", selection: $categoryId,
                               categories: income ? app.snapshot.incomeCategories.filter { !$0.archived } : app.expenseChoices(), allowsNone: true)
                if !income {
                    Field(label: "Remind me") {
                        Choice(value: $reminderDays, options: Notifications.choices.map(\.days)) { d in Notifications.choices.first { $0.days == d }?.label ?? "" }
                    }
                    .disabled(!Notifications.isOn(.bills))
                    if !Notifications.isOn(.bills) {
                        Redesign.footnote("Turn on Bills in More › Settings › Notifications to be reminded before bills are due.")
                    }
                    ToggleRow(title: "It's a free trial", detail: isTrial ? "You'll be reminded 2 days before the first charge, in time to cancel." : nil, isOn: $isTrial)
                }
                Problem(text: problem)
                Button(editing == nil ? (income ? "Add expected income" : "Add bill") : "Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("saveBill")
                if editing != nil {
                    Button(income ? "Stop expecting this" : "Stop this bill") { confirmStop = true }
                        .buttonStyle(QuietButtonStyle())
                        .confirmationDialog("Stop \(name)?", isPresented: $confirmStop, titleVisibility: .visible) {
                            Button("Stop", role: .destructive) {
                                if let editing { problem = app.attempt("Stopped.") { try app.store.archivePlannedItem(editing.id) } }
                            }
                        } message: { Text("Future unpaid ones are removed. Payments already made stay in your history.") }
                }
            }
            .onAppear(perform: load)
        }

        private func load() {
            guard let item = editing else {
                accountId = app.moneyAccounts.first { $0.id == app.store.settings.lastUsedAccountId }?.id ?? app.moneyAccounts.first?.id
                if income { categoryId = app.snapshot.incomeCategories.first?.id }
                return
            }
            let s = app.snapshot
            name = item.name
            amount = MoneyFormat.editable(item.amount)
            estimate = item.isEstimate
            // Show when it's next due, not when the bill was first set up
            due = s.occurrences.filter { $0.itemId == item.id && !$0.skipped && !$0.remaining.isZero && $0.dueDate >= s.today }
                .map(\.dueDate).min() ?? item.schedule.start
            loadedDue = due
            let oneTime = item.schedule.end.map { s.calendar.isDate($0, inSameDayAs: item.schedule.start) } ?? false
            frequency = oneTime ? nil : item.schedule.frequency
            hasEnd = !oneTime && item.schedule.end != nil
            end = item.schedule.end ?? due
            accountId = item.accountId
            categoryId = item.categoryId
            reminderDays = s.reminderDays(for: item.id)
            isTrial = s.isTrial(item.id)
        }

        private func save() {
            problem = nil
            let title = name.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { problem = income ? "Say what it is." : "Give the bill a name."; return }
            guard let value = app.parse(amount), value.isPositive else { problem = "Enter an amount greater than zero."; return }
            let start = editing != nil && due == loadedDue ? editing!.schedule.start : app.calendar.startOfDay(for: due)
            let schedule = Schedule(start: start, frequency: frequency ?? .monthly(every: 1),
                                    end: frequency == nil ? start : hasEnd ? end : nil)
            let item = PlannedItem(id: editing?.id ?? UUID(), name: title, direction: direction, amount: value, isEstimate: estimate,
                                   schedule: schedule, accountId: accountId, categoryId: categoryId, debtId: editing?.debtId)
            problem = app.attempt(editing != nil ? "Saved." : income ? "Expected income added." : "Bill added to your upcoming commitments.") {
                try app.store.savePlannedItem(item, reminderDays: income ? nil : reminderDays, isTrial: income ? nil : isTrial)
            }
        }
    }

    /// Every regular bill and expected income, to change or stop
    struct Schedules: View {
        @Environment(AppModel.self) private var app
        /// Pressed and held to remove, waiting on a yes
        @State private var removing: PlannedItem?

        var body: some View {
            let items = app.snapshot.items
            let bills = items.filter { $0.direction == .outflow }
            let income = items.filter { $0.direction == .inflow }
            SectionHeading(title: "Bills", action: "Add") { app.open(.entry(.bill)) }
            list(bills, empty: "No bills yet.")
            SectionHeading(title: "Expected income", action: "Add") { app.open(.entry(.expectedIncome)) }.padding(.top, 24)
            list(income, empty: "Add your salary or other regular income, so payday can be planned for.")
            Redesign.footnote("A card or loan payment is set from the card's or loan's page, under Terms.").padding(.top, 16)
        }

        @ViewBuilder private func list(_ items: [PlannedItem], empty: String) -> some View {
            if items.isEmpty {
                Redesign.footnote(empty).rdPanel()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { app.open(item.debtId.map { .debtTerms($0) } ?? .editBill(item.id)) } label: {
                            HStack(spacing: 12) {
                                IconBox(symbol: item.direction == .inflow ? "arrow.down.left" : item.debtId != nil ? "creditcard" : "doc.text", small: true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.hidesDetails ? (item.direction == .inflow ? "Income" : "Bill") : item.name).rdText(.cardTitle)
                                    Text(app.scheduleLabel(item.schedule) + (item.isEstimate ? " · estimate" : "")).rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                app.amount(item.amount.decimal).rdText(.amount)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(item.direction == .inflow ? "Stop expecting this" : "Remove this bill", systemImage: "trash", role: .destructive) {
                                removing = item
                            }
                        }
                        if i < items.count - 1 { Redesign.hairline }
                    }
                }
                .rdPanel(padding: 14)
                .confirmationDialog(removing.map { "Remove \($0.name)?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                    titleVisibility: .visible, presenting: removing) { item in
                    Button("Remove", role: .destructive) {
                        if let problem = app.attempt("Removed.", closing: false, { try app.store.archivePlannedItem(item.id) }) {
                            app.toast = Toast(message: problem, isError: true)
                        }
                    }
                } message: { _ in
                    Text("Future unpaid ones are removed. Payments already made stay in your history.")
                }
            }
        }
    }
}
