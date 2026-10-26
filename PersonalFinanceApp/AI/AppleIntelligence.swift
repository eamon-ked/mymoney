//
//  AppleIntelligence.swift
//  Nokael Money
//
//  Apple's on-device language model (FoundationModels, iOS 26+): free, private,
//  works offline. Every AI feature checks `AppleIntelligence.isReady` first and
//  the app works the same without it, just with fewer shortcuts.
//

import Foundation
import SwiftUI
import NokaelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligence {
    /// Person's choice in Settings; on by default where the device supports it
    static let enabledKey = "appleIntelligenceEnabled"

    enum Status: Equatable {
        case ready
        case turnedOff          // switched off in this app's Settings
        case notEnabled         // Apple Intelligence is off in iOS Settings
        case downloading        // model still getting ready
        case unsupportedDevice
        case needsNewerIOS

        var explanation: String {
            switch self {
            case .ready: return "Ready. Runs privately on this iPhone, even offline."
            case .turnedOff: return "Turned off for Nokael Money."
            case .notEnabled: return "Turn on Apple Intelligence in the Settings app to use these features."
            case .downloading: return "Apple Intelligence is still downloading. Try again in a little while."
            case .unsupportedDevice: return "This iPhone doesn't support Apple Intelligence."
            case .needsNewerIOS: return "Needs iOS 26 or later."
            }
        }
    }

    /// Whether the model itself can run, ignoring the in-app switch
    static var systemStatus: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable: return .unsupportedDevice
            }
        }
        #endif
        return .needsNewerIOS
    }

    static var status: Status {
        let system = systemStatus
        guard system == .ready else { return system }
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        return enabled ? .ready : .turnedOff
    }

    static var isReady: Bool { status == .ready }

    /// Shared rules for every prompt: plain words, real numbers only
    static let baseInstructions = """
        You are the assistant inside Nokael Money, a personal budgeting app. \
        Be brief, friendly and plain-spoken. Use only the figures you are given or that tools return; \
        never invent amounts, accounts or dates. If you don't have the data, say so. \
        Amounts are already formatted with their currency; repeat them exactly. \
        You give budgeting help, not investment, tax or legal advice.
        """

    static func message(for error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return "That conversation got too long. Start a new one."
            case .guardrailViolation, .refusal: return "Apple Intelligence couldn't answer that. Try asking another way."
            case .unsupportedLanguageOrLocale: return "Apple Intelligence doesn't support this language yet."
            case .assetsUnavailable: return "Apple Intelligence isn't available right now."
            case .rateLimited: return "Apple Intelligence is busy. Try again in a moment."
            default: return "Apple Intelligence couldn't run this time. Try again, or fill it in yourself."
            }
        }
        #endif
        return "Something went wrong. Try again."
    }
}

/// Small sparkle label used wherever an AI shortcut appears
struct AIBadge: View {
    var text = "Apple Intelligence"
    var body: some View {
        Label(text, systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing))
    }
}
