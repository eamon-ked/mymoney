//
//  RedesignFlows.swift
//  Nokael Money
//
//  Payday in one screen, bringing in a statement, Siri and automatic capture,
//  and the debug launch options for screenshots.
//

import SwiftUI
import AppIntents
import UniformTypeIdentifiers
import NokaelCore

// MARK: - Payday

extension Redesign {
    /// The salary from the plan already filled in, and the month's routine as switches that are on by default
    struct PaydayForm: View {
        @Environment(AppModel.self) private var app
        @State private var plan: PaydayPlan?
        @State private var amount = ""
        @State private var accountId: UUID?
        @State private var date = Date()
        @State private var choices = PaydayPlan.Choices()
        @State private var key = UUID()
        @State private var done: [String]?
        @State private var problem: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let done {
                    finished(done)
                } else if let plan {
                    if let when = plan.alreadyReceived, app.paydaySaid == nil {
                        Label("This month's salary was recorded on \(when.formatted(.dateTime.day().month(.wide))).", systemImage: "checkmark.circle")
                            .rdText(.body).foregroundStyle(Theme.primary)
                        Button("Add other income") { app.open(.entry(.income)) }.buttonStyle(QuietButtonStyle())
                    } else {
                        form(plan)
                    }
                }
            }
            .onAppear(perform: load)
        }

        @ViewBuilder private func form(_ plan: PaydayPlan) -> some View {
            AmountBox(label: "Your salary in \(app.currency)", text: $amount)
            Redesign.footnote(plan.item.map { "From your plan: \(app.hidesDetails ? "Salary" : $0.name), \(app.money($0.amount)). Change the amount if this one was different." }
                              ?? "There's no salary in your plan yet.")
                .padding(.horizontal, 4)
            AccountChoice(label: "Paid into", selection: $accountId, accounts: app.moneyAccounts.filter { app.record($0.id)?.spendable == true })
            Field(label: "Received") {
                DatePicker("Received", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            if plan.item == nil {
                ToggleRow(title: "Remember it as my monthly salary", detail: "Next month Nokael expects it, and payday is one tap.",
                          isOn: $choices.remember)
            }
            if plan.budgetFrom != nil || !plan.goals.isEmpty {
                Redesign.overline("Then, for this month").padding(.top, 8)
                if plan.budgetFrom != nil {
                    ToggleRow(title: "Plan this month's budget",
                              detail: "Same as last month: \(app.money(plan.budgetTotal)) across \(plan.budgetCount) categories",
                              isOn: $choices.copyBudget)
                }
                ForEach(plan.goals) { goal in
                    ToggleRow(title: "Put \(app.money(goal.amount)) into \(app.hidesDetails ? "a goal" : goal.name)",
                              detail: goal.by.map { "To reach it by \($0.formatted(.dateTime.month(.wide).year()))" },
                              isOn: Binding(get: { choices.goals.contains(goal.id) },
                                            set: { on in if on { choices.goals.insert(goal.id) } else { choices.goals.remove(goal.id) } }))
                }
            }
            if plan.billsBeforeNext.isPositive {
                DetailCard { DetailRow(label: "Bills before next payday", value: app.money(plan.billsBeforeNext)) }
                Redesign.footnote(plan.nextPayday.map { "Until \($0.formatted(.dateTime.day().month(.wide))). They're already kept aside in safe to spend." }
                                  ?? "They're already kept aside in safe to spend.")
                    .padding(.horizontal, 4)
            }
            Problem(text: problem)
            Button("Do it", action: run).buttonStyle(PrimaryButtonStyle()).padding(.top, 8).accessibilityIdentifier("paydayDoIt")
        }

        @ViewBuilder private func finished(_ lines: [String]) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(lines, id: \.self) { line in
                    Label { Text(private: line).rdText(.body) } icon: { Image(systemName: "checkmark.circle").foregroundStyle(Theme.primary) }
                }
            }
            .rdPanel()
            let sts = app.safeToSpend
            if let amount = sts.amount, app.snapshot.setupComplete {
                Redesign.footnote("Safe to spend is now \(app.money(amount)) until \(sts.periodEnd.formatted(.dateTime.day().month(.wide))).")
                    .padding(.horizontal, 4)
            }
            Button("Done") { app.close() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
        }

        private func load() {
            guard plan == nil else { return }
            let made = PaydayPlan.make(app.snapshot, said: app.paydaySaid)
            plan = made
            amount = MoneyFormat.editable(made.amount, emptyWhenZero: true)
            accountId = made.accountId
            choices.goals = Set(made.goals.map(\.id))
            choices.copyBudget = made.budgetFrom != nil
        }

        private func run() {
            guard var plan else { return }
            guard let money = app.parse(amount), money.isPositive else { problem = "Enter the salary you received."; return }
            plan.amount = money
            plan.accountId = accountId
            do {
                done = try plan.run(app.store, choices: choices, date: date, key: key)
                app.paydaySaid = nil
                problem = nil
            } catch {
                problem = StoreError.from(error).errorDescription
            }
        }
    }
}

// MARK: - Statement import

extension Redesign {
    /// Bring in a bank or card statement saved as CSV. Rows already recorded are set aside; the rest are given
    /// a category, a transfer or the bill they pay, then added in one go. Reading and matching are in StatementReview.
    struct ImportStatement: View {
        let accountId: UUID?
        @Environment(AppModel.self) private var app
        @State private var chosen: UUID?
        @State private var review: StatementReview?
        /// The account already had its free import
        @State private var usedFree: UUID?

        var body: some View {
            Group {
                if let review {
                    ImportReview(review: review)
                } else if let usedFree {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("One free import per account").rdText(.heading)
                        Text(private: "A statement is already imported into \(app.accountLabel(usedFree)). To keep it up to date, add new spending as it happens, or import as often as you like with Nokael Plus.")
                            .rdText(.body).foregroundStyle(Theme.muted)
                        Button("See Nokael Plus") { app.open(.paywall(.statementImport)) }.buttonStyle(PrimaryButtonStyle())
                        if accountId == nil {
                            Button("Choose another account") { self.usedFree = nil }.buttonStyle(QuietButtonStyle())
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Which account is the statement for?").rdText(.heading)
                        Redesign.footnote("The statement is read on this device and never uploaded.")
                        if !app.isPlus {
                            Redesign.footnote("Your first statement for each account is free. More imports come with Nokael Plus.")
                        }
                        AccountChoice(label: "Account", selection: $chosen, accounts: app.accounts.filter { $0.kind != .lent })
                        Button("Continue") { start(chosen) }.buttonStyle(PrimaryButtonStyle()).disabled(chosen == nil)
                    }
                }
            }
            .onAppear { if review == nil, usedFree == nil, let accountId { start(accountId) } }
            .onChange(of: app.isPlus) { _, plus in if plus, let id = usedFree { usedFree = nil; start(id) } }
        }

        /// The first import into each account is free, so a new account can start with its history
        private func start(_ id: UUID?) {
            guard let id else { return }
            if !app.isPlus && app.store.hasImportedStatement(into: id) {
                usedFree = id
                return
            }
            let review = StatementReview(accountId: id, store: app.store)
            review.askAI = AppleIntelligence.isReady
            self.review = review
        }
    }

    private struct ImportReview: View {
        @Bindable var review: StatementReview
        @Environment(AppModel.self) private var app
        @State private var choosingFile = false
        @State private var showMatched = false
        @State private var showColumns = false
        @State private var password = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let added = review.added {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.primary)
                        Text(added == 0 ? "Nothing new to add" : "Added \(added) \(added == 1 ? "entry" : "entries")").rdText(.heading)
                        if review.closingCheck == nil {
                            Text("Check the balance against your statement to be sure everything's in.")
                                .rdText(.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    balanceCheck
                    Button("Done") { app.close() }.buttonStyle(PrimaryButtonStyle())
                } else if review.fileText == nil {
                    intro
                } else if review.needsColumns, let layout = review.layout {
                    DetailCard { DetailRow(label: "File", value: review.fileName) }
                    Text("Which column is which?").rdText(.heading).padding(.top, 8)
                    if let reading = review.reading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(reading).rdText(.detail).foregroundStyle(Theme.muted)
                        }
                    } else {
                        Text(columnsQuestion(layout)).rdText(.body).foregroundStyle(Theme.muted)
                    }
                    ColumnsPicker(review: review, layout: layout) {}
                    Problem(text: review.error)
                    Button("Choose another file") { choosingFile = true }.rdText(.label).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                } else {
                    rows
                }
            }
            #if DEBUG
            .onAppear {
                // Screenshot helper: -importSample /path/to/statement.csv
                if review.fileText == nil, let path = UserDefaults.standard.string(forKey: "importSample") {
                    review.load(URL(fileURLWithPath: path))
                }
            }
            #endif
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .pdf, .plainText, .text]) { result in
                switch result {
                case .success(let url): review.load(url)
                case .failure: review.error = "Couldn't open that file."
                }
            }
        }

        @ViewBuilder private var intro: some View {
            IconBox(symbol: "doc.text.magnifyingglass")
            Text("Bring in \(app.hidesAccountNames ? "this account" : review.account?.name ?? "this account")'s statement").rdText(.heading)
            Text("Download a statement from your bank's website or app as a CSV or PDF file, then choose it here. Rows you've already recorded are recognised and left alone.")
                .rdText(.body).foregroundStyle(Theme.muted)
            Label("Read on this device. Your statement is never uploaded, and the app never signs in to your bank.", systemImage: "lock")
                .rdText(.detail).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("statementStaysHere")
            if let reading = review.reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(reading).rdText(.detail).foregroundStyle(Theme.muted)
                }
            } else if review.needsPassword {
                Field(label: "\(review.fileName) is locked") {
                    SecureField("Password", text: $password)
                        .textContentType(.password).submitLabel(.go)
                        .onSubmit(unlock)
                        .accessibilityIdentifier("statementPassword")
                }
                Redesign.footnote("Enter the file's own password, the one your bank gave for opening statements. It's used once to open the file on this device and isn't saved. This is never your bank login.")
                Problem(text: review.error)
                Button("Open", action: unlock).buttonStyle(PrimaryButtonStyle()).disabled(password.isEmpty)
                Button("Choose another file") { choosingFile = true }.rdText(.label).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
            } else {
                Button("Choose file") { choosingFile = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("chooseStatement")
                Problem(text: review.error)
            }
            Redesign.explainer("The app works out which column is which from what's in them, in any language. If it picks the wrong ones, you can choose them. The file stays on this device.")
        }

        private func unlock() {
            guard !password.isEmpty else { return }
            let typed = password
            password = ""
            Task { await review.unlock(typed) }
        }

        /// Why the person is asked, in words
        private func columnsQuestion(_ layout: StatementLayout) -> String {
            switch layout.question {
            case .outOrIn(let a, let b):
                return "\(layout.name(a)) and \(layout.name(b)) both hold money, and nothing in the file says which is money out. Pick them below."
            case .whichAmount:
                return "Several columns hold amounts, and nothing in the file says which is each row's amount. Pick them below."
            case nil:
                return "The app couldn't tell from what's in the file. Pick them from the examples below."
            }
        }

        /// "Date, Details, Amount": the columns in use, by the file's own names
        private var columnsSummary: String {
            guard let layout = review.layout, let c = review.columnsInUse else { return "Choose" }
            return [c.date, c.description, c.amount, c.debit, c.credit].compactMap { $0 }.map(layout.name).joined(separator: ", ")
        }

        @ViewBuilder private var rows: some View {
            if let mismatch = review.numberMismatch {
                Label { Text(private: mismatch) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.amber) }
                    .rdText(.detail).rdPanel()
            }
            DetailCard {
                DetailRow(label: "File", value: review.fileName)
                Redesign.hairline
                DetailRow(label: "Rows", value: "\(review.rows.count)")
                Redesign.hairline
                DetailRow(label: "Already recorded", value: "\(review.matched.count)")
                if review.layout != nil && !review.needsColumns {
                    Redesign.hairline
                    Button { withAnimation { showColumns.toggle() } } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("Columns").foregroundStyle(Theme.muted)
                            Spacer()
                            Text(private: columnsSummary).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                            Image(systemName: showColumns ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .rdText(.detail).padding(.vertical, 15).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statementColumns")
                }
                if let check = review.balanceCheck {
                    Redesign.hairline
                    DetailRow(label: "Match the balance", value: "\(check.addUp) of \(check.rows)")
                        .accessibilityIdentifier("balanceCheck")
                }
            }
            if review.columns == nil, review.suggested != nil {
                Text("Apple Intelligence chose the money columns. Check them under Columns.")
                    .rdText(.caption).foregroundStyle(Theme.muted)
            } else if let check = review.balanceCheck, !check.allAddUp {
                Text("Some rows don't match the running balance. Check the columns, or rows may be missing from the file.")
                    .rdText(.caption).foregroundStyle(Theme.muted)
            }
            if let layout = review.layout, showColumns {
                ColumnsPicker(review: review, layout: layout) { showColumns = false }
            }
            ToggleRow(title: "Purchases show as positive numbers",
                      detail: "Card statements often list purchases without a minus sign. Turn this on if money out appears as money in below.",
                      isOn: $review.flipSigns)
            Problem(text: review.error)
            if review.error == nil, let problem = review.currencyProblem { Problem(text: problem) }

            if review.suggesting > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suggesting categories… \(review.suggesting) to go").rdText(.detail).foregroundStyle(Theme.muted)
                }
            } else if !review.bulkSortable.isEmpty {
                sortTheRest
            }

            HStack {
                Text("To add · \(review.inbox.count)").rdText(.section)
                Spacer()
                if !review.inbox.isEmpty {
                    Button(review.allSelected ? "Untick all" : "Tick all") { review.toggleAll() }
                        .rdText(.detail).foregroundStyle(Theme.primary)
                        .accessibilityIdentifier("importSelectAll")
                }
            }
            .padding(.top, 8)
            if review.inbox.isEmpty {
                Text("Everything in this file is already recorded.").rdText(.detail).foregroundStyle(Theme.muted)
                balanceCheck
            } else {
                Divided(items: review.inbox) { row in
                    InboxRow(row: row, target: binding(row), skipped: skipBinding(row),
                             options: review.options(for: row), label: review.label(for: row),
                             prompt: review.prompt(for: row), lookalike: review.lookalike(for: row),
                             addAccount: review.ownTransfers.contains(row.id) ? { review.addOwnAccount(for: row) } : nil,
                             addLoan: review.loanRows.contains(row.id) ? { review.addLoan(for: row) } : nil)
                }
                .padding(.horizontal, 16)
                .rdPanel(padding: 0)
                Redesign.footnote("Categories are suggested for you; tap one to change it. Untick a row to leave it out.").padding(.horizontal, 4)
            }

            if !review.matched.isEmpty {
                Button { withAnimation { showMatched.toggle() } } label: {
                    HStack {
                        Text("Already recorded · \(review.matched.count)").rdText(.section)
                        Spacer()
                        Image(systemName: showMatched ? "chevron.up" : "chevron.down").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                if showMatched {
                    Divided(items: review.rows.filter { review.matched[$0.id] != nil }) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(private: app.hidesDetails ? "Entry" : row.description).rdText(.cardTitle).lineLimit(1)
                                Text(app.fullDay(row.date)).rdText(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(private: app.money(row.amount)).rdText(.amount).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .rdPanel(padding: 0)
                }
            }

            if !review.inbox.isEmpty {
                Text(review.summary).rdText(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, 8)
                Button(review.ready.isEmpty ? "Choose a category to add"
                       : "Add \(review.ready.count) \(review.ready.count == 1 ? "entry" : "entries")") { review.add() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(review.ready.isEmpty || review.currencyProblem != nil)
                    .accessibilityIdentifier("addImported")
            }
        }

        /// One entry the statement doesn't show, as a short line, signed the way the statement would show it
        private func gapLine(_ id: UUID) -> String? {
            guard let t = app.transaction(id), let effect = review.effect(of: id) else { return nil }
            return "\(app.day(t.date)) · \(app.name(of: t)) · \(signed(effect))"
        }

        /// "+AED 69.00" or "−AED 20.00": which way the money went, always spelled out
        private func signed(_ amount: Money) -> String {
            amount.isZero ? app.money(amount) : "\(amount.isNegative ? "−" : "+")\(app.money(amount.magnitude))"
        }

        /// Entries the statement doesn't show: not posted yet, and ones worth a look
        @ViewBuilder private var gapsPanel: some View {
            if let gaps = review.gaps {
                let waiting = gaps.waiting.compactMap { id in gapLine(id).map { (id, $0) } }
                let missing = gaps.missing.compactMap { id in gapLine(id).map { (id, $0) } }
                if !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Not on this statement").rdText(.detailStrong)
                        Redesign.footnote("These are in the app for the statement's dates, but the statement doesn't show them. If one is the same money saved twice, delete it.")
                        ForEach(missing, id: \.0) { id, line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(private: line).rdText(.detail)
                                HStack(spacing: 12) {
                                    Button("Keep") { review.keep(id) }.buttonStyle(QuietButtonStyle())
                                        .accessibilityIdentifier("keepGap")
                                    Button { review.delete(id) } label: { Text("Delete").foregroundStyle(Theme.destructive) }
                                        .buttonStyle(QuietButtonStyle())
                                        .accessibilityIdentifier("deleteGap")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rdPanel()
                }
                if !waiting.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not on the statement yet").rdText(.detailStrong)
                        Redesign.footnote("Card payments take a few days to post, and the last day may have more since the statement was made. They're left out of the check below.")
                        ForEach(waiting, id: \.0) { _, line in Text(private: line).rdText(.detail) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rdPanel()
                }
            }
        }

        /// The statement's closing balance against the app's on the same day, with a way to match them
        @ViewBuilder private var balanceCheck: some View {
            gapsPanel
            if let check = review.closingCheck, let day = review.balances?.lastDay {
                VStack(alignment: .leading, spacing: 8) {
                    if check.matches {
                        Label {
                            Text(private: "Matches your statement: \(app.money(check.statement)) on \(app.day(day))")
                        } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary) }
                        .rdText(.detail)
                    } else {
                        Text(private: "Your statement ends at \(app.money(check.statement)) on \(app.day(day)). For the same entries, the app has \(app.money(check.calculated)).")
                            .rdText(.detail)
                        if review.gaps?.missing.isEmpty == false {
                            Redesign.footnote("Check the entries above first: they may explain the difference.")
                        }
                        Redesign.footnote(check.difference.isNegative
                            ? "Using the statement's balance takes \(app.money(check.difference.magnitude)) off this account."
                            : "Using the statement's balance adds \(app.money(check.difference)) to this account.")
                        Button("Use the statement's balance") { review.matchStatement() }
                            .rdText(.label).foregroundStyle(Theme.primary)
                            .accessibilityIdentifier("matchStatement")
                    }
                    // The account page shows today's balance, which also counts what the statement doesn't have yet
                    if review.balanceToday != check.calculated {
                        Redesign.footnote("The account shows \(app.money(review.balanceToday)) today, because it also counts entries that aren't on this statement yet.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rdPanel()
            }
        }

        /// One choice for every ticked row that has none yet
        @ViewBuilder private var sortTheRest: some View {
            let out = review.bulkSortable.filter(\.amount.isNegative)
            let into = review.bulkSortable.filter { !$0.amount.isNegative }
            VStack(alignment: .leading, spacing: 10) {
                Text("\(review.bulkSortable.count) still need a category").rdText(.cardTitle)
                if !out.isEmpty {
                    bulkMenu("Put \(out.count) money-out \(out.count == 1 ? "row" : "rows") in…", categories: app.snapshot.expenseCategories, rows: out)
                }
                if !into.isEmpty {
                    bulkMenu("Put \(into.count) money-in \(into.count == 1 ? "row" : "rows") in…", categories: app.snapshot.incomeCategories, rows: into)
                }
                Text("Sorts all of them at once. You can still change any single row below.").rdText(.caption).foregroundStyle(Theme.muted)
            }
            .rdPanel()
        }

        private func bulkMenu(_ title: String, categories: [LedgerAccountRecord], rows: [StatementRow]) -> some View {
            Menu {
                ForEach(categories, id: \.id) { c in
                    Button { review.put(rows, in: c.id) } label: { Label(c.name, systemImage: c.icon) }
                }
            } label: {
                Label(title, systemImage: "square.stack.3d.down.right").rdText(.label).foregroundStyle(Theme.primary)
            }
        }

        private func binding(_ row: StatementRow) -> Binding<LedgerStore.ImportedRow.Target?> {
            Binding(get: { review.targets[row.id] }, set: { review.targets[row.id] = $0 })
        }

        private func skipBinding(_ row: StatementRow) -> Binding<Bool> {
            Binding(get: { review.skipped.contains(row.id) },
                    set: { if $0 { review.skipped.insert(row.id) } else { review.skipped.remove(row.id) } })
        }
    }

    /// Which of the file's columns holds the date, the description and the money, chosen by the person
    private struct ColumnsPicker: View {
        let review: StatementReview
        let layout: StatementLayout
        let done: () -> Void
        @State private var draft = StatementColumns()
        @State private var separate = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                role("Date", \.date)
                Redesign.hairline
                role("Description", \.description)
                Redesign.hairline
                Picker("Money", selection: $separate) {
                    Text("One amount").tag(false)
                    Text("Money out and in").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 12)
                .onChange(of: separate) { _, on in
                    if on { draft.amount = nil } else { draft.debit = nil; draft.credit = nil }
                }
                if separate {
                    role("Money out", \.debit)
                    Redesign.hairline
                    role("Money in", \.credit)
                } else {
                    role("Amount", \.amount)
                }
                Redesign.hairline
                role("Balance", \.balance, optional: true)
            }
            .padding(.horizontal, 16)
            .rdPanel(padding: 0)
            .onAppear {
                draft = review.columnsInUse ?? StatementColumns()
                separate = draft.amount == nil && (draft.debit != nil || draft.credit != nil)
            }

            VStack(alignment: .leading, spacing: 10) {
                if !draft.missing.isEmpty {
                    Text("Still to choose: \(draft.missing.joined(separator: ", ")).").rdText(.caption).foregroundStyle(Theme.muted)
                }
                Button("Use these columns") {
                    review.columns = draft == layout.guess ? nil : draft
                    done()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!draft.isComplete)
                .accessibilityIdentifier("useColumns")
                if review.columns != nil, layout.guess != nil {
                    Button("Go back to the app's choice") {
                        review.columns = nil
                        done()
                    }
                    .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity)
                }
                Text("Remembered for this account's next statement with the same columns.")
                    .rdText(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
        }

        /// One column holds one thing: choosing it here takes it away from any other role
        private func choose(_ column: Int, for key: WritableKeyPath<StatementColumns, Int?>) {
            let keys: [WritableKeyPath<StatementColumns, Int?>] = [\.date, \.description, \.amount, \.debit, \.credit, \.balance]
            for other in keys where other != key && draft[keyPath: other] == column { draft[keyPath: other] = nil }
            draft[keyPath: key] = column
        }

        private func role(_ title: String, _ key: WritableKeyPath<StatementColumns, Int?>, optional: Bool = false) -> some View {
            Menu {
                if optional {
                    Button("None") { draft[keyPath: key] = nil }
                }
                ForEach(layout.names.indices, id: \.self) { i in
                    Button { choose(i, for: key) } label: {
                        Text(layout.name(i))
                        if let sample = layout.sample(i) { Text(sample) }
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title).foregroundStyle(Theme.muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(private: draft[keyPath: key].map(layout.name) ?? (optional ? "None" : "Choose"))
                            .fontWeight(.medium)
                            .foregroundStyle(draft[keyPath: key] == nil && !optional ? Theme.primary : Theme.foreground)
                        if let i = draft[keyPath: key], let sample = layout.sample(i) {
                            Text(private: sample).rdText(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
                }
                .rdText(.detail).padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("column.\(title)")
        }
    }

    /// One statement row waiting for a decision
    private struct InboxRow: View {
        let row: StatementRow
        @Binding var target: LedgerStore.ImportedRow.Target?
        @Binding var skipped: Bool
        let options: [(String, [StatementReview.Option])]
        let label: String?
        var prompt = "Choose a category"
        /// An entry of the same amount close by under another name: maybe this row, maybe not
        var lookalike: EntryRecord? = nil
        /// Money moved to an account of theirs that isn't in the app yet
        var addAccount: (() -> Void)? = nil
        /// Pays a loan that isn't in the app yet
        var addLoan: (() -> Void)? = nil
        @Environment(AppModel.self) private var app

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Button { skipped.toggle() } label: {
                    Image(systemName: skipped ? "circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(skipped ? Theme.muted : Theme.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.description)
                .accessibilityValue(skipped ? "Not ticked" : "Ticked")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(private: app.hidesDetails ? "Entry" : row.description.isEmpty ? "No description" : row.description)
                            .rdText(.cardTitle).lineLimit(2).strikethrough(skipped)
                        Spacer(minLength: 8)
                        Text(private: (row.amount.isNegative ? "−" : "+") + app.money(row.amount.magnitude))
                            .rdText(.amount).foregroundStyle(row.amount.isNegative ? Theme.foreground : Theme.primary)
                    }
                    Text(app.fullDay(row.date)).rdText(.caption).foregroundStyle(Theme.muted)
                    if let lookalike {
                        Text(private: "Maybe already recorded as \(app.hidesDetails || lookalike.memo.isEmpty ? "an entry" : lookalike.memo) on \(app.fullDay(lookalike.date))")
                            .rdText(.caption).foregroundStyle(Theme.amber)
                    }
                    if skipped {
                        Text("Left out · tick to add it").rdText(.captionStrong).foregroundStyle(Theme.muted)
                    } else {
                        Menu {
                            if let addAccount {
                                Button { addAccount() } label: { Label("Add it as a new account", systemImage: "plus.circle") }
                            }
                            if let addLoan {
                                Button { addLoan() } label: { Label("Add it as a new loan", systemImage: "plus.circle") }
                                    .accessibilityIdentifier("addLoanFromRow")
                            }
                            ForEach(options, id: \.0) { group in
                                Section(group.0) {
                                    ForEach(group.1) { option in
                                        Button { target = option.target } label: { Label(option.title, systemImage: option.symbol) }
                                    }
                                }
                            }
                        } label: {
                            Text(label ?? prompt)
                                .rdText(.captionStrong)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .foregroundStyle(label == nil ? Theme.amber : Theme.primary)
                                .background(label == nil ? Theme.amberFill : Theme.primary.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .opacity(skipped ? 0.5 : 1)
        }
    }
}

// MARK: - Siri & automatic capture

extension Redesign {
    /// iOS doesn't let apps read Wallet or messages, so the person sets up two Shortcuts automations once; this page
    /// walks through them, lists the cards it has learned, picks which SMS senders count as banks, and tries a message.
    struct CapturePage: View {
        /// The overview, or one way of capturing, each on its own screen
        enum Section { case overview, bank, applePay, siri, activity }

        var section: Section = .overview
        @Environment(AppModel.self) private var app
        @Environment(\.openURL) private var openURL
        @State private var newSender = ""
        @State private var testText = ""
        @State private var testSender = ""
        @State private var testRun: CaptureTrace?
        @State private var testSteps = false
        @State private var confirmClear = false
        @State private var traceProblem: String?
        @State private var openTrace: UUID?
        @State private var byHand = false
        @State private var addingBank = false
        @State private var applePaySteps: Bool?

        private var settings: SettingsRecord { app.store.settings }
        /// The person's choice, else the phone's country if we know its banks, else the country of their currency
        private var region: String {
            AppGuide.bankRegion(chosen: settings.bankRegion, phone: Locale.current.region?.identifier, currency: settings.currency)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .overview: overview
                case .bank:
                    bankAlerts
                    yourBanks
                    tryIt
                case .applePay: applePay
                case .siri: siri
                case .activity: history
                }
            }
        }

        // MARK: Overview

        @ViewBuilder private var overview: some View {
            if !app.isPlus {
                LinkRow(symbol: "wallet.pass", title: "Apple Pay and bank messages",
                        detail: "Siri is free. Saving Apple Pay purchases and bank alerts automatically comes with Nokael Plus.",
                        badge: "PLUS") { app.open(.paywall(.autoCapture)) }
                    .rdPanel(padding: 0)
                    .padding(.bottom, 24)
            }
            Text("Choose how purchases get into Nokael Money. Each one is set up once.")
                .rdText(.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.bottom, 16)
            VStack(spacing: 0) {
                LinkRow(symbol: "message", title: "Bank messages",
                        detail: seen(app.store.lastBankMessage?.date, "Last message", none: "No message received yet")) {
                    app.show(.captureBank)
                }
                .accessibilityIdentifier("captureBank")
                line
                LinkRow(symbol: "wallet.pass", title: "Apple Pay",
                        detail: seen(app.store.lastCardPurchase?.date, "Last purchase", none: "No purchase received yet")) {
                    app.show(.captureApplePay)
                }
                .accessibilityIdentifier("captureApplePay")
                line
                LinkRow(symbol: "waveform", title: "Siri", detail: "Ready to use, nothing to set up") { app.show(.captureSiri) }
                    .accessibilityIdentifier("captureSiri")
            }
            .rdPanel(padding: 0)
            Redesign.footnote("Anything Nokael isn't sure of waits on To check for you. A payment that arrives by Apple Pay and by bank message is saved once.")
                .padding(.top, 10).padding(.horizontal, 4).padding(.bottom, 24)
            let traces = app.store.captureTraces
            if !traces.isEmpty {
                LinkRow(symbol: "clock.arrow.circlepath", title: "What came in", detail: summary(traces)) { app.show(.captureActivity) }
                    .accessibilityIdentifier("captureActivity")
                    .rdPanel(padding: 0)
                    .padding(.bottom, 24)
            }
        }

        /// "Last message 15 minutes ago": only what reached the app, never a guess that the automation is on
        private func seen(_ date: Date?, _ label: String, none: String) -> String {
            date.map { "\(label) \($0.formatted(.relative(presentation: .named)))" } ?? none
        }

        /// "This week: 5 saved, 2 ignored"
        private func summary(_ traces: [CaptureTrace]) -> String {
            let week = traces.filter { $0.date > app.store.now().addingTimeInterval(-7 * 86_400) }
            guard !week.isEmpty else { return "Nothing this week" }
            let ignored = week.filter { $0.verdict == .ignored }.count
            let saved = week.count - ignored
            return ignored == 0 ? "This week: \(saved) saved" : "This week: \(saved) saved, \(ignored) ignored"
        }

        /// One panel: the button that adds the shared shortcut, then the steps in Shortcuts to switch on the
        /// automation it brings (Shortcuts adds it switched off). By hand replaces the steps for older iOS.
        private func setUp(button: String, id: String, link: URL, steps: [String], after: String,
                           byHand: Bool, toggle: @escaping () -> Void, manual: [String]) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set it up once").rdText(.cardTitle)
                Button(button) { Task { openURL(await Self.resolved(link)) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier(id)
                Steps(steps: byHand ? manual : steps)
                if !byHand {
                    Text(after).rdText(.detail).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Button(byHand ? "Use the shortcut instead" : "Set it up by hand instead") { withAnimation { toggle() } }
                    .rdText(.detail).foregroundStyle(Theme.primary)
            }
            .rdPanel()
        }

        private var line: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 64) }

        // MARK: Siri

        private var siri: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Already on, nothing to set up", systemImage: "checkmark.circle").rdText(.detailStrong).foregroundStyle(Theme.primary)
                    Text("Say “Hey Siri” and one of these:").rdText(.detail).foregroundStyle(Theme.muted)
                    ForEach(["“Log spending in Nokael Money”, then “45 at the supermarket”",
                             "“What's safe to spend in Nokael Money”",
                             "“Add income in Nokael Money”"], id: \.self) { phrase in
                        Label(phrase, systemImage: "waveform").rdText(.detail)
                    }
                }
                .rdPanel()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Want a button for one? This lists them in Shortcuts; press and hold one to add it to your Home Screen or Action button.")
                        .rdText(.detail).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
                }
                .padding(.top, 16).padding(.horizontal, 4)
                Redesign.footnote("Entries from Siri use your last account and the category you used before for that shop. Anything Nokael had to guess is marked for review.")
                    .padding(.top, 16).padding(.horizontal, 4).padding(.bottom, 24)
            }
        }

        // MARK: Apple Pay

        private var applePay: some View {
            let showSteps = applePaySteps ?? false
            return VStack(alignment: .leading, spacing: 0) {
                lastSeen(app.store.lastCardPurchase.map { ($0.date, $0.summary) }, label: "Last card purchase",
                         none: "No card purchase has reached Nokael Money yet.")
                    .padding(.bottom, 16)
                setUp(button: "Add the Apple Pay shortcut", id: "addApplePayAutomation", link: Self.applePayShortcut,
                      steps: AppGuide.applePaySetupSteps, after: "Then pay with Apple Pay once. It shows at the top of this page.",
                      byHand: showSteps, toggle: { applePaySteps = !showSteps }, manual: [
                          "Open Shortcuts, tap Automation, then +.",
                          "Choose Transaction. Select all your cards and choose Run Immediately.",
                          "Tap New Blank Automation and add “Log Card Purchase” from Nokael Money.",
                          "Set Amount, Merchant and Card to the matching Shortcut Input values, then tap Done.",
                      ])
                let links = app.store.fetch(CardLinkRecord.self).sorted { $0.hint < $1.hint }
                if !links.isEmpty {
                    Redesign.overline("Your cards").padding(.top, 24)
                    VStack(spacing: 0) {
                        ForEach(Array(links.enumerated()), id: \.element.hint) { i, link in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(cardTitle(link.hint)).rdText(.cardTitle)
                                    Text(app.accountLabel(link.accountId)).rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Button("Forget") { try? app.store.unlinkCard(link.hint) }
                                    .rdText(.detail).foregroundStyle(Theme.destructive)
                            }
                            .frame(minHeight: 58)
                            if i < links.count - 1 { Redesign.hairline }
                        }
                    }
                    .padding(.horizontal, 16)
                    .rdPanel(padding: 0)
                }
                Redesign.footnote(links.isEmpty
                                  ? "Each tap of your iPhone or Watch is saved for review. The first time a card is used, choose its account once."
                                  : "A new card appears here the first time you use it. Forget one to choose its account again.")
                    .padding(.top, 10).padding(.horizontal, 4).padding(.bottom, 24)
            }
        }

        // MARK: Bank messages

        private var bankAlerts: some View {
            VStack(alignment: .leading, spacing: 0) {
                lastSeen(app.store.lastBankMessage.map { ($0.date, $0.summary) }, label: "Last message",
                         none: "No bank message has reached Nokael Money yet.")
                    .padding(.bottom, 16)
                // One ready-made shortcut for every country: it brings an automation for each common currency
                setUp(button: "Add the bank alerts shortcut", id: "addBankAutomation", link: Self.bankAlertShortcut,
                      steps: AppGuide.bankSetupSteps(keyword: AppGuide.bankKeyword(region: region)),
                      after: "Then add your bank below. Its next message shows at the top of this page.",
                      byHand: byHand, toggle: { byHand.toggle() }, manual: manualSteps)
                Spacer().frame(height: 24)
            }
        }

        /// The banks whose messages count: the ones chosen, then a way to add another, suggested or typed
        @ViewBuilder private var yourBanks: some View {
            let suggested = BankSenders.banks(region: region)
            let chosen = settings.bankSenders
            // Chosen senders, grouped under their bank's name where we know it
            let named = BankSenders.banks(region: region).filter { $0.senders.contains(where: chosen.contains) }
            let known = Set(named.flatMap(\.senders))
            let own = chosen.filter { !known.contains($0) }
            VStack(alignment: .leading, spacing: 0) {
                Redesign.overline("Your banks")
                VStack(spacing: 0) {
                    ForEach(named) { bank in
                        bankRow(bank.name, detail: bank.senders.filter(chosen.contains).joined(separator: ", ")) {
                            setSenders(bank.senders, on: false)
                        }
                        Redesign.hairline
                    }
                    ForEach(own, id: \.self) { sender in
                        bankRow(sender, detail: nil) { setSenders([sender], on: false) }
                        Redesign.hairline
                    }
                    Button { withAnimation { addingBank.toggle() } } label: {
                        Label(addingBank ? "Done adding" : "Add a bank", systemImage: addingBank ? "checkmark" : "plus")
                            .rdText(.label).foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    }
                    .accessibilityIdentifier("addBank")
                }
                .padding(.horizontal, 16)
                .rdPanel(padding: 0)
                if chosen.isEmpty {
                    Redesign.footnote("With no bank added, any message that reads like a purchase is saved. Add your bank so messages from anyone else are ignored.")
                        .padding(.top, 10).padding(.horizontal, 4)
                }
                if addingBank {
                    VStack(alignment: .leading, spacing: 12) {
                        Field(label: "The name your bank's messages come from") {
                            HStack {
                                TextField("e.g. MyBank or +4412345", text: $newSender)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("newSender")
                                Button("Add") {
                                    setSenders([newSender.trimmingCharacters(in: .whitespaces)], on: true)
                                    newSender = ""
                                }
                                .foregroundStyle(Theme.primary)
                                .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        Text("Type it exactly as it shows at the top of the message in Messages.")
                            .rdText(.caption).foregroundStyle(Theme.muted)
                        Field(label: "Or pick from banks in") {
                            Choice(value: Binding(get: { region }, set: { value in try? app.store.updateSettings { $0.bankRegion = value } }),
                                   options: Self.regions.map(\.code)) { code in Self.regions.first { $0.code == code }?.name ?? code }
                        }
                        let unpicked = suggested.filter { !$0.senders.contains(where: chosen.contains) }
                        if !unpicked.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(unpicked.enumerated()), id: \.element.id) { i, bank in
                                    Button { setSenders(bank.senders, on: true) } label: {
                                        HStack {
                                            Text(bank.name).rdText(.cardTitle)
                                            Spacer()
                                            Image(systemName: "plus.circle").foregroundStyle(Theme.primary)
                                        }
                                        .frame(minHeight: 50).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Add \(bank.name)")
                                    if i < unpicked.count - 1 { Redesign.hairline }
                                }
                            }
                            .padding(.horizontal, 16)
                            .rdPanel(padding: 0)
                        } else if suggested.isEmpty {
                            Text("No suggested banks for this country yet. Type your bank's sender above.")
                                .rdText(.detail).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }

        private func bankRow(_ name: String, detail: String?, remove: @escaping () -> Void) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).rdText(.cardTitle)
                    if let detail { Text(detail).rdText(.caption).foregroundStyle(Theme.muted) }
                }
                Spacer()
                Button("Remove", action: remove).rdText(.detail).foregroundStyle(Theme.destructive)
                    .accessibilityLabel("Remove \(name)")
            }
            .frame(minHeight: 54)
        }

        /// Paste a message and see what would happen to it, in a word, with the detail one tap away
        private var tryIt: some View {
            VStack(alignment: .leading, spacing: 12) {
                Redesign.overline("Test a message").padding(.bottom, -12)
                Field(label: "Paste a bank message") {
                    TextField("Message", text: $testText, axis: .vertical).lineLimit(3...6).padding(.vertical, 12)
                        .accessibilityIdentifier("captureTestMessage")
                }
                Field(label: "Who it's from, as it shows in Messages (optional)") {
                    TextField("e.g. MyBank", text: $testSender).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Test it") { Task { await test() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("captureTestButton")
                if let testRun { testResult(testRun) }
                Redesign.footnote("Nothing is saved. Messages are read on this iPhone and never leave it; only the purchase is kept, not the message.")
                    .padding(.horizontal, 4)
            }
            .padding(.bottom, 24)
        }

        private func testResult(_ run: CaptureTrace) -> some View {
            let verdict = run.verdict
            let read = verdict == .ignored ? nil : run.read
            return VStack(alignment: .leading, spacing: 10) {
                Label(verdict.title, systemImage: verdict.symbol)
                    .rdText(.cardTitle).foregroundStyle(verdict == .ignored ? Theme.muted : Theme.primary)
                    .accessibilityIdentifier("captureVerdict")
                if let read {
                    Text(private: MoneyFormat.string(read.amount)).rdText(.figure)
                    if !read.name.isEmpty {
                        Text(private: (read.spent ? "" : "From ") + read.name).rdText(.body)
                    }
                }
                Text(private: hidesTraces && verdict != .ignored ? "Hidden in Privacy Mode." : run.explanation)
                    .rdText(.detail).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button(testSteps ? "Hide each step" : "Show each step") { withAnimation { testSteps.toggle() } }
                    .rdText(.detail).foregroundStyle(Theme.primary)
                if testSteps { TraceSteps(trace: run, hidden: hidesTraces) }
            }
            .rdPanel()
        }

        /// The steps name amounts, shops, accounts and references, so any Privacy Mode hides them
        private var hidesTraces: Bool { app.hidesAmounts || app.hidesDetails }

        // MARK: What came in

        /// What became of the last few alerts and taps: a word for each, and the steps on a tap
        @ViewBuilder private var history: some View {
            let traces = app.store.captureTraces
            VStack(alignment: .leading, spacing: 0) {
                if traces.isEmpty {
                    Text("Nothing has reached Nokael Money yet. Each bank message and Wallet tap will show here with what became of it.")
                        .rdText(.detail).foregroundStyle(Theme.muted).rdPanel()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(traces.prefix(15).enumerated()), id: \.element.id) { i, trace in
                            Button {
                                withAnimation(.snappy) { openTrace = openTrace == trace.id ? nil : trace.id }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: trace.verdict.symbol)
                                        .foregroundStyle(trace.verdict == .ignored ? Theme.muted : Theme.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(trace.verdict.title) · \(trace.source.title) · \(trace.date.formatted(.relative(presentation: .named)))")
                                            .rdText(.detailStrong)
                                        Text(private: hidesTraces ? "Hidden in Privacy Mode." : trace.explanation).rdText(.caption)
                                            .foregroundStyle(Theme.muted).lineLimit(openTrace == trace.id ? nil : 2)
                                    }
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                                        .rotationEffect(.degrees(openTrace == trace.id ? 90 : 0))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("captureTrace.\(i)")
                            .padding(.top, 10)
                            .padding(.bottom, openTrace == trace.id ? 0 : 10)
                            if openTrace == trace.id {
                                TraceSteps(trace: trace, hidden: hidesTraces).padding(.vertical, 10)
                                traceActions(trace).padding(.bottom, 10)
                            }
                            if i < min(traces.count, 15) - 1 { Redesign.hairline }
                        }
                    }
                    .padding(.horizontal, 16)
                    .rdPanel(padding: 0)
                    Button("Clear these records") { confirmClear = true }
                        .rdText(.detail).foregroundStyle(Theme.primary).frame(minHeight: 44)
                        .accessibilityIdentifier("clearCaptureRecords")
                        .confirmationDialog("Clear these records?", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Clear records", role: .destructive) {
                                traceProblem = app.attempt("Records cleared. Your entries are as they were.", closing: false) {
                                    try app.store.clearCaptureTraces()
                                }
                            }
                        } message: { Text("Only this list goes. Every entry the messages made stays.") }
                    Problem(text: traceProblem)
                }
            }
            .padding(.bottom, 24)
        }

        /// What can be done with one record: open what it made or joined, or add a payment it didn't save
        @ViewBuilder private func traceActions(_ trace: CaptureTrace) -> some View {
            let current = trace.entryId.flatMap(app.store.currentEntryId(from:))
            let deleted = current == nil ? trace.entryId.flatMap { app.store.entryRecord($0) } : nil
            VStack(alignment: .leading, spacing: 4) {
                if let current {
                    Button(trace.joined == true ? "Open the entry it joined" : "Open entry") { app.open(.transaction(current)) }
                        .accessibilityIdentifier("openTraceEntry")
                } else if let deleted {
                    Button("Open the deleted entry") { app.open(.transaction(deleted.id)) }
                        .accessibilityIdentifier("openTraceEntry")
                }
                if trace.joined == true || (current == nil && deleted == nil),
                   trace.readDetails(currency: app.store.currency) != nil {
                    Button(trace.joined == true ? "This was a separate payment" : "Add this payment") { addOnItsOwn(trace) }
                        .accessibilityIdentifier("addTracePayment")
                }
            }
            .rdText(.detail).foregroundStyle(Theme.primary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func addOnItsOwn(_ trace: CaptureTrace) {
            Task {
                do {
                    let id = try await CaptureService.saveOnItsOwn(trace, in: app.store)
                    traceProblem = app.attempt("Added. It's on To check so you can look at its account and category.", closing: false,
                                               undo: { try CaptureService.undoSaveOnItsOwn(id, trace: trace, in: app.store) }) {}
                } catch {
                    traceProblem = StoreError.from(error).errorDescription
                }
            }
        }

        @ViewBuilder private func lastSeen(_ last: (Date, String)?, label: String, none: String) -> some View {
            if let last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(label) \(last.0.formatted(.relative(presentation: .named)))").rdText(.detailStrong)
                    Text(private: app.hidesDetails ? "Hidden in Privacy Mode." : last.1).rdText(.caption).foregroundStyle(Theme.muted)
                }
                .rdPanel()
                .padding(.top, 12)
            } else {
                Label(none, systemImage: "exclamationmark.circle").rdText(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12).padding(.horizontal, 4)
            }
        }

        /// A shared shortcut with the Read Bank Message action; the person adds its Message automation. The link
        /// goes through our site (legal-docs/_redirects), so a new version ships without an app update.
        static let bankAlertShortcut = URL(string: "https://mymoney-legal-docs.pages.dev/s/bank-alerts")!

        /// The same for Apple Pay: the Log Card Purchase action, run by the person's Transaction automation
        static let applePayShortcut = URL(string: "https://mymoney-legal-docs.pages.dev/s/apple-pay")!

        /// Where our redirect points now. Opened directly, an iCloud shortcut link goes straight to
        /// Shortcuts; reached through a redirect in Safari it stops on the web page instead.
        static func resolved(_ url: URL) async -> URL {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
            request.httpMethod = "HEAD"
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let final = response.url, final.host != url.host else { return url }
            return final
        }

        private var manualSteps: [String] {
            [
                "Open Shortcuts, tap Automation, then +, and choose Message (“When I receive a message”).",
                "Add the filter Message contains “\(BankSenders.keyword(region: region))”, with no sender, and choose Run Immediately if asked.",
                "Add “Read Bank Message” from Nokael Money.",
                "Set Message to Shortcut Input, and Sender to Shortcut Input › Sender. Turn off Show When Run, then go back to save.",
            ]
        }

        private func test() async {
            let sender = testSender.trimmingCharacters(in: .whitespaces)
            testRun = await CaptureService.runBankMessage(testText, sender: sender.isEmpty ? nil : sender, store: app.store,
                                                          isPlus: app.isPlus, dryRun: true, useAI: false).trace
        }

        private func setSenders(_ senders: [String], on: Bool) {
            let cleaned = senders.filter { !$0.isEmpty }
            try? app.store.updateSettings { s in
                var list = s.bankSenders.filter { !cleaned.contains($0) }
                if on { list += cleaned }
                s.bankSenders = list
            }
        }

        private func cardTitle(_ hint: String) -> String {
            hint.count == 4 && hint.allSatisfy(\.isNumber) ? "Card ending \(hint)"
                : hint.hasPrefix("account ") ? "Account ending \(hint.dropFirst(8))" : hint.capitalized
        }

        static let regions: [(code: String, name: String)] = {
            let codes = Array(BankSenders.catalog.keys) + ["GB", "US", "KW", "OM", "BH"]
            return Set(codes).map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }
                .sorted { $0.1 < $1.1 }
        }()
    }

    /// Numbered how-to steps
    struct Steps: View {
        let steps: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .rdText(.captionStrong)
                            .frame(width: 22, height: 22)
                            .background(Theme.primary.opacity(0.1), in: Circle())
                            .foregroundStyle(Theme.primary)
                        Text(step).rdText(.detail).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Debug launch options

#if DEBUG
extension Redesign {
    /// Screenshot helpers: -tab budget|accounts|bills|more|activity|reports and
    /// -screen forecast|reports|payday|choose|guide|capture|applepay|bankalerts|settings|add [-addKind income]|ask|debtpay|loan|paywall|import|person
    enum DebugScreens {
        @MainActor static func open(in app: AppModel) {
            let defaults = UserDefaults.standard
            // -openEntry <id>: opens an entry the way a tapped notification does
            if let id = defaults.string(forKey: "openEntry").flatMap(UUID.init(uuidString:)) { AppRouter.shared.open(.entry(id)) }
            switch defaults.string(forKey: "tab") {
            case "budget": app.go(.budget)
            case "accounts": app.go(.accounts)
            case "bills": app.go(.bills)
            case "more": app.go(.more)
            case "activity": app.show(.activity)
            case "reports": app.show(.reports)
            default: break
            }
            let s = app.snapshot
            // UI tests: -captureMessages "first|||second" runs bank messages through, as the automation would
            if let messages = defaults.string(forKey: "captureMessages") {
                Task {
                    for message in messages.components(separatedBy: "|||") {
                        _ = await CaptureService.runBankMessage(message, sender: nil, store: app.store, isPlus: true, useAI: false)
                    }
                }
            }
            switch defaults.string(forKey: "screen") {
            case "forecast": app.show(.forecast)
            case "reports": app.show(.reports)
            case "capture": app.show(.capture)
            case "applepay": app.show(.capture); app.show(.captureApplePay)
            case "bankalerts": app.show(.capture); app.show(.captureBank)
            case "captureBank": app.show(.capture); app.show(.captureBank)
            case "captureActivity": app.show(.capture); app.show(.captureActivity)
            case "captureApplePay": app.show(.capture); app.show(.captureApplePay)
            case "captureSiri": app.show(.capture); app.show(.captureSiri)
            case "settings": app.show(.settings)
            case "payday": app.open(.payday)
            case "choose": app.open(.whatHappened)
            case "guide": app.open(.help)
            case "ask": app.open(.ask)
            case "add": app.open(.entry(defaults.string(forKey: "addKind") == "income" ? .income : .expense))
            case "loan": app.open(.newAccount(loan: true))
            case "paywall": app.open(.paywall(.statementImport))
            case "debtpay":
                if let paid = s.entryRecords.first(where: { $0.kind == .debtPayment && $0.status == .posted }) { app.open(.transaction(paid.id)) }
            case "person":
                if let person = s.accountRecords.first(where: { $0.kind == .lent && $0.name == "Maya" }) { app.open(.account(person.id)) }
            case "import":
                if let account = s.accounts.first(where: \.spendable) { app.open(.importStatement(account.id)) }
            default: break
            }
        }
    }
}
#endif

extension Redesign {
    /// Each step of a capture with a tick, a cross or a dash
    struct TraceSteps: View {
        let trace: CaptureTrace
        var hidden = false

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(trace.steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol(step.mark)).foregroundStyle(step.mark == .done ? Theme.primary : Theme.muted)
                            .accessibilityLabel(step.mark == .done ? "Done" : step.mark == .failed ? "Stopped here" : "Not reached")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).rdText(.detailStrong)
                            Text(private: hidden && step.mark == .done ? "Hidden in Privacy Mode." : step.detail)
                                .rdText(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func symbol(_ mark: CaptureTrace.Mark) -> String {
            switch mark {
            case .done: return "checkmark.circle.fill"
            case .failed: return "xmark.circle"
            case .notReached: return "minus.circle"
            }
        }
    }
}
