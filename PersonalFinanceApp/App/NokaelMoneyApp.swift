//
//  NokaelMoneyApp.swift
//  Nokael Money
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct NokaelMoneyApp: App {
    private let container: ModelContainer
    @State private var store: LedgerStore
    @State private var plus = PlusStore()

    init() {
        let args = CommandLine.arguments
        // UI tests and demos run on a throwaway in-memory store, never on real records
        let inMemory = args.contains("-uiTesting") || args.contains("-demoData")
        do {
            container = try ModelContainer(for: Schema(Schema1.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Could not open the database: \(error)")
        }
        let store = LedgerStore(context: container.mainContext)
        #if DEBUG
        if args.contains("-demoData") { DemoData.load(into: store) }
        #endif
        _store = State(initialValue: store)
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
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
