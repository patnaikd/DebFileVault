//
//  AppState.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import Foundation
import CryptoKit
import Observation

// UserDefaults keys for vault metadata (none of this is secret)
private enum VaultKeys {
    static let salt = "com.debprakash.DebFileVault.vaultSalt"
    static let sentinelCiphertext = "com.debprakash.DebFileVault.sentinelCiphertext"
    static let sentinelNonce = "com.debprakash.DebFileVault.sentinelNonce"
}

// Fixed plaintext used to verify the correct password on unlock.
// We encrypt this on first setup and attempt to decrypt on every subsequent unlock.
// nonisolated(unsafe) because this is an immutable constant accessed from Task.detached.
private nonisolated(unsafe) let sentinelPlaintext = "DebFileVault-v1"

@MainActor
@Observable
final class AppState {

    // MARK: - Public State

    private(set) var isUnlocked: Bool = false

    // The derived AES-256 key, held in memory only while unlocked.
    // NOTE: Swift value types do not guarantee memory zeroing on release;
    // setting to nil drops the reference and allows ARC to reclaim it,
    // but the underlying bytes may remain in process memory until overwritten.
    // This is a known limitation of Swift for sensitive key material.
    private(set) var vaultKey: SymmetricKey? = nil

    // MARK: - First-Launch Detection

    var isFirstLaunch: Bool {
        UserDefaults.standard.data(forKey: VaultKeys.salt) == nil
    }

    // MARK: - Setup (First Launch)

    /// Creates the vault with a new master password. Generates a salt, derives the key,
    /// encrypts a sentinel blob for future password verification, and unlocks.
    /// Key derivation runs off the main thread; state mutations happen on MainActor.
    func setupVault(password: String) async throws {
        // Run CPU-intensive PBKDF2 off the main thread
        let (key, salt, ciphertext, nonce) = try await Task.detached(priority: .userInitiated) {
            let salt = EncryptionService.generateSalt()
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            guard let sentinelData = sentinelPlaintext.data(using: .utf8) else {
                throw EncryptionError.encryptionFailed
            }
            let (ciphertext, nonce) = try EncryptionService.encrypt(sentinelData, key: key)
            return (key, salt, ciphertext, nonce)
        }.value

        // Persist salt and encrypted sentinel (neither is secret)
        UserDefaults.standard.set(salt, forKey: VaultKeys.salt)
        UserDefaults.standard.set(ciphertext, forKey: VaultKeys.sentinelCiphertext)
        UserDefaults.standard.set(nonce, forKey: VaultKeys.sentinelNonce)

        vaultKey = key
        isUnlocked = true
        startIdleTimer()
    }

    // MARK: - Unlock

    /// Unlocks the vault with the master password.
    /// Throws CryptoKitError.authenticationFailure if the password is wrong.
    /// Key derivation runs off the main thread; state mutations happen on MainActor.
    func unlock(password: String) async throws {
        guard
            let salt = UserDefaults.standard.data(forKey: VaultKeys.salt),
            let sentinelCiphertext = UserDefaults.standard.data(forKey: VaultKeys.sentinelCiphertext),
            let sentinelNonce = UserDefaults.standard.data(forKey: VaultKeys.sentinelNonce)
        else {
            throw EncryptionError.invalidData
        }

        // Run CPU-intensive PBKDF2 off the main thread
        let key = try await Task.detached(priority: .userInitiated) {
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            // Throws CryptoKitError.authenticationFailure if the password is wrong
            _ = try EncryptionService.decrypt(sentinelCiphertext, nonce: sentinelNonce, key: key)
            return key
        }.value

        vaultKey = key
        isUnlocked = true
        startIdleTimer()
    }

    // MARK: - Lock

    /// Locks the vault, wiping the in-memory key.
    func lock() {
        vaultKey = nil
        isUnlocked = false
        cancelIdleTimer()
    }

    // MARK: - Idle Timer

    private var idleTimer: Timer?
    private let idleTimeoutSeconds: TimeInterval = 5 * 60 // 5 minutes

    /// Resets the idle timer. Call this on any user interaction.
    func resetIdleTimer() {
        guard isUnlocked else { return }
        cancelIdleTimer()
        startIdleTimer()
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: idleTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            // Timer fires on the main run loop; AppState is @MainActor, so this is safe.
            self.lock()
        }
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Vault Salt

    /// Returns the stored vault salt. Used by views when creating new encrypted items.
    var vaultSalt: Data? {
        UserDefaults.standard.data(forKey: VaultKeys.salt)
    }
}
