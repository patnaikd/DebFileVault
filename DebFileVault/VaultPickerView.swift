//
//  VaultPickerView.swift
//  DebFileVault
//

import SwiftUI
import UniformTypeIdentifiers

struct VaultPickerView: View {
    @Environment(AppState.self) private var appState

    @State private var showingCreatePassword = false
    @State private var newVaultURL: URL? = nil
    @State private var createPassword = ""
    @State private var createConfirm = ""
    @State private var errorMessage: String? = nil
    @State private var isWorking = false

    @State private var lastVaultURL: URL? = nil

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("DebFileVault")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Choose a vault to open or create a new one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if showingCreatePassword, let url = newVaultURL {
                createPasswordForm(for: url)
            } else {
                pickerButtons
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 460)
        .onAppear {
            lastVaultURL = VaultManager.loadLastVaultURL()
        }
    }

    // MARK: - Picker Buttons

    private var pickerButtons: some View {
        VStack(spacing: 12) {
            if let url = lastVaultURL {
                Button {
                    openVault(at: url)
                } label: {
                    Label("Open \(url.deletingPathExtension().lastPathComponent)", systemImage: "clock")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)

                Divider().frame(maxWidth: 260)
            }

            Button {
                presentOpenPanel()
            } label: {
                Label("Open Existing Vault…", systemImage: "folder")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.bordered)

            Button {
                presentCreatePanel()
            } label: {
                Label("Create New Vault…", systemImage: "plus.circle")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.bordered)

            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Create Password Form

    private func createPasswordForm(for url: URL) -> some View {
        VStack(spacing: 12) {
            Text("Set a master password for\n\"\(url.deletingPathExtension().lastPathComponent)\"")
                .font(.headline).multilineTextAlignment(.center)

            SecureField("Master Password", text: $createPassword)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            SecureField("Confirm Password", text: $createConfirm)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)

            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingCreatePassword = false
                    newVaultURL = nil
                    createPassword = ""
                    createConfirm = ""
                    errorMessage = nil
                }
                .buttonStyle(.bordered)

                Button("Create Vault") {
                    createVault(at: url)
                }
                .buttonStyle(.borderedProminent)
                .disabled(createPassword.isEmpty || isWorking)
            }
        }
    }

    // MARK: - Actions

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        if let uti = UTType(filenameExtension: VaultManager.fileExtension) {
            panel.allowedContentTypes = [uti]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a DebFileVault vault file"
        if panel.runModal() == .OK, let url = panel.url {
            openVault(at: url)
        }
    }

    private func presentCreatePanel() {
        let panel = NSSavePanel()
        if let uti = UTType(filenameExtension: VaultManager.fileExtension) {
            panel.allowedContentTypes = [uti]
        }
        panel.nameFieldStringValue = "MyVault"
        panel.message = "Choose where to save your new vault"
        if panel.runModal() == .OK, let url = panel.url {
            newVaultURL = url
            showingCreatePassword = true
        }
    }

    private func openVault(at url: URL) {
        errorMessage = nil
        do {
            try appState.openVault(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createVault(at url: URL) {
        guard createPassword == createConfirm else {
            errorMessage = "Passwords do not match."
            return
        }
        guard createPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                try await appState.createVault(at: url, password: createPassword)
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
