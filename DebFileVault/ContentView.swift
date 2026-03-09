//
//  ContentView.swift
//  DebFileVault
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItem: Item? = nil

    var body: some View {
        Group {
            if !appState.hasOpenVault {
                VaultPickerView()
            } else if !appState.isUnlocked {
                LockScreenView()
            } else {
                vaultView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.lockNotification)) { _ in
            appState.lock()
        }
        .onContinuousHover { _ in appState.resetIdleTimer() }
        .onChange(of: appState.isUnlocked) { _, unlocked in
            if !unlocked { selectedItem = nil }
        }
        .onChange(of: appState.hasOpenVault) { _, hasVault in
            if !hasVault { selectedItem = nil }
        }
        .onChange(of: appState.currentVaultURL) { _, url in
            updateWindowTitle(url: url)
        }
        .onAppear {
            updateWindowTitle(url: appState.currentVaultURL)
        }
    }

    private func updateWindowTitle(url: URL?) {
        if let url {
            let name = url.deletingPathExtension().lastPathComponent
            let path = url.deletingLastPathComponent().path(percentEncoded: false)
            NSApp.mainWindow?.title = "\(name) — \(path)"
        } else {
            NSApp.mainWindow?.title = "DebFileVault"
        }
    }

    private var vaultView: some View {
        NavigationSplitView {
            if let container = appState.modelContainer {
                NoteListView(selectedItem: $selectedItem)
                    .modelContainer(container)
                    .navigationTitle(appState.currentVaultURL?.deletingPathExtension().lastPathComponent ?? "Notes")
            }
        } detail: {
            if let item = selectedItem {
                NoteDetailView(item: item)
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "note.text",
                    description: Text("Select a note from the list or create a new one.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { appState.lock() } label: {
                    Label("Lock Vault", systemImage: "lock")
                }
            }
        }
    }
}
