//
//  GuideView.swift
//  Nokael Money
//
//  "How do I…?" Type a question, or just say what happened ("I got my salary,
//  20,000"), and the guide shows the steps with a button that does it. Topics
//  are matched by keywords so it works on every iPhone and for free; with
//  Apple Intelligence it also answers in its own words, using only these topics.
//

import SwiftUI
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something the guide can open for the person
enum GuideAction: Hashable {
    case add(AddKind)
    case importStatement
    case capture
    case tab(AppTab)
    case backup
    case payDebt
    case addLoan
}

struct GuideTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let steps: [String]
    let tip: String?
    let action: GuideAction?
    let actionTitle: String?
    let keywords: [String]
}

enum AppGuide {
    static let topics: [GuideTopic] = [
        GuideTopic(id: "income", title: "Add your salary or other income", symbol: "arrow.down.circle.fill",
                   steps: ["Tap Add and choose “I received money”.",
                           "Enter the amount, choose the kind of income (for example Salary) and the account it was paid into.",
                           "Tap Save. Your balance and safe-to-spend update straight away."],
                   tip: "Paid every month? Open More options and turn on Repeats, so next month's salary shows under Bills as expected.",
                   action: .add(.income), actionTitle: "Add income now",
                   keywords: ["salary", "income", "paid", "pay", "received", "receive", "got", "earn", "wage", "bonus", "deposit", "money in"]),
        GuideTopic(id: "expense", title: "Add something you spent", symbol: "arrow.up.right.circle.fill",
                   steps: ["Tap Spent on Home, or Add at the top right and choose “I spent money”.",
                           "Enter the amount, what it was for and the account it was paid from.",
                           "Tap Save."],
                   tip: "Faster: say “Log spending in Nokael Money” to Siri, then “45 at Carrefour”.",
                   action: .add(.expense), actionTitle: "Add an expense now",
                   keywords: ["spent", "spend", "expense", "bought", "buy", "purchase", "paid for", "cost", "lunch", "groceries"]),
        GuideTopic(id: "import", title: "Import a bank statement", symbol: "square.and.arrow.down.fill",
                   steps: ["In your bank's app or website, open Statements and download the period you want as CSV (sometimes called Excel or spreadsheet). Save it to Files.",
                           "In Nokael Money, open the Accounts tab and tap the account the statement is for.",
                           "Tap Import a statement (CSV), then Choose CSV file, and pick the file.",
                           "Check the rows. Ones already recorded are skipped. Tap Add."],
                   tip: "A PDF statement can't be read. If your bank only gives PDFs, add entries yourself or set up bank SMS capture.",
                   action: .importStatement, actionTitle: "Import a statement now",
                   keywords: ["import", "statement", "csv", "excel", "spreadsheet", "bank file", "download", "history", "past", "old transactions"]),
        GuideTopic(id: "capture", title: "Save Apple Pay purchases and bank SMS automatically", symbol: "wallet.pass.fill",
                   steps: ["Open Settings (the gear on Home), then Siri & automatic capture.",
                           "Follow the steps for Apple Pay: one Shortcuts automation, set up once.",
                           "For bank alerts, tick your bank, then follow the SMS steps.",
                           "New purchases appear on Home marked New. Tap one to check it."],
                   tip: "iOS doesn't let any app read old messages; capture starts from the moment you set it up. Use a statement import for earlier ones.",
                   action: .capture, actionTitle: "Set it up now",
                   keywords: ["apple pay", "wallet", "sms", "message", "messages", "alert", "automatic", "auto", "sync", "card", "siri", "voice"]),
        GuideTopic(id: "loan", title: "Pay a loan or credit card", symbol: "creditcard.fill",
                   steps: ["Tap + at the top right and choose “I paid a loan or credit card”.",
                           "Pick the loan or card if you have more than one.",
                           "Enter what you paid and the account it came from, then tap Record.",
                           "What you owe goes down by the payment minus interest, which is worked out for you."],
                   tip: "Haven't added the loan yet? The same button asks for what you owe and the monthly payment first.",
                   action: .payDebt, actionTitle: "Pay a loan or card now",
                   keywords: ["loan", "car loan", "personal loan", "mortgage", "credit card", "card payment", "installment", "instalment", "emi", "debt", "owe", "repay", "repayment"]),
        GuideTopic(id: "transfer", title: "Move money between your accounts", symbol: "arrow.left.arrow.right.circle.fill",
                   steps: ["Tap Add at the top right and choose “I moved money between my accounts”.",
                           "Choose where it came from and where it went, then tap Save."],
                   tip: "Paying off a credit card from your bank account is a transfer, not spending.",
                   action: .add(.transfer), actionTitle: "Add a transfer now",
                   keywords: ["transfer", "move", "credit card payment", "pay my card", "savings account", "between"]),
        GuideTopic(id: "fix", title: "Change or delete an entry", symbol: "pencil.circle.fill",
                   steps: ["Open the Activity tab and tap the entry.",
                           "Tap Edit to change it, or Delete at the bottom.",
                           "Every change is kept in its history."],
                   tip: nil, action: .tab(.activity), actionTitle: "Open Activity",
                   keywords: ["edit", "change", "delete", "remove", "wrong", "mistake", "fix", "undo"]),
        GuideTopic(id: "balance", title: "Correct an account's balance", symbol: "slider.horizontal.3",
                   steps: ["Tap Add at the top right and choose “A balance is wrong”.",
                           "Pick the account and enter what it really holds today.",
                           "Add a short reason and tap Save."],
                   tip: "To compare with a statement instead, open the account in Accounts and tap Check against a statement.",
                   action: .add(.adjustment), actionTitle: "Correct a balance now",
                   keywords: ["balance", "wrong balance", "correct", "adjust", "reconcile", "doesn't match", "bank says"]),
        GuideTopic(id: "addLoan", title: "Add a loan or credit card", symbol: "creditcard.fill",
                   steps: ["Tap Add at the top right and choose “I have a loan or credit card”.",
                           "Enter what you still owe today and the monthly payment.",
                           "Pick the day it's paid, and it's added to your bills automatically."],
                   tip: "The interest rate is optional. Each payment then lowers what you owe.",
                   action: .addLoan, actionTitle: "Add a loan or card now",
                   keywords: ["add a loan", "add my loan", "new loan", "took a loan", "got a loan", "add a card", "add credit card", "new credit card", "mortgage", "car loan", "personal loan"]),
        GuideTopic(id: "account", title: "Add a bank account or cash", symbol: "building.columns.fill",
                   steps: ["Open the Accounts tab.",
                           "Tap New account at the top left.",
                           "Pick the type, name it, enter today's balance and tap Add."],
                   tip: nil, action: .tab(.accounts), actionTitle: "Open Accounts",
                   keywords: ["new account", "add bank", "add account", "cash", "wallet account", "savings account"]),
        GuideTopic(id: "budget", title: "Plan your spending for the month", symbol: "chart.pie.fill",
                   steps: ["Open the Budget tab.",
                           "Tap a category and enter how much you plan to spend this month.",
                           "Next month, use Copy last month's plan to start quickly."],
                   tip: nil, action: .tab(.budget), actionTitle: "Open Budget",
                   keywords: ["budget", "plan spending", "limit", "category", "categories", "overspent"]),
        GuideTopic(id: "bills", title: "Add a bill or expected income", symbol: "calendar.badge.plus",
                   steps: ["On Home, tap See all next to Coming up.",
                           "Tap + at the top right, then Bill or Expected income.",
                           "Enter the name, amount, date and how often it repeats, then tap Save.",
                           "When it's paid, tap it under Coming up on Home to mark it paid."],
                   tip: "Bills are set aside from safe-to-spend before they're due.",
                   action: .tab(.home), actionTitle: "Open Home",
                   keywords: ["bill", "bills", "rent", "dewa", "subscription", "due", "recurring", "every month", "expected"]),
        GuideTopic(id: "goal", title: "Save for something", symbol: "target",
                   steps: ["Open the Budget tab and scroll to Savings.",
                           "Tap Add, then Savings goal.",
                           "Name it, set the target and the account it's kept in, then tap Save."],
                   tip: nil, action: .tab(.budget), actionTitle: "Open Budget",
                   keywords: ["save", "saving", "goal", "target", "set aside"]),
        GuideTopic(id: "safe", title: "What “Safe to spend” means", symbol: "checkmark.shield.fill",
                   steps: ["It's the money in your spending accounts, minus bills due before your next payday, money set aside and what's left in your budget categories.",
                           "Tap the blue card on Home, then How is this worked out?, to see every part."],
                   tip: nil, action: .tab(.home), actionTitle: "Open Home",
                   keywords: ["safe to spend", "how much can i spend", "left", "afford", "worked out"]),
        GuideTopic(id: "backup", title: "Back up your data", symbol: "externaldrive.fill",
                   steps: ["Open Settings (the gear on Home).",
                           "Tap Save a backup and keep the file in iCloud Drive or Files.",
                           "On a new iPhone, use Restore from a backup."],
                   tip: "Your data lives only on this iPhone, so keep a recent backup.",
                   action: .backup, actionTitle: nil,
                   keywords: ["backup", "back up", "restore", "new phone", "export", "lose"]),
    ]

    /// Best topics for what the person typed, most relevant first
    static func match(_ text: String) -> [GuideTopic] {
        let lower = text.lowercased()
        let scored = topics.map { topic in
            (topic, topic.keywords.reduce(0) { $0 + (lower.contains($1) ? ($1.contains(" ") ? 3 : 2) : 0) }
                + (lower.contains(topic.title.lowercased()) ? 4 : 0)
                + (topic.id == "addLoan" && addsALoan(lower) ? 6 : 0))
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// "How do I add my car loan" is about adding one, "I paid my car loan" about paying it
    private static func addsALoan(_ lower: String) -> Bool {
        ["loan", "card", "mortgage", "debt"].contains(where: lower.contains)
            && ["add", "new", "took", "got a", "have a", "set up", "setup", "enter", "where"].contains(where: lower.contains)
            && !["pay", "paid", "instal"].contains(where: lower.contains)
    }

    /// Every topic as plain text, for the on-device model
    static var reference: String {
        topics.map { t in
            "\(t.title):\n" + t.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                + (t.tip.map { "\nTip: \($0)" } ?? "")
        }.joined(separator: "\n\n")
    }
}

struct GuideView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectTab) private var selectTab
    @State private var question = ""
    @State private var asked = ""
    @State private var answer: String?
    @State private var thinking = false
    @State private var draft: (kind: AddKind, entry: DraftEntry)?
    @State private var adding: AddRequest?
    @State private var importAccount: ImportRequest?
    @State private var paywall: PlusFeature?
    @State private var expanded: String?
    @State private var payingDebt = false
    @State private var addingLoan = false
    @State private var payday: PaydayRequest?
    @State private var paydaySaid: Money??

    struct AddRequest: Identifiable { let id = UUID(); let kind: AddKind; let draft: DraftEntry? }
    struct ImportRequest: Identifiable { let id: UUID }
    struct PaydayRequest: Identifiable { let id = UUID(); let said: Money? }

    var initialQuestion = ""

    private var matches: [GuideTopic] { asked.isEmpty ? [] : AppGuide.match(asked) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Ask, or say what happened", text: $question, axis: .vertical)
                            .lineLimit(1...3)
                            .submitLabel(.go)
                            .onSubmit(ask)
                        Button(action: ask) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Ask")
                    }
                } footer: {
                    Text("For example “I received my salary”, “how do I import a statement” or “spent 45 at Carrefour”.")
                }

                if let said = paydaySaid { paydaySection(said) }
                if let draft { draftSection(draft.kind, draft.entry) }

                if thinking || answer != nil {
                    Section {
                        if let answer {
                            Text(answer).font(.subheadline)
                        } else {
                            HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
                        }
                    } header: {
                        AIBadge(text: "Answer")
                    }
                }

                if !asked.isEmpty && matches.isEmpty && answer == nil && !thinking && draft == nil {
                    Section {
                        Text("I couldn't find that. Try different words, or pick a topic below.").foregroundStyle(.secondary)
                    }
                }

                // Payday already does it; the manual steps would only distract
                ForEach(paydaySaid == nil ? Array(matches.prefix(2)) : []) { topic in topicSection(topic, open: true) }

                Section(asked.isEmpty ? "How do I…" : "Other topics") {
                    ForEach(AppGuide.topics.filter { t in !matches.prefix(2).contains(t) }) { topic in
                        DisclosureGroup(isExpanded: Binding(get: { expanded == topic.id },
                                                            set: { expanded = $0 ? topic.id : nil })) {
                            topicBody(topic)
                        } label: {
                            Label(topic.title, systemImage: topic.symbol)
                        }
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $adding) { request in EntryEditor(kind: request.kind, prefill: request.draft) }
            .sheet(item: $importAccount) { ImportStatementView(accountId: $0.id) }
            .sheet(isPresented: $payingDebt) { AddChooser(focus: .debts) }
            .sheet(isPresented: $addingLoan) { NewLoanSheet() }
            .sheet(item: $payday) { PaydaySheet(said: $0.said) }
            .paywall($paywall)
            .onAppear {
                if !initialQuestion.isEmpty && asked.isEmpty { question = initialQuestion; ask() }
            }
        }
    }

    // MARK: - Pieces

    private func topicSection(_ topic: GuideTopic, open: Bool) -> some View {
        Section {
            topicBody(topic)
        } header: {
            Label(topic.title, systemImage: topic.symbol)
        }
    }

    @ViewBuilder private func topicBody(_ topic: GuideTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SetupSteps(steps: topic.steps)
            if let tip = topic.tip {
                Label(tip, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        if let action = topic.action, let title = topic.actionTitle {
            actionButton(action, title: title)
        }
    }

    @ViewBuilder private func actionButton(_ action: GuideAction, title: String) -> some View {
        switch action {
        case .add(let kind):
            Button { adding = AddRequest(kind: kind, draft: nil) } label: { Label(title, systemImage: "plus.circle.fill") }
        case .importStatement:
            let accounts = store.snapshot.accounts.filter { $0.kind.isBalanceSheet && !$0.archived }
            if !plus.isPlus {
                Button { paywall = .statementImport } label: {
                    HStack { Label(title, systemImage: "square.and.arrow.down"); Spacer(); PlusBadge() }
                }
            } else if accounts.count == 1, let only = accounts.first {
                Button { importAccount = ImportRequest(id: only.id) } label: { Label(title, systemImage: "square.and.arrow.down") }
            } else {
                Menu {
                    ForEach(accounts, id: \.id) { a in
                        Button(a.name) { importAccount = ImportRequest(id: a.id) }
                    }
                } label: {
                    Label("\(title): choose the account", systemImage: "square.and.arrow.down")
                }
            }
        case .capture:
            NavigationLink { CaptureSetupView() } label: { Label(title, systemImage: "wallet.pass") }
        case .tab(let tab):
            Button { selectTab(tab); dismiss() } label: { Label(title, systemImage: "arrow.right.circle") }
        case .backup:
            EmptyView()
        case .payDebt:
            Button { payingDebt = true } label: { Label(title, systemImage: "creditcard") }
        case .addLoan:
            Button { addingLoan = true } label: { Label(title, systemImage: "creditcard") }
        }
    }

    private func paydaySection(_ said: Money?) -> some View {
        let plan = PaydayPlan.make(store.snapshot, said: said)
        let account = store.snapshot.account(plan.accountId)?.name ?? "your account"
        return Section {
            Button { payday = PaydayRequest(said: said) } label: {
                HStack {
                    Image(systemName: "banknote.fill").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(plan.alreadyReceived != nil && said == nil ? "Salary already recorded this month"
                             : "Record \(plan.amount.compact) salary into \(account)").font(.headline)
                        Text(plan.item == nil ? "Then plan the month" : "From your plan, then budget and goals for the month")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Payday")
        } footer: {
            Text("You'll see everything before it's saved, and can change the amount.")
        }
    }

    private func draftSection(_ kind: AddKind, _ entry: DraftEntry) -> some View {
        Section {
            let amount = entry.amount.map { MoneyFormat.string(Money($0, currency: store.currency)) } ?? ""
            let what = [entry.memo, entry.category].compactMap { $0 }.filter { !$0.isEmpty }.first ?? kind.title
            Button { adding = AddRequest(kind: kind, draft: entry) } label: {
                HStack {
                    Image(systemName: kind.symbol).foregroundStyle(kind == .income ? .green : Palette.home)
                    VStack(alignment: .leading) {
                        Text("Add \(kind.title.lowercased()): \(amount)").font(.headline)
                        Text(what).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Add it now")
        } footer: {
            Text("Opens the form filled in. Check the account, then tap Save.")
        }
    }

    // MARK: - Asking

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        asked = text
        answer = nil
        draft = nil
        paydaySaid = nil
        expanded = nil
        let snapshot = store.snapshot
        // "I got my salary 20,000" is something to add, not only a question. Loan
        // payments and transfers have their own forms, which the topic opens.
        let topTopic = AppGuide.match(text).first?.id ?? ""
        if PaydayPlan.mentionsSalary(text) {
            // Salary uses what's saved in Plan, not guesses from the sentence
            paydaySaid = .some(AlertParser.spoken(text, homeCurrency: store.currency, date: Date())?.amount)
        } else if !["loan", "transfer", "balance"].contains(topTopic),
           let spoken = AlertParser.spoken(text, homeCurrency: store.currency, date: Date()) {
            var entry = DraftEntry()
            let lower = text.lowercased()
            let incoming = spoken.direction == .received || lower.contains("salary") || lower.contains("paid me")
            entry.kind = incoming ? .income : .expense
            entry.amount = spoken.amount.decimal
            let categories = incoming ? snapshot.incomeCategories : snapshot.expenseCategories
            if lower.contains("salary") { entry.category = categories.first { $0.name.lowercased().contains("salary") }?.name }
            entry.memo = spoken.merchant.isEmpty ? (entry.category ?? "") : spoken.merchant
            draft = (entry.kind, entry)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isReady, paydaySaid == nil {
            thinking = true
            Task {
                defer { thinking = false }
                let session = LanguageModelSession(instructions: """
                    You are the help guide inside Nokael Money, a budgeting app. Answer how-to questions in at most four short numbered steps, \
                    using only the instructions below and the exact button names in them. If the person describes money they received or spent, \
                    tell them how to add it. If the instructions don't cover it, say so briefly. No financial advice.

                    \(AppGuide.reference)
                    """)
                if let reply = try? await session.respond(to: text, options: GenerationOptions(sampling: .greedy)) {
                    answer = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        #endif
    }
}

/// The Home and Settings way in
struct HelpButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Text("Help").font(.body.weight(.semibold)) }
            .accessibilityLabel("Help")
            .sheet(isPresented: $showing) { GuideView() }
    }
}

/// Shown once after setup: the three things that make the rest obvious
struct WelcomeTour: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("3 things to know").font(.largeTitle.bold()).padding(.top, 40)
            point("cart.fill", .blue, "Spent, Received, Pay a loan",
                  "The big buttons on Home. Tap one whenever money comes in or goes out.")
            point("plus.circle.fill", .green, "Add, at the top right",
                  "On every screen. It asks what happened and takes you to the right place.")
            point("questionmark.circle.fill", .purple, "Help, at the top left of Home",
                  "Stuck? Type your question or just what happened, like “I got my salary”.")
            Spacer()
            Button { dismiss() } label: {
                Text("Got it").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title).foregroundStyle(color).frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
