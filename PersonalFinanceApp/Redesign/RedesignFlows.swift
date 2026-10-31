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
            review = StatementReview(accountId: id, store: app.store)
        }
    }

    private struct ImportReview: View {
        @Bindable var review: StatementReview
        @Environment(AppModel.self) private var app
        @State private var choosingFile = false
        @State private var showMatched = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                if let added = review.added {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.primary)
                        Text(added == 0 ? "Nothing new to add" : "Added \(added) \(added == 1 ? "entry" : "entries")").rdText(.heading)
                        Text("Check the balance against your statement to be sure everything's in.")
                            .rdText(.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    Button("Done") { app.close() }.buttonStyle(PrimaryButtonStyle())
                } else if review.fileText == nil {
                    intro
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
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): review.load(url)
                case .failure: review.error = "Couldn't open that file."
                }
            }
        }

        @ViewBuilder private var intro: some View {
            IconBox(symbol: "doc.text.magnifyingglass")
            Text("Bring in \(app.hidesAccountNames ? "this account" : review.account?.name ?? "this account")'s statement").rdText(.heading)
            Text("Download a statement from your bank's website or app as a CSV file, then choose it here. Rows you've already recorded are recognised and left alone.")
                .rdText(.body).foregroundStyle(Theme.muted)
            Button("Choose CSV file") { choosingFile = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("chooseStatement")
            Problem(text: review.error)
            Redesign.explainer("The file needs a header row with a date, a description and either an amount or separate money in and money out columns. It stays on this iPhone.")
        }

        @ViewBuilder private var rows: some View {
            DetailCard {
                DetailRow(label: "File", value: review.fileName)
                Redesign.hairline
                DetailRow(label: "Rows", value: "\(review.rows.count)")
                Redesign.hairline
                DetailRow(label: "Already recorded", value: "\(review.matched.count)")
            }
            ToggleRow(title: "Purchases show as positive numbers",
                      detail: "Card statements often list purchases without a minus sign. Turn this on if money out appears as money in below.",
                      isOn: $review.flipSigns)
            Problem(text: review.error)

            if review.suggesting > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suggesting categories… \(review.suggesting) to go").rdText(.detail).foregroundStyle(Theme.muted)
                }
            } else if !review.unsorted.isEmpty {
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
            } else {
                Divided(items: review.inbox) { row in
                    InboxRow(row: row, target: binding(row), skipped: skipBinding(row),
                             options: review.options(for: row), label: review.label(for: row))
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
                    .disabled(review.ready.isEmpty)
                    .accessibilityIdentifier("addImported")
            }
        }

        /// One choice for every ticked row that has none yet
        @ViewBuilder private var sortTheRest: some View {
            let out = review.unsorted.filter(\.amount.isNegative)
            let into = review.unsorted.filter { !$0.amount.isNegative }
            VStack(alignment: .leading, spacing: 10) {
                Text("\(review.unsorted.count) still need a category").rdText(.cardTitle)
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

    /// One statement row waiting for a decision
    private struct InboxRow: View {
        let row: StatementRow
        @Binding var target: LedgerStore.ImportedRow.Target?
        @Binding var skipped: Bool
        let options: [(String, [StatementReview.Option])]
        let label: String?
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
                    if skipped {
                        Text("Left out · tick to add it").rdText(.captionStrong).foregroundStyle(Theme.muted)
                    } else {
                        Menu {
                            ForEach(options, id: \.0) { group in
                                Section(group.0) {
                                    ForEach(group.1) { option in
                                        Button { target = option.target } label: { Label(option.title, systemImage: option.symbol) }
                                    }
                                }
                            }
                        } label: {
                            Text(label ?? "Choose a category")
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
        @State private var testResult: String?
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
                    // The ready-made shortcut listens for one keyword; everywhere else it's set up by hand with the local keyword
                    if BankSenders.keyword(region: region) == Self.bankAlertShortcutKeyword {
                        Button("Add the bank alerts automation") { Task { openURL(await Self.resolved(Self.bankAlertShortcut)) } }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("addBankAutomation")
                        Text("Opens Shortcuts with it ready: tap Add Shortcut, and turn on its automation if Shortcuts asks. It runs whenever a message mentions \(Self.bankAlertShortcutKeyword).")
                            .rdText(.detail).foregroundStyle(Theme.muted)
                        Button(byHand ? "Hide the steps" : "Set it up by hand instead") { withAnimation { byHand.toggle() } }
                            .rdText(.detail).foregroundStyle(Theme.primary)
                        if byHand { Steps(steps: manualSteps) }
                    } else {
                        Text("Set up the automation in Shortcuts:").rdText(.detailStrong)
                        Steps(steps: manualSteps)
                    }
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
                Redesign.overline("Try a message").padding(.bottom, -12)
                Field(label: "Paste a bank message") {
                    TextField("Message", text: $testText, axis: .vertical).lineLimit(3...6).padding(.vertical, 12)
                }
                Button("Read it") { Task { await test() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let testResult { Text(private: testResult).rdText(.detail).foregroundStyle(Theme.muted) }
                Redesign.footnote("Shows what would be saved. Nothing is added.").padding(.horizontal, 4)
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
        static let bankAlertShortcutKeyword = "AED"
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
                "Set Message to Shortcut Input, and Sender to Shortcut Input › Sender, then go back to save.",
            ]
        }

        private func test() async {
            guard let capture = await CaptureService.read(message: testText, homeCurrency: app.currency, date: Date()) else {
                testResult = "No purchase or deposit found. This message would be ignored."
                return
            }
            var parts = [(capture.direction == .spent ? "Spent " : "Received ") + MoneyFormat.string(capture.amount)]
            if !capture.merchant.isEmpty { parts.append((capture.direction == .spent ? "at " : "from ") + capture.merchant) }
            if let card = capture.cardHint { parts.append(cardTitle(card)) }
            if let id = capture.cardHint.flatMap(app.store.linkedAccount(forCard:)) { parts.append("into \(app.accountLabel(id))") }
            testResult = parts.joined(separator: " · ")
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
            hint.count == 4 && hint.allSatisfy(\.isNumber) ? "Card ending \(hint)" : hint.capitalized
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
