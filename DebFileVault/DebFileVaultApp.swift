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
            fatalError("Could not create ModelContainer: \(error)")
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
