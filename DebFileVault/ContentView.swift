//
//  ContentView.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItem: Item? = nil

    var body: some View {
        Group {
            if appState.isUnlocked {
                vaultView
            } else {
                LockScreenView()
            }
        }
        // Lock when screen sleeps or system suspends
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.lockNotification)) { _ in
            appState.lock()
        }
        // Reset idle timer on any mouse/keyboard activity in the window
        .onContinuousHover { _ in appState.resetIdleTimer() }
    }

    // MARK: - Vault (unlocked)

    private var vaultView: some View {
        NavigationSplitView {
            NoteListView(selectedItem: $selectedItem)
                .navigationTitle("Notes")
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
                Button {
                    appState.lock()
                } label: {
                    Label("Lock Vault", systemImage: "lock")
                }
            }
        }
    }
}
