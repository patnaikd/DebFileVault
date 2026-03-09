//
//  LockScreenView.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import SwiftUI
import CryptoKit

struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String? = nil
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon + title
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("DebFileVault")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(appState.isFirstLaunch ? "Create a master password to protect your vault." : "Enter your master password to unlock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Form
            VStack(spacing: 12) {
                SecureField("Master Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { handleAction() }

                if appState.isFirstLaunch {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit { handleAction() }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: handleAction) {
                    if isWorking {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 80, height: 20)
                    } else {
                        Text(appState.isFirstLaunch ? "Create Vault" : "Unlock")
                            .frame(width: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isWorking || (appState.isFirstLaunch && confirmPassword.isEmpty))
                .keyboardShortcut(.return)
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 400)
    }

    private func handleAction() {
        errorMessage = nil
        guard !password.isEmpty else { return }

        if appState.isFirstLaunch {
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match."
                return
            }
            guard password.count >= 8 else {
                errorMessage = "Password must be at least 8 characters."
                return
            }
        }

        isWorking = true

        // AppState methods are async and run PBKDF2 off the main thread internally
        Task {
            do {
                if appState.isFirstLaunch {
                    try await appState.setupVault(password: password)
                } else {
                    try await appState.unlock(password: password)
                }
            } catch is CryptoKitError {
                errorMessage = "Incorrect password. Please try again."
                isWorking = false
                password = ""
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
