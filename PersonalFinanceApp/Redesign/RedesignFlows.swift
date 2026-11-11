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
            if let reading = review.reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(reading).rdText(.detail).foregroundStyle(Theme.muted)
                }
            } else if review.needsPassword {
                Field(label: "\(review.fileName) has a password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password).submitLabel(.go)
                        .onSubmit(unlock)
                        .accessibilityIdentifier("statementPassword")
                }
                Problem(text: review.error)
                Button("Open", action: unlock).buttonStyle(PrimaryButtonStyle()).disabled(password.isEmpty)
                Button("Choose another file") { choosingFile = true }.rdText(.label).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
            } else {
                Button("Choose file") { choosingFile = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("chooseStatement")
                Problem(text: review.error)
            }
            Redesign.explainer("The app works out which column is which from what's in them, in any language. If it picks the wrong ones, you can choose them. The file stays on this iPhone.")
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

        /// The statement's closing balance against the app's on the same day, with a way to match them
        @ViewBuilder private var balanceCheck: some View {
            if let check = review.closingCheck, let day = review.balances?.lastDay {
                VStack(alignment: .leading, spacing: 8) {
                    if check.matches {
                        Label {
                            Text(private: "Matches your statement: \(app.money(check.statement)) on \(app.day(day))")
                        } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary) }
                        .rdText(.detail)
                    } else {
                        Text(private: "Your statement ends at \(app.money(check.statement)) on \(app.day(day)). The app has \(app.money(check.calculated)).")
                            .rdText(.detail)
                        Button("Use the statement's balance") { review.matchStatement() }
                            .rdText(.label).foregroundStyle(Theme.primary)
                            .accessibilityIdentifier("matchStatement")
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
        @Environment(AppModel.self) private var app
        @Environment(\.openURL) private var openURL
        @State private var newSender = ""
        @State private var testText = ""
        @State private var testSender = ""
        @State private var testRun: CaptureTrace?
        @State private var confirmClear = false
        @State private var traceProblem: String?
        @State private var openTrace: UUID?
        @State private var byHand = false

        private var settings: SettingsRecord { app.store.settings }
        /// The person's choice, else the phone's country if we know its banks, else the country of their currency
        private var region: String {
            if let chosen = settings.bankRegion { return chosen }
            let phone = Locale.current.region?.identifier ?? ""
            if !BankSenders.banks(region: phone).isEmpty { return phone }
            let byCurrency = ["AED": "AE", "SAR": "SA", "INR": "IN", "QAR": "QA", "KWD": "KW", "OMR": "OM", "BHD": "BH"]
            return byCurrency[settings.currency] ?? phone
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !app.isPlus {
                    LinkRow(symbol: "wallet.pass", title: "Apple Pay and bank SMS capture",
                            detail: "Adding by voice with Siri is free. Saving Apple Pay purchases and bank alerts automatically comes with Nokael Plus.",
                            badge: "PLUS") { app.open(.paywall(.autoCapture)) }
                        .rdPanel(padding: 0)
                        .padding(.bottom, 24)
                }
                siri
                applePay
                sms
                tryIt
                history
            }
        }

        private var siri: some View {
            VStack(alignment: .leading, spacing: 0) {
                Redesign.overline("Siri")
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ready to use, nothing to create", systemImage: "checkmark.circle").rdText(.detailStrong).foregroundStyle(Theme.primary)
                    Text("Just say “Hey Siri” and one of these:").rdText(.detail).foregroundStyle(Theme.muted)
                    ForEach(["“Log spending in Nokael Money”, then “45 at the supermarket”",
                             "“What's safe to spend in Nokael Money”",
                             "“Add income in Nokael Money”"], id: \.self) { phrase in
                        Label(phrase, systemImage: "waveform").rdText(.detail)
                    }
                    Text("Want a button for it? Open Nokael Money in Shortcuts, then press and hold one to add it to your Home Screen or Action button.")
                        .rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
                    ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
                }
                .rdPanel()
                Redesign.footnote("Entries from Siri use your last account and the category you used before for that shop. Anything Nokael had to guess is marked for review.")
                    .padding(.top, 10).padding(.horizontal, 4).padding(.bottom, 24)
            }
        }

        private var applePay: some View {
            VStack(alignment: .leading, spacing: 0) {
                Redesign.overline("Apple Pay")
                VStack(alignment: .leading, spacing: 14) {
                    Steps(steps: [
                        "Open Shortcuts, tap Automation, then +.",
                        "Choose Transaction. Select all your cards and choose Run Immediately.",
                        "Tap New Blank Automation and add “Log Card Purchase” from Nokael Money.",
                        "Set Amount, Merchant and Card to the matching Shortcut Input values, then tap Done.",
                    ])
                    Button("Open Shortcuts") { openURL(URL(string: "shortcuts://")!) }.buttonStyle(QuietButtonStyle())
                }
                .rdPanel()
                let links = app.store.fetch(CardLinkRecord.self).sorted { $0.hint < $1.hint }
                if !links.isEmpty {
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
                    .padding(.top, 12)
                }
                lastSeen(app.store.lastCardPurchase.map { ($0.date, $0.summary) }, label: "Last card purchase",
                         none: "No card purchase has reached Nokael Money yet. If you've paid with your iPhone or Watch since setting this up, open the automation and check it's on, set to Run Immediately, and has your cards selected.")
                Redesign.footnote("Each tap of your iPhone or Watch is saved for review. When a new card is used, check the account once and choose “Always use this account”.")
                    .padding(.top, 10).padding(.horizontal, 4).padding(.bottom, 24)
            }
        }

        @ViewBuilder private var sms: some View {
            let banks = BankSenders.banks(region: region)
            let chosen = Set(settings.bankSenders)
            let known = Set(banks.flatMap(\.senders))
            let own = settings.bankSenders.filter { !known.contains($0) }
            VStack(alignment: .leading, spacing: 12) {
                Redesign.overline("Your banks").padding(.bottom, -12)
                Field(label: "Country") {
                    Choice(value: Binding(get: { region }, set: { value in try? app.store.updateSettings { $0.bankRegion = value } }),
                           options: Self.regions.map(\.code)) { code in Self.regions.first { $0.code == code }?.name ?? code }
                }
                ForEach(banks) { bank in
                    ToggleRow(title: bank.name, detail: bank.senders.joined(separator: ", "),
                              isOn: Binding(get: { bank.senders.contains(where: chosen.contains) }, set: { setSenders(bank.senders, on: $0) }))
                }
                if banks.isEmpty {
                    Text("No suggested banks for this country yet. Add the name your bank's alerts come from below.")
                        .rdText(.detail).foregroundStyle(Theme.muted)
                }
                ForEach(own, id: \.self) { sender in
                    HStack {
                        Text(sender).rdText(.cardTitle)
                        Spacer()
                        Button("Remove") { setSenders([sender], on: false) }.rdText(.detail).foregroundStyle(Theme.destructive)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 54).rdPanel(padding: 0)
                }
                Field(label: "Add a sender") {
                    HStack {
                        TextField("e.g. MyBankAlert", text: $newSender).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Add") {
                            setSenders([newSender.trimmingCharacters(in: .whitespaces)], on: true)
                            newSender = ""
                        }
                        .foregroundStyle(Theme.primary)
                        .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Redesign.footnote("Type the name your bank's alerts come from exactly as it appears in Messages. Messages from anyone else are ignored. With no banks chosen, any message that reads like a purchase is saved.")
                    .padding(.horizontal, 4)
            }
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 0) {
                Redesign.overline("Bank SMS alerts")
                VStack(alignment: .leading, spacing: 14) {
                    // One ready-made shortcut for every country: it listens for the ways banks write currencies
                    Button("Add the bank alerts automation") { Task { openURL(await Self.resolved(Self.bankAlertShortcut)) } }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("addBankAutomation")
                    Text("Opens Shortcuts with it ready: tap Add Shortcut, and turn on its automation if Shortcuts asks. It runs when a message mentions money.")
                        .rdText(.detail).foregroundStyle(Theme.muted)
                    Button(byHand ? "Hide the steps" : "Set it up by hand instead") { withAnimation { byHand.toggle() } }
                        .rdText(.detail).foregroundStyle(Theme.primary)
                    if byHand { Steps(steps: manualSteps) }
                }
                .rdPanel()
                lastSeen(app.store.lastBankMessage.map { ($0.date, $0.summary) }, label: "Last alert",
                         none: "No alert has reached Nokael Money yet. If your bank has texted since you set this up, open the automation and check it's on and set to Run Immediately.")
                Redesign.footnote("Messages are read on this iPhone and never leave it. Only the purchase is saved, not the message. One-time codes, declined payments and offers are ignored.")
                    .padding(.top, 10).padding(.horizontal, 4).padding(.bottom, 24)
            }
        }

        private var tryIt: some View {
            VStack(alignment: .leading, spacing: 12) {
                Redesign.overline("Test a message").padding(.bottom, -12)
                Field(label: "Paste a bank message") {
                    TextField("Message", text: $testText, axis: .vertical).lineLimit(3...6).padding(.vertical, 12)
                        .accessibilityIdentifier("captureTestMessage")
                }
                Field(label: "Sender, as it shows in Messages (optional)") {
                    TextField("e.g. ADCBAlert", text: $testSender).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Test it") { Task { await test() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("captureTestButton")
                if let testRun { TraceSteps(trace: testRun, hidden: hidesTraces).rdPanel() }
                Redesign.footnote("Goes through every step a real alert does, including your banks, Nokael Plus, duplicates and which account, without Apple Intelligence. Nothing is saved.")
                    .padding(.horizontal, 4)
            }
            .padding(.bottom, 24)
        }

        /// The steps name amounts, shops, accounts and references, so any Privacy Mode hides them
        private var hidesTraces: Bool { app.hidesAmounts || app.hidesDetails }

        /// What became of the last few alerts and taps, step by step
        @ViewBuilder private var history: some View {
            let traces = app.store.captureTraces
            VStack(alignment: .leading, spacing: 0) {
                Redesign.overline("What happened to each one")
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
                                    Image(systemName: trace.saved ? "checkmark.circle.fill" : "exclamationmark.circle")
                                        .foregroundStyle(trace.saved ? Theme.primary : Theme.muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(trace.source.title) · \(trace.date.formatted(.relative(presentation: .named)))").rdText(.detailStrong)
                                        Text(private: hidesTraces ? "Hidden in Privacy Mode." : trace.headline).rdText(.caption)
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

        /// A shared shortcut carrying the Message trigger and the Read Bank Message action. The link
        /// goes through our site (legal-docs/_redirects), so a new version ships without an app update.
        static let bankAlertShortcut = URL(string: "https://mymoney-legal-docs.pages.dev/s/bank-alerts")!

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
    /// -screen forecast|reports|payday|choose|guide|capture|settings|add [-addKind income]|ask|debtpay|loan|paywall|import|person
    enum DebugScreens {
        @MainActor static func open(in app: AppModel) {
            let defaults = UserDefaults.standard
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
