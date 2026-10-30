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

/// Where a request runs: on this iPhone, or on Apple's Private Cloud Compute
enum AIEngine: Equatable, Sendable { case onDevice, cloud }

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

    // MARK: - Which model answers

    /// Plus members' choice in Settings; on by default
    static let cloudKey = "useCloudModel"

    enum CloudStatus: Equatable {
        case ready
        case limitReached       // today's allowance on this iCloud account is used up
        case unavailable        // offline, not signed in to iCloud, or not set up for this app
        case needsNewerIOS
        case notSetUp           // this build doesn't include it yet: waiting on Apple's approval

        /// Whether to offer the cloud model at all on this iPhone and build
        var offered: Bool { self != .needsNewerIOS && self != .notSetUp }
    }

    /// Apple's larger model on Private Cloud Compute (iOS 27): needs the internet and has a daily limit per iCloud account.
    ///
    /// Creating the model in an app without Apple's `com.apple.developer.private-cloud-compute` entitlement
    /// stops the app at once, so every use is compiled only when the PRIVATE_CLOUD_COMPUTE flag is set.
    /// Turn it on together with the entitlement, once Apple has approved the app:
    /// add the entitlement to the app's .entitlements file and PRIVATE_CLOUD_COMPUTE to the target's
    /// Active Compilation Conditions (SWIFT_ACTIVE_COMPILATION_CONDITIONS), for Debug and Release.
    static var cloudStatus: CloudStatus {
        #if canImport(FoundationModels) && PRIVATE_CLOUD_COMPUTE
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            guard model.isAvailable else { return .unavailable }
            return model.quotaUsage.isLimitReached ? .limitReached : .ready
        }
        return .needsNewerIOS
        #else
        return .notSetUp
        #endif
    }

    /// The cloud model is a Plus benefit, used only when it's switched on and can answer right now
    static func engine(plus: Bool, cloudOn: Bool, cloud: CloudStatus) -> AIEngine {
        plus && cloudOn && cloud == .ready ? .cloud : .onDevice
    }

    static func engine(plus: Bool) -> AIEngine {
        guard plus else { return .onDevice }
        let cloudOn = UserDefaults.standard.object(forKey: cloudKey) as? Bool ?? true
        return engine(plus: plus, cloudOn: cloudOn, cloud: cloudOn ? cloudStatus : .unavailable)
    }

    /// Whether the on-device model has the larger context of newer iPhones on iOS 27
    static var onDeviceIsRoomy: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) { return SystemLanguageModel.default.contextSize >= 8192 }
        #endif
        return false
    }

    /// Shared rules for every prompt: plain words, real numbers only
    static let baseInstructions = """
        You are the assistant inside Nokael Money, a personal budgeting app. \
        Be brief, friendly and plain-spoken. Use only the figures you are given or that tools return; \
        never invent amounts, accounts or dates. If you don't have the data, say so. \
        Amounts are already formatted with their currency; repeat them exactly. \
        You give budgeting help, not investment, tax or legal advice.
        """

    static func message(for error: Error) -> String {
        #if canImport(FoundationModels) && PRIVATE_CLOUD_COMPUTE
        if #available(iOS 27.0, *), let error = error as? PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .networkFailure: return "No internet connection. Try again when you're online."
            case .quotaLimitReached: return "Today's limit for Apple's cloud model is used up. It resets tomorrow."
            default: return "Apple's cloud model isn't available right now. Try again in a little while."
            }
        }
        #endif
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
