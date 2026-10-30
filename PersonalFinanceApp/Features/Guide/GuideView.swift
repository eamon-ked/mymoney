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
