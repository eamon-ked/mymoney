//
//  AIViews.swift
//  Nokael Money
//
//  The conversation behind Ask about your money; its screen is in
//  Redesign/RedesignInsights.swift.
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
    /// Bumped by New conversation, so an answer still arriving for the old one is dropped
    private var generation = 0

    /// `answered` is told whether an answer came back, so a free question is only used up by one that did
    func ask(_ question: String, digest: FinanceDigest, plus: Bool, answered: @escaping (Bool) -> Void = { _ in }) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        if session == nil {
            engine = AppleIntelligence.engine(plus: plus)
            session = MoneyAI.assistantSession(digest, engine: engine)
        }
        messages.append(Message(fromPerson: true, text: question))
        messages.append(Message(fromPerson: false, text: ""))
        let index = messages.count - 1
        let turn = generation
        busy = true
        task = Task {
            var ok = false
            do {
                try await stream(question, into: index, turn: turn)
                ok = true
            } catch is CancellationError {
            } catch where engine == .cloud && turn == generation {
                // Offline, out of today's allowance or not available: carry on, on this iPhone
                engine = .onDevice
                session = MoneyAI.assistantSession(digest, engine: .onDevice)
                do {
                    try await stream(question, into: index, turn: turn)
                    ok = true
                } catch is CancellationError {
                } catch {
                    fail(index, error, turn: turn)
                }
            } catch {
                fail(index, error, turn: turn)
            }
            // Only the conversation that asked hears back; New conversation already reset everything
            guard turn == generation else { return }
            busy = false
            answered(ok)
        }
    }

    private func stream(_ question: String, into index: Int, turn: Int) async throws {
        guard let session else { return }
        for try await partial in session.streamResponse(to: question) {
            try Task.checkCancellation()
            guard turn == generation, messages.indices.contains(index) else { throw CancellationError() }
            messages[index].text = partial.content
        }
    }

    private func fail(_ index: Int, _ error: Error, turn: Int) {
        guard turn == generation, messages.indices.contains(index) else { return }
        messages[index].text = AppleIntelligence.message(for: error)
        messages[index].failed = true
        // A full context window can't recover; the next question starts fresh
        session = nil
    }

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        messages = []
        session = nil
        busy = false
    }
}

#endif
