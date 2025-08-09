//
//  MainTabView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some View {
        if authViewModel.isAuthenticated {
            TabView {
                DashboardView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Dashboard")
                    }
                
                AccountsView()
                    .tabItem {
                        Image(systemName: "creditcard.fill")
                        Text("Accounts")
                    }
                
                TransactionsView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Transactions")
                    }
                
                GoalsView()
                    .tabItem {
                        Image(systemName: "target")
                        Text("Goals")
                    }
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
            }
        } else {
            AuthView()
        }
    }
}

struct SettingsView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var syncManager = SyncManager.shared
    
    var body: some View {
        NavigationView {
            List {
                Section("Sync") {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        if let lastSync = syncManager.lastSyncDate {
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button("Sync Now") {
                        Task {
                            await syncManager.forceSyncNow()
                        }
                    }
                    .disabled(syncManager.isSyncing)
                    
                    if syncManager.isSyncing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = syncManager.syncError {
                        Text("Sync Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Account") {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                        }
                    }
                    .disabled(authViewModel.isLoading)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    MainTabView()
}