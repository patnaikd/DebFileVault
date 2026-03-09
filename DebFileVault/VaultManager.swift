//
//  VaultManager.swift
//  DebFileVault
//

import Foundation
import SwiftData

enum VaultError: Error, LocalizedError {
    case invalidURL
    case containerCreationFailed(Error)
    case metadataNotFound
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid vault file location."
        case .containerCreationFailed(let e): return "Could not open vault: \(e.localizedDescription)"
        case .metadataNotFound: return "Vault metadata is missing. The file may be corrupted."
        case .alreadyExists: return "A vault file already exists at that location."
        }
    }
}

struct VaultManager {

    static let fileExtension = "debfilevault"

    /// Creates a ModelContainer backed by a .debfilevault file at the given URL.
    static nonisolated func openContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([Item.self, VaultMetadata.self])
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw VaultError.containerCreationFailed(error)
        }
    }

    /// UserDefaults key for remembering the last opened vault path.
    static let lastVaultURLKey = "com.debprakash.DebFileVault.lastVaultURL"

    static func saveLastVaultURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: lastVaultURLKey)
    }

    static func loadLastVaultURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: lastVaultURLKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func clearLastVaultURL() {
        UserDefaults.standard.removeObject(forKey: lastVaultURLKey)
    }
}
