//
//  NoteListView.swift
//  DebFileVault
//
//  Created by Debprakash Patnaik on 3/8/26.
//

import SwiftUI
import SwiftData
import CryptoKit

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    @Binding var selectedItem: Item?

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    NoteRowView(item: item)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button(action: addItem) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
    }

    private func addItem() {
        guard let key = appState.vaultKey else { return }
        do {
            let (titleCipher, titleNonce) = try EncryptionService.encryptString("New Note", key: key)
            let (contentCipher, contentNonce) = try EncryptionService.encryptString("", key: key)
            let newItem = Item(
                encryptedTitle: titleCipher,
                titleNonce: titleNonce,
                encryptedContent: contentCipher,
                contentNonce: contentNonce
            )
            withAnimation {
                modelContext.insert(newItem)
                selectedItem = newItem
            }
            appState.resetIdleTimer()
        } catch {
            // Key is present (guard passed); encryption failure is unexpected here
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                if selectedItem?.id == items[index].id {
                    selectedItem = nil
                }
                modelContext.delete(items[index])
            }
        }
        appState.resetIdleTimer()
    }
}

// MARK: - Row View

private struct NoteRowView: View {
    @Environment(AppState.self) private var appState
    var item: Item

    @State private var title: String = "Untitled"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onAppear { decryptTitle() }
        .onChange(of: item.encryptedTitle) { decryptTitle() }
    }

    private func decryptTitle() {
        guard let key = appState.vaultKey else { return }
        if let decrypted = try? EncryptionService.decryptString(item.encryptedTitle, nonce: item.titleNonce, key: key) {
            title = decrypted.isEmpty ? "Untitled" : decrypted
        }
    }
}
