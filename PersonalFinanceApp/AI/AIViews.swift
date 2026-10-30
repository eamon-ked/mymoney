//
//  AIViews.swift
//  Nokael Money
//
//  Screens and cards powered by Apple Intelligence: Ask about your money,
//  and the month's story in Reports.
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
    /// Where the current conversation runs; drops to the iPhone if the cloud can't answer
    private(set) var engine: AIEngine = .onDevice
    private var session: LanguageModelSession?
    private var task: Task<Void, Never>?

    func ask(_ question: String, digest: FinanceDigest, plus: Bool) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        if session == nil {
            engine = AppleIntelligence.engine(plus: plus)
            session = MoneyAI.assistantSession(digest, engine: engine)
        }
        messages.append(Message(fromPerson: true, text: question))
        messages.append(Message(fromPerson: false, text: ""))
        let index = messages.count - 1
        busy = true
        task = Task {
            do {
                try await stream(question, into: index)
            } catch is CancellationError {
            } catch where engine == .cloud {
                // Offline, out of today's allowance or not available: carry on, on this iPhone
                engine = .onDevice
                session = MoneyAI.assistantSession(digest, engine: .onDevice)
                do {
                    try await stream(question, into: index)
                } catch is CancellationError {
                } catch {
                    fail(index, error)
                }
            } catch {
                fail(index, error)
            }
            busy = false
        }
    }

    private func stream(_ question: String, into index: Int) async throws {
        guard let session else { return }
        messages[index].text = ""
        for try await partial in session.streamResponse(to: question) {
            messages[index].text = partial.content
        }
    }

    private func fail(_ index: Int, _ error: Error) {
        messages[index].text = AppleIntelligence.message(for: error)
        messages[index].failed = true
        // A full context window can't recover; the next question starts fresh
        session = nil
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
    @Environment(PlusStore.self) private var plus
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
            Text(AppleIntelligence.engine(plus: plus.isPlus) == .cloud
                 ? "Answered by Apple's larger model on Private Cloud Compute, from your accounts, budget and bills. Apple uses your data only to answer and doesn't keep it."
                 : "Answers come from your accounts, budget and bills, worked out privately on this iPhone. Nothing is sent anywhere.")
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
            .accessibilityIdentifier("askSend")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        model.ask(text, digest: FinanceDigest(store.snapshot), plus: plus.isPlus)
        question = ""
    }
}

#endif

#if canImport(FoundationModels)

// MARK: - The month's story (Reports)

@available(iOS 26.0, *)
struct MonthStoryView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
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
        let digest = FinanceDigest(store.snapshot)
        let engine = AppleIntelligence.engine(plus: plus.isPlus)
        do {
            for try await partial in MoneyAI.monthStory(digest, monthKey: monthKey, engine: engine) {
                text = partial.content
            }
        } catch where engine == .cloud && !(error is CancellationError) {
            // The cloud couldn't answer: tell the story on this iPhone instead
            do {
                for try await partial in MoneyAI.monthStory(digest, monthKey: monthKey, engine: .onDevice) {
                    text = partial.content
                }
            } catch {
                self.error = AppleIntelligence.message(for: error)
            }
        } catch {
            self.error = AppleIntelligence.message(for: error)
        }
    }
}

#endif

// MARK: - Settings

struct AppleIntelligenceSection: View {
    @Environment(PlusStore.self) private var plus
    @AppStorage(AppleIntelligence.enabledKey) private var enabled = true
    @AppStorage(AppleIntelligence.cloudKey) private var cloudOn = true

    var body: some View {
        let system = AppleIntelligence.systemStatus
        let cloud = AppleIntelligence.cloudStatus
        Section {
            if system == .ready {
                Toggle("Use Apple Intelligence", isOn: $enabled)
                // Apple's larger model is a Plus benefit on iOS 27
                if enabled, plus.isPlus, cloud.offered {
                    Toggle("Use Apple's cloud model when online", isOn: $cloudOn)
                        .accessibilityIdentifier("cloudModelToggle")
                    if cloudOn, cloud == .limitReached {
                        Label("Today's limit is used up. Answers come from this iPhone until it resets.", systemImage: "hourglass")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                LabeledContent("Apple Intelligence", value: "Unavailable")
            }
        } footer: {
            if system != .ready {
                Text(system.explanation)
            } else if plus.isPlus, cloud.offered, cloudOn, enabled {
                Text("A summary of your month and answers to your questions use Apple's larger model on Private Cloud Compute when you're online. Apple uses your data only to answer and doesn't keep it. Offline, everything runs on this iPhone. Always check before saving.")
            } else {
                Text("Quick add from a sentence, category suggestions, a summary of your month and answers to your questions. Runs privately on this iPhone, free and offline. Always check before saving.")
            }
        }
    }
}
