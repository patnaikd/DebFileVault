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
        .onAppear {
            // Give AppDelegate a reference to AppState for file-open handling
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.appState = appState
            }
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
