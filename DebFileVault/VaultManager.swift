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
    /// The caller must have already called `url.startAccessingSecurityScopedResource()`.
    static nonisolated func openContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([Item.self, VaultMetadata.self])
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw VaultError.containerCreationFailed(error)
        }
    }

    // MARK: - Security-Scoped Bookmark Persistence

    static let lastVaultBookmarkKey = "com.debprakash.DebFileVault.lastVaultBookmark"

    /// Saves a security-scoped bookmark for `url` so sandbox access survives relaunch.
    static func saveLastVaultURL(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(bookmark, forKey: lastVaultBookmarkKey)
    }

    /// Resolves the stored bookmark back to a URL and starts security-scoped access.
    /// Returns `nil` if no bookmark is stored or the file no longer exists.
    /// **Caller must call `url.stopAccessingSecurityScopedResource()` when done.**
    static func loadLastVaultURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: lastVaultBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale { saveLastVaultURL(url) } // refresh stale bookmark
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func clearLastVaultURL() {
        UserDefaults.standard.removeObject(forKey: lastVaultBookmarkKey)
    }
}
