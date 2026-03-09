//
//  EncryptionService.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import Foundation
import CryptoKit
import CommonCrypto

enum EncryptionError: Error, LocalizedError {
    case keyDerivationFailed
    case invalidNonce
    case encryptionFailed
    case decryptionFailed
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed: return "Failed to derive encryption key from password."
        case .invalidNonce: return "Invalid nonce data."
        case .encryptionFailed: return "Encryption failed."
        case .decryptionFailed: return "Decryption failed. The password may be incorrect."
        case .invalidData: return "Invalid encrypted data."
        }
    }
}

// Pure stateless crypto utility. All methods are nonisolated so they can be called
// from any Swift concurrency context, including Task.detached off the main actor.
struct EncryptionService {

    // PBKDF2-SHA256 iteration count (OWASP 2023 recommendation for AES-256)
    // NOTE: Memory zeroing of the derived SymmetricKey is not guaranteed by Swift value types.
    // Setting vaultKey = nil releases the reference; the OS allocator reclaims the memory
    // but does not guarantee zeroing. This is a known Swift limitation for key material.
    nonisolated(unsafe) static let pbkdf2Iterations = 310_000

    // MARK: - Key Derivation

    /// Derives a 256-bit AES key from a password and salt using PBKDF2-SHA256.
    /// The salt should be a random 16-byte value generated once per vault.
    static nonisolated func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        var derivedKeyData = Data(count: 32) // 256 bits for AES-256

        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(pbkdf2Iterations),
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    32
                )
            }
        }

        guard result == kCCSuccess else { throw EncryptionError.keyDerivationFailed }
        return SymmetricKey(data: derivedKeyData)
    }

    // MARK: - Salt Generation

    /// Generates a cryptographically random 16-byte salt.
    static nonisolated func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Encryption

    /// Encrypts plaintext data with AES-256-GCM.
    /// Returns (ciphertext+tag, nonce). A fresh random nonce is generated per call.
    static nonisolated func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        let nonce = AES.GCM.Nonce() // cryptographically random 12 bytes
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        // Concatenate ciphertext and authentication tag (tag is 16 bytes)
        let ciphertextWithTag = sealedBox.ciphertext + sealedBox.tag
        return (ciphertextWithTag, Data(nonce))
    }

    /// Encrypts a String (UTF-8) with AES-256-GCM.
    static nonisolated func encryptString(_ string: String, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        guard let data = string.data(using: .utf8) else { throw EncryptionError.invalidData }
        return try encrypt(data, key: key)
    }

    // MARK: - Decryption

    /// Decrypts AES-256-GCM ciphertext. The ciphertext must include the 16-byte GCM tag as the last bytes.
    /// Throws CryptoKitError.authenticationFailure if the key is wrong or data is tampered.
    static nonisolated func decrypt(_ ciphertextWithTag: Data, nonce nonceData: Data, key: SymmetricKey) throws -> Data {
        guard ciphertextWithTag.count >= 16 else { throw EncryptionError.invalidData }
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else { throw EncryptionError.invalidNonce }

        let tag = ciphertextWithTag.suffix(16)
        let ciphertext = ciphertextWithTag.dropLast(16)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Decrypts AES-256-GCM ciphertext and returns a UTF-8 String.
    static nonisolated func decryptString(_ ciphertextWithTag: Data, nonce: Data, key: SymmetricKey) throws -> String {
        let data = try decrypt(ciphertextWithTag, nonce: nonce, key: key)
        guard let string = String(data: data, encoding: .utf8) else { throw EncryptionError.invalidData }
        return string
    }
}
