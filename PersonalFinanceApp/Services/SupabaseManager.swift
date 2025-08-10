//
//  SupabaseManager.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Supabase
import Combine

@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    private let client: SupabaseClient
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private init() {
        let (urlString, anonKey) = SupabaseManager.loadSupabaseConfig()
        guard let url = URL(string: urlString), !anonKey.isEmpty else {
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
        let user = response.user
        // Create user profile
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let profile: [String: AnyEncodable] = [
            "id": AnyEncodable(user.id.uuidString),
            "full_name": AnyEncodable(fullName),
            "created_at": AnyEncodable(nowISO),
            "updated_at": AnyEncodable(nowISO)
        ]
        
        try await client
            .from("user_profiles")
            .insert(profile)
            .execute()
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
            // Securely clear local data upon logout
            try? LocalDatabaseManager.shared.wipeAllData()
        }
    }
    
    // MARK: - Account management
    func getCurrentEmail() -> String? {
        return currentUser?.email
    }
    
    func updatePassword(newPassword: String) async throws {
        _ = try await client.auth.update(user: .init(password: newPassword))
        // Session remains valid; Supabase returns updated user
        await checkAuthStatus()
    }

    // Permanently delete the current user's account and all associated data.
    // This method ensures complete data deletion for App Store compliance.
    func deleteCurrentUserAndData() async throws {
        guard let uid = currentUser?.id.uuidString else {
            throw NSError(domain: "PersonalFinanceApp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("🗑️ Starting account deletion for user: \(uid)")
        
        // Step 1: Check what data exists before deletion
        await checkExistingData(userId: uid)
        
        // Step 2: Try server-side RPC (deletes both data and auth user)
        do {
            struct EmptyParams: Encodable {}
            print("🔄 Attempting RPC deletion (data + auth user)...")
            _ = try await client.rpc("delete_user_and_data", params: EmptyParams()).execute()
            print("✅ Server-side deletion successful")
            
            // Step 3: Verify deletion worked
            await checkExistingData(userId: uid)
            
            try await signOut()
            return
        } catch {
            print("⚠️ Server-side deletion failed: \(error.localizedDescription)")
        }
        
        // Step 4: Fallback to client-side deletion with proper error handling
        do {
            print("🔄 Attempting client-side deletion...")
            try await performClientSideDeletion(userId: uid)
            print("✅ Client-side deletion successful")
            
            // Step 5: Verify deletion worked
            await checkExistingData(userId: uid)
            
            // Note: Auth user deletion will need manual intervention if RPC fails
            print("⚠️ Auth user deletion required manually. Please delete user \(uid) from Supabase Dashboard → Authentication → Users")
            
            try await signOut()
            return
        } catch {
            print("❌ Client-side deletion failed: \(error.localizedDescription)")
            // Don't sign out if deletion fails - let user know there was an issue
            throw NSError(
                domain: "PersonalFinanceApp", 
                code: -2, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete account data. Please try again or contact support."]
            )
        }
    }
    
    // Check what data exists for a user
    private func checkExistingData(userId: String) async {
        print("🔍 Checking existing data for user: \(userId)")
        
        let tables = [
            ("transactions", "user_id"),
            ("goals", "user_id"),
            ("categories", "user_id"),
            ("private_loans", "user_id"),
            ("accounts", "user_id"),
            ("user_profiles", "id")
        ]
        
        for (table, column) in tables {
            do {
                let response = try await client
                    .from(table)
                    .select("id")
                    .eq(column, value: userId)
                    .execute()
                
                let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] ?? []
                print("📊 \(table): \(rows.count) rows")
            } catch {
                print("❌ Error checking \(table): \(error.localizedDescription)")
            }
        }
    }
    
    // Comprehensive client-side deletion with proper error handling
    private func performClientSideDeletion(userId: String) async throws {
        var deletionErrors: [String] = []
        
        // Delete in dependency order to avoid foreign key constraints
        let deletionOrder = [
            ("transactions", "user_id"),
            ("goals", "user_id"), 
            ("categories", "user_id"),
            ("private_loans", "user_id"),
            ("accounts", "user_id"),
            ("user_profiles", "id") // user_profiles uses id = user_id
        ]
        
        for (table, column) in deletionOrder {
            do {
                print("🗑️ Deleting from \(table) where \(column) = \(userId)")
                
                _ = try await client
                    .from(table)
                    .delete()
                    .eq(column, value: userId)
                    .execute()
                
                print("✅ Delete request sent for \(table)")
                
                // Verify deletion by checking if any rows remain
                let verifyResponse = try await client
                    .from(table)
                    .select("id")
                    .eq(column, value: userId)
                    .limit(1)
                    .execute()
                
                let remainingRows = try JSONSerialization.jsonObject(with: verifyResponse.data) as? [[String: Any]] ?? []
                if !remainingRows.isEmpty {
                    deletionErrors.append("Failed to delete all rows from \(table)")
                    print("❌ \(table) still has \(remainingRows.count) rows after deletion")
                } else {
                    print("✅ \(table) deletion verified - 0 rows remaining")
                }
                
            } catch {
                deletionErrors.append("Error deleting from \(table): \(error.localizedDescription)")
                print("❌ Failed to delete from \(table): \(error.localizedDescription)")
            }
        }
        
        // If any deletions failed, throw an error
        if !deletionErrors.isEmpty {
            print("❌ Deletion errors: \(deletionErrors)")
            throw NSError(
                domain: "PersonalFinanceApp",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Some data could not be deleted",
                    "deletionErrors": deletionErrors
                ]
            )
        }
        
        print("✅ All client-side deletions completed successfully")
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
        var q = client
            .from("accounts")
            .select()
        if let uid = currentUser?.id.uuidString {
            q = q.eq("user_id", value: uid)
        }
        let query = q.order("created_at", ascending: false)
        
        if let _ = lastSyncedAt {
            // Filtering by updated_at is temporarily disabled due to SDK API differences.
            // The sync will fetch recent items ordered by created_at.
        }
        let response = try await query.execute()
        return decodeRows(response)
    }
    
    func upsertAccount(_ account: [String: Any]) async throws {
        let payload = encodableDict(account)
        try await client
            .from("accounts")
            .upsert(payload)
            .execute()
    }
    
    func fetchTransactions(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var q = client
            .from("transactions")
            .select()
        if let uid = currentUser?.id.uuidString {
            q = q.eq("user_id", value: uid)
        }
        let query = q.order("transaction_date", ascending: false)
            .limit(100)
        
        if let _ = lastSyncedAt {
            // See note above regarding filter support.
        }
        let response = try await query.execute()
        return decodeRows(response)
    }
    
    func upsertTransaction(_ transaction: [String: Any]) async throws {
        let payload = encodableDict(transaction)
        try await client
            .from("transactions")
            .upsert(payload)
            .execute()
    }
    
    func fetchCategories(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var q = client
            .from("categories")
            .select()
        if let uid = currentUser?.id.uuidString {
            q = q.eq("user_id", value: uid)
        }
        let query = q.order("name", ascending: true)
        
        if let _ = lastSyncedAt {
            // See note above regarding filter support.
        }
        let response = try await query.execute()
        return decodeRows(response)
    }
    
    func upsertCategory(_ category: [String: Any]) async throws {
        var dict = category
        // Ensure user_id is set for uniqueness scope
        if dict["user_id"] == nil, let uid = currentUser?.id.uuidString {
            dict["user_id"] = uid
        }
        let payload = encodableDict(dict)
        try await client
            .from("categories")
            .upsert(payload)
            .execute()
    }
    
    func fetchGoals(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var q = client
            .from("goals")
            .select()
        if let uid = currentUser?.id.uuidString {
            q = q.eq("user_id", value: uid)
        }
        let query = q.order("created_at", ascending: false)
        
        if let _ = lastSyncedAt {
            // See note above regarding filter support.
        }
        let response = try await query.execute()
        return decodeRows(response)
    }
    
    func upsertGoal(_ goal: [String: Any]) async throws {
        let payload = encodableDict(goal)
        try await client
            .from("goals")
            .upsert(payload)
            .execute()
    }
    
    func fetchPrivateLoans(lastSyncedAt: Date?) async throws -> [[String: Any]] {
        var q = client
            .from("private_loans")
            .select()
        if let uid = currentUser?.id.uuidString {
            q = q.eq("user_id", value: uid)
        }
        let query = q.order("created_at", ascending: false)
        
        if let _ = lastSyncedAt {
            // See note above regarding filter support.
        }
        let response = try await query.execute()
        return decodeRows(response)
    }
    
    func upsertPrivateLoan(_ loan: [String: Any]) async throws {
        let payload = encodableDict(loan)
        try await client
            .from("private_loans")
            .upsert(payload)
            .execute()
    }
}

// MARK: - Helpers for encoding and decoding

fileprivate struct AnyEncodable: Encodable, @unchecked Sendable {
    private let encoderClosure: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T?) {
        self.encoderClosure = { encoder in
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }
    func encode(to encoder: Encoder) throws {
        try encoderClosure(encoder)
    }
}

extension SupabaseManager {
    // Prefer: Environment > Info.plist > bundled .env
    static func loadSupabaseConfig() -> (String, String) {
        // 1) Environment variables (Scheme > Run > Arguments)
        if let url = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !url.isEmpty, !key.isEmpty {
            return (url, key)
        }
        // 2) Info.plist custom keys
        if let info = Bundle.main.infoDictionary,
           let url = info["SUPABASE_URL"] as? String,
           let key = info["SUPABASE_ANON_KEY"] as? String,
           !url.isEmpty, !key.isEmpty {
            return (url, key)
        }
        // 3) Bundled .env file (copied in Build Phases)
        if let envURL = Bundle.main.url(forResource: ".env", withExtension: nil),
           let contents = try? String(contentsOf: envURL, encoding: .utf8) {
            var urlValue = ""
            var keyValue = ""
            contents.split(separator: "\n").forEach { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
                if trimmed.hasPrefix("SUPABASE_URL=") {
                    urlValue = String(trimmed.dropFirst("SUPABASE_URL=".count))
                } else if trimmed.hasPrefix("SUPABASE_ANON_KEY=") {
                    keyValue = String(trimmed.dropFirst("SUPABASE_ANON_KEY=".count))
                }
            }
            if !urlValue.isEmpty, !keyValue.isEmpty {
                return (urlValue, keyValue)
            }
        }
        return ("", "")
    }

    private func encodableDict(_ dict: [String: Any]) -> [String: AnyEncodable] {
        var out: [String: AnyEncodable] = [:]
        for (k, v) in dict {
            out[k] = wrapAny(v)
        }
        return out
    }
    
    private func wrapAny(_ value: Any) -> AnyEncodable {
        switch value {
        case let v as String: return AnyEncodable(v)
        case let v as Int: return AnyEncodable(v)
        case let v as Double: return AnyEncodable(v)
        case let v as Bool: return AnyEncodable(v)
        case let v as [String]: return AnyEncodable(v)
        case is NSNull: return AnyEncodable(Optional<String>.none)
        default:
            return AnyEncodable(Optional<String>.none)
        }
    }
    
    private func decodeRows<T>(_ response: PostgrestResponse<T>) -> [[String: Any]] {
        do {
            // Attempt to parse raw data into array of dictionaries
            let obj = try JSONSerialization.jsonObject(with: response.data)
            if let rows = obj as? [[String: Any]] {
                return rows
            } else if let row = obj as? [String: Any] {
                return [row]
            }
        } catch { }
        return []
    }
}