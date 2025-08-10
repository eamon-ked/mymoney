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
                
                LoansView()
                    .tabItem {
                        Image(systemName: "banknote")
                        Text("Loans")
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
    @State private var currencyCode: String = UserDefaults.standard.string(forKey: "currencyCode") ?? "USD"
    @State private var includeLoanPaymentsInMonthly: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "includeLoanPaymentsInMonthly") == nil ? false : defaults.bool(forKey: "includeLoanPaymentsInMonthly")
    }()
    @State private var includeGoalSavingsInMonthly: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "includeGoalSavingsInMonthly") == nil ? false : defaults.bool(forKey: "includeGoalSavingsInMonthly")
    }()
    
    // Account deletion state
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deletionError: String?
    @State private var showingErrorAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Preferences") {
                    HStack {
                        Text("Currency")
                        Spacer()
                        TextField("e.g. USD, EUR", text: $currencyCode)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .onSubmit { saveCurrency() }
                            .onChange(of: currencyCode) { _, new in
                                // Persist as user types (trim to 3-5 chars for safety)
                                let code = new.trimmingCharacters(in: .whitespacesAndNewlines)
                                UserDefaults.standard.set(code, forKey: "currencyCode")
                            }
                    }
                    Text("Used across amounts in the app").font(.caption).foregroundColor(.secondary)

                    Toggle("Include Loan Payments in Monthly Expenses", isOn: $includeLoanPaymentsInMonthly)
                        .onChange(of: includeLoanPaymentsInMonthly) { _, value in
                            UserDefaults.standard.set(value, forKey: "includeLoanPaymentsInMonthly")
                        }
                    Toggle("Include Goal Savings in Monthly Expenses", isOn: $includeGoalSavingsInMonthly)
                        .onChange(of: includeGoalSavingsInMonthly) { _, value in
                            UserDefaults.standard.set(value, forKey: "includeGoalSavingsInMonthly")
                        }
                }
                // Sync controls hidden per requirements
                
                Section("Account") {
                    NavigationLink("Profile") { ProfileView() }
                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(isDeletingAccount)
                    .overlay(
                        Group {
                            if isDeletingAccount {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Deleting...")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    )
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                        }
                    }
                    .disabled(authViewModel.isLoading || isDeletingAccount)
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
            .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task { await deleteAccountFlow() }
                }
            } message: {
                Text("This action cannot be undone. All your data will be permanently deleted and you will be signed out.")
            }
            .alert("Deletion Failed", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(deletionError ?? "An unknown error occurred. Please try again.")
            }
        }
    }

    private func saveCurrency() {
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(code, forKey: "currencyCode")
    }

    @MainActor
    private func deleteAccountFlow() async {
        // Set loading state
        isDeletingAccount = true
        deletionError = nil
        
        do {
            try await SupabaseManager.shared.deleteCurrentUserAndData()
            // Success - user is already signed out by deleteCurrentUserAndData
            // No need to show success message as user will be redirected to login
        } catch {
            // Show error to user
            deletionError = error.localizedDescription
            showingErrorAlert = true
            print("Account deletion failed: \(error.localizedDescription)")
        }
        
        // Reset loading state
        isDeletingAccount = false
    }
}

struct ProfileView: View {
    @State private var fullName: String = ""
    @State private var phone: String = ""
    @State private var occupation: String = ""
    @State private var annualIncome: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var hasDateOfBirth: Bool = false
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isChangingPassword: Bool = false
    @State private var isSaving: Bool = false
    @State private var error: String?

    private let localDB = LocalDatabaseManager.shared
    private let supabase = SupabaseManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section("Personal") {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(supabase.getCurrentEmail() ?? "-")
                            .foregroundColor(.secondary)
                    }
                    TextField("Full Name", text: $fullName)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    Toggle("Add Date of Birth", isOn: $hasDateOfBirth)
                    if hasDateOfBirth {
                        DatePicker("Date of Birth", selection: $dateOfBirth, displayedComponents: .date)
                    }
                }
                Section("Work") {
                    TextField("Occupation", text: $occupation)
                    TextField("Annual Income", text: $annualIncome)
                        .keyboardType(.decimalPad)
                }
                Section("Security") {
                    if isChangingPassword {
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm Password", text: $confirmPassword)
                        Button("Update Password") { Task { await changePassword() } }
                            .disabled(newPassword.isEmpty || newPassword != confirmPassword || isSaving)
                    } else {
                        Button("Change Password") { isChangingPassword = true }
                    }
                    if let err = error { Text(err).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button("Save Profile") { saveProfile() }
                }
            }
            .navigationTitle("Profile")
            .onAppear(perform: loadProfile)
        }
    }

    private func loadProfile() {
        do {
            if let profile = try localDB.fetchUserProfile() {
                fullName = profile.fullName
                phone = profile.phone ?? ""
                occupation = profile.occupation ?? ""
                if let income = profile.annualIncome { annualIncome = String(describing: income) } else { annualIncome = "" }
                if let dob = profile.dateOfBirth { hasDateOfBirth = true; dateOfBirth = dob } else { hasDateOfBirth = false }
            }
        } catch {
            // keep UI silent
        }
    }

    private func saveProfile() {
        do {
            if let existing = try localDB.fetchUserProfile() {
                existing.fullName = fullName
                existing.phone = phone.isEmpty ? nil : phone
                existing.occupation = occupation.isEmpty ? nil : occupation
                if let income = Decimal(string: annualIncome) { existing.annualIncome = income } else { existing.annualIncome = nil }
                existing.dateOfBirth = hasDateOfBirth ? dateOfBirth : nil
                existing.updatedAt = Date()
                existing.syncStatus = "pending"
                try localDB.save()
            } else {
                let incomeDecimal = Decimal(string: annualIncome)
                let profile = UserProfile(
                    fullName: fullName.isEmpty ? "" : fullName,
                    phone: phone.isEmpty ? nil : phone,
                    dateOfBirth: hasDateOfBirth ? dateOfBirth : nil,
                    occupation: occupation.isEmpty ? nil : occupation,
                    annualIncome: incomeDecimal,
                    financialGoals: []
                )
                try localDB.insert(profile)
            }
        } catch {
            // keep UI silent
        }
    }

    private func changePassword() async {
        guard newPassword.count >= 6 else {
            error = "Password must be at least 6 characters"
            return
        }
        guard newPassword == confirmPassword else {
            error = "Passwords do not match"
            return
        }
        error = nil
        isSaving = true
        do {
            try await supabase.updatePassword(newPassword: newPassword)
            await MainActor.run {
                isSaving = false
                isChangingPassword = false
                newPassword = ""
                confirmPassword = ""
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isSaving = false
            }
        }
    }
}

#Preview {
    MainTabView()
}