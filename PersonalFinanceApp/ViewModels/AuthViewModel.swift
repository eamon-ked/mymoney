//
//  AuthViewModel.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import Foundation
import Combine
import Network

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var email = ""
    @Published var password = ""
    @Published var fullName = ""
    @Published var isSignUpMode = false
    
    private let supabaseManager = SupabaseManager.shared
    private let syncManager = SyncManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var isOnline = true
    
    init() {
        supabaseManager.$isAuthenticated
            .assign(to: \.isAuthenticated, on: self)
            .store(in: &cancellables)

        // Observe online status from SyncManager
        syncManager.$isOnline
            .sink { [weak self] online in self?.isOnline = online }
            .store(in: &cancellables)
    }
    
    func signIn() async {
        guard isOnline else {
            await MainActor.run {
                self.error = "You need to be online to sign in."
            }
            return
        }
        guard !email.isEmpty, !password.isEmpty else {
            await MainActor.run {
                self.error = "Please fill in all fields"
            }
            return
        }
        
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            try await supabaseManager.signIn(email: email, password: password)
            // Ensure we do a full pull right after a successful sign-in on a device
            await MainActor.run { self.syncManager.resetSyncState() }
            await self.syncManager.forceSyncNow()
            await MainActor.run {
                self.isLoading = false
                self.clearFields()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func signUp() async {
        guard !email.isEmpty, !password.isEmpty, !fullName.isEmpty else {
            await MainActor.run {
                self.error = "Please fill in all fields"
            }
            return
        }
        
        guard password.count >= 6 else {
            await MainActor.run {
                self.error = "Password must be at least 6 characters"
            }
            return
        }
        
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            try await supabaseManager.signUp(email: email, password: password, fullName: fullName)
            await MainActor.run {
                self.isLoading = false
                self.clearFields()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func signOut() async {
        await MainActor.run {
            self.isLoading = true
        }
        
        do {
            try await supabaseManager.signOut()
            await MainActor.run {
                self.isLoading = false
                self.clearFields()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func toggleMode() {
        isSignUpMode.toggle()
        error = nil
    }
    
    private func clearFields() {
        email = ""
        password = ""
        fullName = ""
        error = nil
    }
}