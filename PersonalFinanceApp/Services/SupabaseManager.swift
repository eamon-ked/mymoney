//
//  SupabaseManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Supabase
import Combine

class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    private let client: SupabaseClient
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private init() {
        guard let url = URL(string: ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? ""),
              let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] else {
            fatalError("Missing Supabase configuration")
        }
        
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        
        Task {
            await checkAuthStatus()
        }
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String, fullName: String) async throws {
        let response = try await client.auth.signUp(email: email, password: password)
        
        if let user = response.user {
            // Create user profile
            let profile = [
                "id": user.id.uuidString,
                "full_name": fullName,
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ]
            
            try await client.database
                .from("user_profiles")
                .insert(profile)
                .execute()
        }
    }
    
    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        await checkAuthStatus()
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    private func checkAuthStatus() async {
        do {
            let user = try await client.auth.user()
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }
    
    // MARK: - Data Operations
    
    func fetchAccounts(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var query = client.database
            .from("accounts")
            .select()
            .order("created_at", ascending: false)
        
        if let lastSynced = lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            query = query.gt("updated_at", value: formatter.string(from: lastSynced))
        }
        
        let response: [PostgrestResponse<[String: Any]>] = try await query.execute()
        return response.first?.value ?? []
    }
    
    func upsertAccount(_ account: [String: Any]) async throws {
        try await client.database
            .from("accounts")
            .upsert(account)
            .execute()
    }
    
    func fetchTransactions(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var query = client.database
            .from("transactions")
            .select()
            .order("transaction_date", ascending: false)
            .limit(100)
        
        if let lastSynced = lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            query = query.gt("updated_at", value: formatter.string(from: lastSynced))
        }
        
        let response: [PostgrestResponse<[String: Any]>] = try await query.execute()
        return response.first?.value ?? []
    }
    
    func upsertTransaction(_ transaction: [String: Any]) async throws {
        try await client.database
            .from("transactions")
            .upsert(transaction)
            .execute()
    }
    
    func fetchCategories(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var query = client.database
            .from("categories")
            .select()
            .order("name", ascending: true)
        
        if let lastSynced = lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            query = query.gt("updated_at", value: formatter.string(from: lastSynced))
        }
        
        let response: [PostgrestResponse<[String: Any]>] = try await query.execute()
        return response.first?.value ?? []
    }
    
    func upsertCategory(_ category: [String: Any]) async throws {
        try await client.database
            .from("categories")
            .upsert(category)
            .execute()
    }
    
    func fetchGoals(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var query = client.database
            .from("goals")
            .select()
            .order("created_at", ascending: false)
        
        if let lastSynced = lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            query = query.gt("updated_at", value: formatter.string(from: lastSynced))
        }
        
        let response: [PostgrestResponse<[String: Any]>] = try await query.execute()
        return response.first?.value ?? []
    }
    
    func upsertGoal(_ goal: [String: Any]) async throws {
        try await client.database
            .from("goals")
            .upsert(goal)
            .execute()
    }
    
    func fetchPrivateLoans(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var query = client.database
            .from("private_loans")
            .select()
            .order("created_at", ascending: false)
        
        if let lastSynced = lastSyncedAt {
            let formatter = ISO8601DateFormatter()
            query = query.gt("updated_at", value: formatter.string(from: lastSynced))
        }
        
        let response: [PostgrestResponse<[String: Any]>] = try await query.execute()
        return response.first?.value ?? []
    }
    
    func upsertPrivateLoan(_ loan: [String: Any]) async throws {
        try await client.database
            .from("private_loans")
            .upsert(loan)
            .execute()
    }
}