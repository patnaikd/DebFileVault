//
//  AppState.swift
//  DebFileVault
//

import Foundation
import CryptoKit
import Observation
import SwiftData

private nonisolated(unsafe) let sentinelPlaintext = "DebFileVault-v1"

@MainActor
@Observable
final class AppState {

    // MARK: - Public State

    private(set) var isUnlocked: Bool = false
    private(set) var vaultKey: SymmetricKey? = nil
    private(set) var currentVaultURL: URL? = nil
    private(set) var modelContainer: ModelContainer? = nil

    // MARK: - Create New Vault

    /// Creates a new .debfilevault file at `url`, sets up the password, and unlocks.
    func createVault(at url: URL, password: String) async throws {
        let container = try VaultManager.openContainer(at: url)

        let (key, metadata) = try await Task.detached(priority: .userInitiated) {
            let salt = EncryptionService.generateSalt()
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            guard let sentinelData = sentinelPlaintext.data(using: .utf8) else {
                throw EncryptionError.encryptionFailed
            }
            let (ciphertext, nonce) = try EncryptionService.encrypt(sentinelData, key: key)
            let metadata = VaultMetadata(salt: salt, sentinelCiphertext: ciphertext, sentinelNonce: nonce)
            return (key, metadata)
        }.value

        let context = ModelContext(container)
        context.insert(metadata)
        try context.save()

        currentVaultURL = url
        modelContainer = container
        vaultKey = key
        isUnlocked = true
        VaultManager.saveLastVaultURL(url)
        startIdleTimer()
    }

    // MARK: - Open Existing Vault

    /// Opens an existing .debfilevault file. Does NOT unlock — call unlock(password:) after.
    func openVault(at url: URL) throws {
        let container = try VaultManager.openContainer(at: url)
        currentVaultURL = url
        modelContainer = container
        VaultManager.saveLastVaultURL(url)
    }

    // MARK: - Unlock

    /// Unlocks the currently open vault with the master password.
    /// Throws CryptoKitError.authenticationFailure if the password is wrong.
    func unlock(password: String) async throws {
        guard let container = modelContainer else { throw VaultError.metadataNotFound }

        let context = ModelContext(container)
        let metadata = try context.fetch(FetchDescriptor<VaultMetadata>()).first
        guard let metadata else { throw VaultError.metadataNotFound }

        let salt = metadata.salt
        let sentinelCiphertext = metadata.sentinelCiphertext
        let sentinelNonce = metadata.sentinelNonce

        let key = try await Task.detached(priority: .userInitiated) {
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            _ = try EncryptionService.decrypt(sentinelCiphertext, nonce: sentinelNonce, key: key)
            return key
        }.value

        vaultKey = key
        isUnlocked = true
        startIdleTimer()
    }

    // MARK: - Lock

    func lock() {
        vaultKey = nil
        isUnlocked = false
        cancelIdleTimer()
    }

    // MARK: - Close Vault (return to picker)

    func closeVault() {
        lock()
        modelContainer = nil
        currentVaultURL = nil
    }

    // MARK: - Idle Timer

    private var idleTimer: Timer?
    private let idleTimeoutSeconds: TimeInterval = 5 * 60

    func resetIdleTimer() {
        guard isUnlocked else { return }
        cancelIdleTimer()
        startIdleTimer()
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lock()
        }
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Convenience

    var hasOpenVault: Bool { modelContainer != nil }
}
