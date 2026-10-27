//
//  NokaelMoneyApp.swift
//  Nokael Money
//

import SwiftUI
import SwiftData
import UserNotifications

/// The one database, ledger and Plus status, shared by the app's screens and
/// by Siri and Shortcuts, which can run while no screen is open
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let store: LedgerStore
    let plus = PlusStore()

    private init() {
        let args = CommandLine.arguments
        // UI tests and demos run on a throwaway in-memory store, never on real records
        let inMemory = args.contains("-uiTesting") || args.contains("-demoData")
        do {
            container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Could not open the database: \(error)")
        }
        store = LedgerStore(context: container.mainContext)
        #if DEBUG
        if args.contains("-demoData") { DemoData.load(into: store) }
        // Test helper: -restoreBackup <path to a backup .json>, to see real data in the simulator
        if let path = UserDefaults.standard.string(forKey: "restoreBackup"),
           let data = FileManager.default.contents(atPath: path),
           let backup = try? LedgerStore.readBackup(data) {
            _ = try? store.restore(backup)
        }
        #endif
    }
}

@main
struct NokaelMoneyApp: App {
    private let container: ModelContainer
    @State private var store: LedgerStore
    @State private var plus: PlusStore

    init() {
        let services = AppServices.shared
        container = services.container
        _store = State(initialValue: services.store)
        _plus = State(initialValue: services.plus)
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        NokaelShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(plus)
                .modelContainer(container)
        }
    }
}
