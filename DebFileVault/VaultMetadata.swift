//
//  VaultMetadata.swift
//  DebFileVault
//

import Foundation
import SwiftData

/// Stores per-vault cryptographic metadata inside the vault's SQLite file.
/// There is exactly one row per vault, created during vault setup.
/// None of this data is secret — salt prevents rainbow tables,
/// sentinel ciphertext is used only to verify the correct password.
@Model
final class VaultMetadata {
    /// PBKDF2-SHA256 salt (16 bytes, random, generated once at vault creation)
    var salt: Data
    /// AES-256-GCM ciphertext of the sentinel string "DebFileVault-v1"
    var sentinelCiphertext: Data
    /// 12-byte GCM nonce for the sentinel encryption
    var sentinelNonce: Data
    /// Schema version for future migrations
    var schemaVersion: Int

    init(salt: Data, sentinelCiphertext: Data, sentinelNonce: Data) {
        self.salt = salt
        self.sentinelCiphertext = sentinelCiphertext
        self.sentinelNonce = sentinelNonce
        self.schemaVersion = 1
    }
}
