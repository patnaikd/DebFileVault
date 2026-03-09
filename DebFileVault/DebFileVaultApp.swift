//
//  DebFileVaultApp.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import SwiftUI
import SwiftData

@main
struct DebFileVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        // Store path is inside the App Sandbox container — protected by macOS App Sandbox.
        // Field-level AES-256-GCM encryption provides additional protection for note content.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed and lightweight migration failed (e.g. non-optional columns added).
            // Delete the store and recreate from scratch. All data was encrypted; no plaintext lost.
            let storeURL = URL.applicationSupportDirectory
                .appendingPathComponent("default.store")
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension(ext.isEmpty ? "" : String(ext.dropFirst())))
            }
            // Also try exact filenames used by SwiftData
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                let url = URL.applicationSupportDirectory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after store deletion: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - App Delegate (screen sleep / lock events)

final class AppDelegate: NSObject, NSApplicationDelegate {
    // AppState is shared via environment; we lock via a notification to decouple.
    static let lockNotification = Notification.Name("DebFileVault.lockVault")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
    }

    @objc private func handleSleep() {
        NotificationCenter.default.post(name: AppDelegate.lockNotification, object: nil)
    }
}
