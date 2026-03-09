//
//  DebFileVaultApp.swift
//  DebFileVault
//

import SwiftUI
import SwiftData

@main
struct DebFileVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    // Wire AppDelegate immediately so file-open events work before first view appears
                    appDelegate.appState = appState
                    // One-time migration: remove legacy UserDefaults vault keys from previous version
                    let legacyKeys = [
                        "com.debprakash.DebFileVault.vaultSalt",
                        "com.debprakash.DebFileVault.sentinelCiphertext",
                        "com.debprakash.DebFileVault.sentinelNonce"
                    ]
                    for key in legacyKeys {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                    // Auto-open the last vault on launch (skip the picker if path still exists)
                    if let url = VaultManager.loadLastVaultURL() {
                        // If the vault no longer exists or is corrupt, silently fall through to the picker
                        try? appState.openVault(at: url)
                    }
                }
        }
        // No static .modelContainer — the container is managed dynamically by AppState
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let lockNotification = Notification.Name("DebFileVault.lockVault")
    // Set by ContentView.onAppear for file-open handling
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    /// Called when the user double-clicks a .debfilevault file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            do {
                try appState?.openVault(at: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not open vault"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func handleSleep() {
        NotificationCenter.default.post(name: AppDelegate.lockNotification, object: nil)
    }
}
