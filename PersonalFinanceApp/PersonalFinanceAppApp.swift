//
//  PersonalFinanceAppApp.swift
//  PersonalFinanceApp
//
//  Created by Eamon on 8/9/25.
//

import SwiftUI
import SwiftData

@main
struct PersonalFinanceAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Account.self,
            Category.self,
            Transaction.self,
            Goal.self,
            PrivateLoan.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
