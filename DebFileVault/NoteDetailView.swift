//
//  NoteDetailView.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import SwiftUI
import CryptoKit

struct NoteDetailView: View {
    @Environment(AppState.self) private var appState
    var item: Item

    @State private var titleText: String = ""
    @State private var contentText: String = ""
    @State private var decryptionFailed: Bool = false

    // Last saved values — used to skip unnecessary re-encryption
    @State private var savedTitle: String = ""
    @State private var savedContent: String = ""

    // Debounce tasks — cancelled and restarted on each keystroke
    @State private var titleSaveTask: Task<Void, Never>? = nil
    @State private var contentSaveTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if decryptionFailed {
                ContentUnavailableView(
                    "Decryption Failed",
                    systemImage: "lock.trianglebadge.exclamationmark",
                    description: Text("This note could not be decrypted. The vault key may have changed.")
                )
            } else {
                // Title field
                TextField("Title", text: $titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .onChange(of: titleText) {
                        appState.resetIdleTimer()
                        scheduleTitleSave()
                    }

                Divider()
                    .padding(.horizontal, 20)

                // Content editor
                TextEditor(text: $contentText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .onChange(of: contentText) {
                        appState.resetIdleTimer()
                        scheduleContentSave()
                    }

                // Metadata footer
                Divider()
                HStack(spacing: 16) {
                    Label("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    Label("Modified \(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "pencil")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .onAppear { decryptItem() }
        .onChange(of: item.id) { decryptItem() }
    }

    // MARK: - Decryption

    private func decryptItem() {
        guard let key = appState.vaultKey else { return }
        do {
            titleText = try EncryptionService.decryptString(item.encryptedTitle, nonce: item.titleNonce, key: key)
            contentText = try EncryptionService.decryptString(item.encryptedContent, nonce: item.contentNonce, key: key)
            savedTitle = titleText
            savedContent = contentText
            decryptionFailed = false
        } catch {
            decryptionFailed = true
        }
    }

    // MARK: - Auto-Save with Debounce

    private func scheduleTitleSave() {
        titleSaveTask?.cancel()
        titleSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveTitle()
        }
    }

    private func scheduleContentSave() {
        contentSaveTask?.cancel()
        contentSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveContent()
        }
    }

    private func saveTitle() {
        guard titleText != savedTitle else { return }
        guard let key = appState.vaultKey else { return }
        do {
            let (ciphertext, nonce) = try EncryptionService.encryptString(titleText, key: key)
            item.encryptedTitle = ciphertext
            item.titleNonce = nonce
            item.modifiedAt = Date()
            savedTitle = titleText
        } catch {
            // Encryption failure is non-fatal for UX; the in-memory text is still correct.
            // The item will be re-encrypted on the next keystroke attempt.
        }
    }

    private func saveContent() {
        guard contentText != savedContent else { return }
        guard let key = appState.vaultKey else { return }
        do {
            let (ciphertext, nonce) = try EncryptionService.encryptString(contentText, key: key)
            item.encryptedContent = ciphertext
            item.contentNonce = nonce
            item.modifiedAt = Date()
            savedContent = contentText
        } catch {
            // See comment in saveTitle
        }
    }
}
