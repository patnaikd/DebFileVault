//
//  LockScreenView.swift
//  DebFileVault
//

import SwiftUI
import CryptoKit

struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var errorMessage: String? = nil
    @State private var isWorking = false

    var vaultName: String {
        appState.currentVaultURL?.deletingPathExtension().lastPathComponent ?? "Vault"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text(vaultName)
                    .font(.largeTitle).fontWeight(.bold)
                Text("Enter your master password to unlock.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Master Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { handleUnlock() }

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Button(action: handleUnlock) {
                    if isWorking {
                        ProgressView().scaleEffect(0.7).frame(width: 80, height: 20)
                    } else {
                        Text("Unlock").frame(width: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isWorking)
                .keyboardShortcut(.return)

                Button("Choose Different Vault…") {
                    appState.closeVault()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 400)
    }

    private func handleUnlock() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await appState.unlock(password: password)
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
