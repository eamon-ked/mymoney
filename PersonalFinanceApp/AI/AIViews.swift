//
//  AIViews.swift
//  Nokael Money
//
//  Screens and cards powered by Apple Intelligence: Ask about your money,
//  the month in brief on Home, and the month's story in Reports.
//

import SwiftUI
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

// MARK: - Ask about your money

@available(iOS 26.0, *)
@MainActor @Observable
final class AskModel {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromPerson: Bool
        var text: String
        var failed = false
    }

    private(set) var messages: [Message] = []
    private(set) var busy = false
    private var session: LanguageModelSession?
    private var task: Task<Void, Never>?

    func ask(_ question: String, digest: FinanceDigest) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        if session == nil { session = MoneyAI.assistantSession(digest) }
        guard let session else { return }
        messages.append(Message(fromPerson: true, text: question))
        messages.append(Message(fromPerson: false, text: ""))
        let index = messages.count - 1
        busy = true
        task = Task {
            do {
                for try await partial in session.streamResponse(to: question) {
                    messages[index].text = partial.content
                }
            } catch is CancellationError {
            } catch {
                messages[index].text = AppleIntelligence.message(for: error)
                messages[index].failed = true
                // A full context window can't recover; the next question starts fresh
                self.session = nil
            }
            busy = false
        }
    }

    func reset() {
        task?.cancel()
        messages = []
        session = nil
        busy = false
    }
}

@available(iOS 26.0, *)
struct AskMoneyView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model = AskModel()
    @State private var question = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "How much can I spend this week?",
        "What did I spend most on this month?",
        "Which bills are due soon?",
        "How does this month compare with last month?",
        "Am I over budget anywhere?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { intro }
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.text) { _, _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !model.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.reset() } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New conversation")
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIBadge()
            Text("Ask about your money").font(.title2.bold())
            Text("Answers come from your accounts, budget and bills, worked out privately on this iPhone. Nothing is sent anywhere.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { s in
                Button { send(s) } label: {
                    Text(s).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func bubble(_ message: AskModel.Message) -> some View {
        HStack {
            if message.fromPerson { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty {
                    ProgressView().padding(.vertical, 2)
                } else {
                    Text(LocalizedStringKey(message.text)).textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(message.fromPerson ? Palette.home : (message.failed ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))))
            .foregroundStyle(message.fromPerson ? .white : .primary)
            if !message.fromPerson { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything about your money", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(question) }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
            Button { send(question) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        model.ask(text, digest: FinanceDigest(store.snapshot))
        question = ""
    }
}

// MARK: - The month in brief (Home)

@available(iOS 26.0, *)
struct InsightCard: View {
    @Environment(LedgerStore.self) private var store
    let ask: () -> Void
    @State private var insight: MonthInsight?
    @State private var loading = false
    @State private var failed = false
    /// Insights are worked out once per data change, not on every appearance
    @State private var builtForRevision: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AIBadge(text: "Your month in brief")
                Spacer()
                if !loading {
                    Button { Task { await load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityLabel("Refresh summary")
                }
            }
            if let insight {
                Text(insight.headline).font(.subheadline)
                ForEach(insight.tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
                }
            } else if loading {
                HStack(spacing: 8) { ProgressView(); Text("Looking at your month…").font(.subheadline).foregroundStyle(.secondary) }
            } else if failed {
                Text("Couldn't make a summary right now.").font(.subheadline).foregroundStyle(.secondary)
            }
            Button(action: ask) { Label("Ask about your money", systemImage: "bubble.left.and.text.bubble.right") }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .task(id: store.revision) { await load(force: false) }
    }

    private func load(force: Bool) async {
        guard force || builtForRevision != store.revision else { return }
        if !force {
            // Let a run of quick edits settle before reading the month again
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        loading = true
        failed = false
        defer { loading = false }
        do {
            insight = try await MoneyAI.insight(FinanceDigest(store.snapshot))
            builtForRevision = store.revision
        } catch is CancellationError {
        } catch {
            failed = insight == nil
        }
    }
}

// MARK: - The month's story (Reports)

@available(iOS 26.0, *)
struct MonthStoryView: View {
    @Environment(LedgerStore.self) private var store
    let monthKey: String
    @State private var text = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIBadge(text: "What happened this month")
            if !text.isEmpty {
                Text(text).font(.subheadline)
            } else if let error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
            }
            if !loading {
                Button(text.isEmpty ? "Explain this month" : "Explain again") { Task { await explain() } }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
            } else if text.isEmpty {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
        .onChange(of: monthKey) { _, _ in text = ""; error = nil }
    }

    private func explain() async {
        loading = true
        error = nil
        text = ""
        defer { loading = false }
        do {
            for try await partial in MoneyAI.monthStory(FinanceDigest(store.snapshot), monthKey: monthKey) {
                text = partial.content
            }
        } catch {
            self.error = AppleIntelligence.message(for: error)
        }
    }
}

#endif

// MARK: - Settings

struct AppleIntelligenceSection: View {
    @AppStorage(AppleIntelligence.enabledKey) private var enabled = true

    var body: some View {
        let system = AppleIntelligence.systemStatus
        Section {
            if system == .ready {
                Toggle("Use Apple Intelligence", isOn: $enabled)
            } else {
                LabeledContent("Apple Intelligence", value: "Unavailable")
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text(system == .ready
                 ? "Quick add from a sentence, category suggestions, a monthly summary and answers to your questions. Runs privately on this iPhone, free and offline. Always check before saving."
                 : system.explanation)
        }
    }
}
