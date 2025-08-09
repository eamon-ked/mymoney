//
//  AuthView.swift
//  PersonalFinanceApp
//
//  Created by AI on 8/9/25.
//

import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Personal Finance")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(viewModel.isSignUpMode ? "Create your account" : "Welcome back")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Form
                VStack(spacing: 16) {
                    if viewModel.isSignUpMode {
                        TextField("Full Name", text: $viewModel.fullName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.name)
                    }
                    
                    TextField("Email", text: $viewModel.email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(viewModel.isSignUpMode ? .newPassword : .password)
                }
                .padding(.horizontal)
                
                // Error message
                if let error = viewModel.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Action button
                Button(action: {
                    Task {
                        if viewModel.isSignUpMode {
                            await viewModel.signUp()
                        } else {
                            await viewModel.signIn()
                        }
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isSignUpMode ? "Sign Up" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
                
                // Toggle mode
                Button(action: viewModel.toggleMode) {
                    Text(viewModel.isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    AuthView()
}