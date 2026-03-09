# Vault File Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the fixed SwiftData store location with user-chosen `.debfilevault` files, add file association so the app opens when you double-click a vault, store vault metadata (salt, sentinel) inside the SQLite file in a `VaultMetadata` SwiftData model, remember the last opened vault path, and provide UI to create or open vaults.

**Architecture:** `AppState` gains a `currentVaultURL: URL?` property. `ModelContainer` is created dynamically from the chosen URL rather than from a fixed path. A new `VaultMetadata` SwiftData model replaces `UserDefaults` for salt/sentinel storage. The app entry point becomes a vault picker if no vault is remembered.

**Tech Stack:** SwiftUI, SwiftData, CryptoKit, CommonCrypto, NSOpenPanel/NSSavePanel, `LSItemContentTypes` / `CFBundleDocumentTypes` in `Info.plist`, `application(_:open:)` delegate method.

---

## Overview of Changes

| Area | What changes |
|---|---|
| `Info.plist` | Register `.debfilevault` UTI and document type |
| `VaultMetadata.swift` | New SwiftData `@Model` storing salt + sentinel inside the vault file |
| `AppState.swift` | Add `currentVaultURL`, move metadata reads/writes from `UserDefaults` to `VaultMetadata`, load/create `ModelContainer` at runtime from URL |
| `DebFileVaultApp.swift` | Remove static `sharedModelContainer`; pass dynamic container; handle `application(_:open:)` |
| `VaultPickerView.swift` | New view: "Create New Vault" + "Open Existing Vault" + recent vault button |
| `ContentView.swift` | Show `VaultPickerView` when no vault is open instead of `LockScreenView` |
| `LockScreenView.swift` | Receive vault metadata from `AppState` instead of `UserDefaults` |
| `UserDefaults` | Remove all three vault keys; add single `lastVaultURL` key |

---

## Task 1: Register `.debfilevault` file type in the Xcode project

**Files:**
- Create: `DebFileVault/DebFileVault.entitlements` (if not already present — check first)
- Modify: `DebFileVault/Info.plist` (create if absent; Xcode may auto-generate)

Xcode project uses File System Synchronized Groups, so `Info.plist` must be added manually in Xcode's target settings (General → Info → Document Types / Exported Type Identifiers). Since we can't run Xcode GUI steps in code, we add the Info.plist key directly.

**Step 1: Check if Info.plist exists**

```bash
ls /Users/debprakash/Documents/GitHub/DebFileVault/DebFileVault/Info.plist
```

**Step 2: Create Info.plist with UTI and document type registration**

Create `DebFileVault/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Exported UTI: declares .debfilevault as a type this app owns -->
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.debprakash.debfilevault</string>
            <key>UTTypeDescription</key>
            <string>DebFileVault Encrypted Vault</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>com.apple.package</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>debfilevault</string>
                </array>
            </dict>
        </dict>
    </array>
    <!-- Document type: tells the OS this app opens .debfilevault files -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DebFileVault Encrypted Vault</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.debprakash.debfilevault</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Owner</string>
        </dict>
    </array>
</dict>
</plist>
```

**Step 3: Verify Info.plist is valid XML**

```bash
plutil -lint /Users/debprakash/Documents/GitHub/DebFileVault/DebFileVault/Info.plist
```
Expected: `OK`

**Step 4: Commit**

```bash
git add DebFileVault/Info.plist
git commit -m "feat: register .debfilevault UTI and document type"
```

---

## Task 2: Create `VaultMetadata` SwiftData model

**Files:**
- Create: `DebFileVault/VaultMetadata.swift`

This model stores the vault's PBKDF2 salt and encrypted sentinel inside the same SQLite file as the notes. One row ever exists per vault.

**Step 1: Create `VaultMetadata.swift`**

```swift
//
//  VaultMetadata.swift
//  DebFileVault
//

import Foundation
import SwiftData

/// Stores per-vault cryptographic metadata inside the vault's SQLite file.
/// There is exactly one row per vault, created during vault setup.
/// None of this data is secret — salt prevents rainbow tables,
/// sentinel ciphertext is used only to verify the correct password.
@Model
final class VaultMetadata {
    /// PBKDF2-SHA256 salt (16 bytes, random, generated once at vault creation)
    var salt: Data
    /// AES-256-GCM ciphertext of the sentinel string "DebFileVault-v1"
    var sentinelCiphertext: Data
    /// 12-byte GCM nonce for the sentinel encryption
    var sentinelNonce: Data
    /// Schema version for future migrations
    var schemaVersion: Int

    init(salt: Data, sentinelCiphertext: Data, sentinelNonce: Data) {
        self.salt = salt
        self.sentinelCiphertext = sentinelCiphertext
        self.sentinelNonce = sentinelNonce
        self.schemaVersion = 1
    }
}
```

**Step 2: Commit**

```bash
git add DebFileVault/VaultMetadata.swift
git commit -m "feat: add VaultMetadata SwiftData model for per-vault crypto metadata"
```

---

## Task 3: Add `VaultManager` — dynamic ModelContainer creation

**Files:**
- Create: `DebFileVault/VaultManager.swift`

This is a pure utility (no SwiftUI imports) that creates and opens `ModelContainer` instances at user-chosen URLs with the `.debfilevault` extension.

**Step 1: Create `VaultManager.swift`**

```swift
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
    /// The URL must end in .debfilevault.
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
        // Only return if the file still exists
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func clearLastVaultURL() {
        UserDefaults.standard.removeObject(forKey: lastVaultURLKey)
    }
}
```

**Step 2: Commit**

```bash
git add DebFileVault/VaultManager.swift
git commit -m "feat: add VaultManager for dynamic ModelContainer creation at user-chosen URLs"
```

---

## Task 4: Rewrite `AppState` to use dynamic vault URL and `VaultMetadata`

**Files:**
- Modify: `DebFileVault/AppState.swift`

Key changes:
- Remove all `UserDefaults` reads/writes for salt/sentinel
- Add `currentVaultURL: URL?` and `modelContainer: ModelContainer?`
- `setupVault` writes `VaultMetadata` row into the new container
- `unlock` reads `VaultMetadata` from the container
- Add `openVault(at:)` and `createVault(at:password:)` entry points
- Remove `vaultSalt` computed property (no longer needed by views)

**Step 1: Rewrite `AppState.swift`**

```swift
//
//  AppState.swift
//  DebFileVault
//

import Foundation
import CryptoKit
import Observation
import SwiftData

private nonisolated(unsafe) let sentinelPlaintext = "DebFileVault-v1"

@MainActor
@Observable
final class AppState {

    // MARK: - Public State

    private(set) var isUnlocked: Bool = false
    private(set) var vaultKey: SymmetricKey? = nil
    private(set) var currentVaultURL: URL? = nil
    private(set) var modelContainer: ModelContainer? = nil

    // MARK: - Create New Vault

    /// Creates a new .debfilevault file at `url`, sets up the password, and unlocks.
    func createVault(at url: URL, password: String) async throws {
        let container = try VaultManager.openContainer(at: url)

        let (key, metadata) = try await Task.detached(priority: .userInitiated) {
            let salt = EncryptionService.generateSalt()
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            guard let sentinelData = sentinelPlaintext.data(using: .utf8) else {
                throw EncryptionError.encryptionFailed
            }
            let (ciphertext, nonce) = try EncryptionService.encrypt(sentinelData, key: key)
            let metadata = VaultMetadata(salt: salt, sentinelCiphertext: ciphertext, sentinelNonce: nonce)
            return (key, metadata)
        }.value

        // Insert VaultMetadata into the new container
        let context = ModelContext(container)
        context.insert(metadata)
        try context.save()

        currentVaultURL = url
        modelContainer = container
        vaultKey = key
        isUnlocked = true
        VaultManager.saveLastVaultURL(url)
        startIdleTimer()
    }

    // MARK: - Open Existing Vault

    /// Opens an existing .debfilevault file. Returns true if metadata found (ready to unlock).
    /// Does NOT unlock — call unlock(password:) after this.
    func openVault(at url: URL) throws {
        let container = try VaultManager.openContainer(at: url)
        currentVaultURL = url
        modelContainer = container
        VaultManager.saveLastVaultURL(url)
    }

    // MARK: - Unlock

    /// Unlocks the currently open vault with the master password.
    /// Throws CryptoKitError.authenticationFailure if the password is wrong.
    func unlock(password: String) async throws {
        guard let container = modelContainer else { throw VaultError.metadataNotFound }

        let context = ModelContext(container)
        let metadata = try context.fetch(FetchDescriptor<VaultMetadata>()).first
        guard let metadata else { throw VaultError.metadataNotFound }

        let salt = metadata.salt
        let sentinelCiphertext = metadata.sentinelCiphertext
        let sentinelNonce = metadata.sentinelNonce

        let key = try await Task.detached(priority: .userInitiated) {
            let key = try EncryptionService.deriveKey(password: password, salt: salt)
            _ = try EncryptionService.decrypt(sentinelCiphertext, nonce: sentinelNonce, key: key)
            return key
        }.value

        vaultKey = key
        isUnlocked = true
        startIdleTimer()
    }

    // MARK: - Lock

    func lock() {
        vaultKey = nil
        isUnlocked = false
        cancelIdleTimer()
        // Keep modelContainer and currentVaultURL — we stay on the lock screen for this vault
    }

    // MARK: - Close Vault (return to picker)

    func closeVault() {
        lock()
        modelContainer = nil
        currentVaultURL = nil
    }

    // MARK: - Idle Timer

    private var idleTimer: Timer?
    private let idleTimeoutSeconds: TimeInterval = 5 * 60

    func resetIdleTimer() {
        guard isUnlocked else { return }
        cancelIdleTimer()
        startIdleTimer()
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lock()
        }
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Convenience

    var hasOpenVault: Bool { modelContainer != nil }
    var isFirstLaunch: Bool { !hasOpenVault }
}
```

**Step 2: Commit**

```bash
git add DebFileVault/AppState.swift
git commit -m "feat: rewrite AppState to use dynamic vault URL and VaultMetadata model"
```

---

## Task 5: Create `VaultPickerView`

**Files:**
- Create: `DebFileVault/VaultPickerView.swift`

Shown when no vault is open. Has three actions:
1. **Create New Vault** — `NSSavePanel` for a `.debfilevault` location → calls `appState.createVault(at:password:)` → shows inline password setup
2. **Open Existing Vault** — `NSOpenPanel` filtered to `.debfilevault` → calls `appState.openVault(at:)` → navigates to lock screen
3. **Open Last Vault** (shown only if `VaultManager.loadLastVaultURL()` returns non-nil)

```swift
//
//  VaultPickerView.swift
//  DebFileVault
//

import SwiftUI

struct VaultPickerView: View {
    @Environment(AppState.self) private var appState

    @State private var showingCreatePassword = false
    @State private var newVaultURL: URL? = nil
    @State private var createPassword = ""
    @State private var createConfirm = ""
    @State private var errorMessage: String? = nil
    @State private var isWorking = false

    private var lastVaultURL: URL? { VaultManager.loadLastVaultURL() }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("DebFileVault")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Choose a vault to open or create a new one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if showingCreatePassword, let url = newVaultURL {
                createPasswordForm(for: url)
            } else {
                pickerButtons
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 460)
    }

    // MARK: - Picker Buttons

    private var pickerButtons: some View {
        VStack(spacing: 12) {
            if let url = lastVaultURL {
                Button {
                    openVault(at: url)
                } label: {
                    Label("Open \(url.deletingPathExtension().lastPathComponent)", systemImage: "clock")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)

                Divider().frame(maxWidth: 260)
            }

            Button {
                presentOpenPanel()
            } label: {
                Label("Open Existing Vault…", systemImage: "folder")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.bordered)

            Button {
                presentCreatePanel()
            } label: {
                Label("Create New Vault…", systemImage: "plus.circle")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.bordered)

            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Create Password Form

    private func createPasswordForm(for url: URL) -> some View {
        VStack(spacing: 12) {
            Text("Set a master password for\n\"\(url.deletingPathExtension().lastPathComponent)\"")
                .font(.headline).multilineTextAlignment(.center)

            SecureField("Master Password", text: $createPassword)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            SecureField("Confirm Password", text: $createConfirm)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280)

            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingCreatePassword = false
                    newVaultURL = nil
                    createPassword = ""
                    createConfirm = ""
                    errorMessage = nil
                }
                .buttonStyle(.bordered)

                Button("Create Vault") {
                    createVault(at: url)
                }
                .buttonStyle(.borderedProminent)
                .disabled(createPassword.isEmpty || isWorking)
            }
        }
    }

    // MARK: - Actions

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: VaultManager.fileExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a DebFileVault vault file"
        if panel.runModal() == .OK, let url = panel.url {
            openVault(at: url)
        }
    }

    private func presentCreatePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: VaultManager.fileExtension)!]
        panel.nameFieldStringValue = "MyVault"
        panel.message = "Choose where to save your new vault"
        if panel.runModal() == .OK, let url = panel.url {
            newVaultURL = url
            showingCreatePassword = true
        }
    }

    private func openVault(at url: URL) {
        errorMessage = nil
        do {
            try appState.openVault(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createVault(at url: URL) {
        guard createPassword == createConfirm else {
            errorMessage = "Passwords do not match."
            return
        }
        guard createPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await appState.createVault(at: url, password: createPassword)
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add DebFileVault/VaultPickerView.swift
git commit -m "feat: add VaultPickerView with create/open/recent vault actions"
```

---

## Task 6: Update `LockScreenView` to use `AppState` metadata (not `UserDefaults`)

**Files:**
- Modify: `DebFileVault/LockScreenView.swift`

`LockScreenView` is now only shown when a vault is open but locked. Remove the first-launch / setup logic (that's now in `VaultPickerView`). It only needs to call `appState.unlock(password:)`.

**Step 1: Rewrite `LockScreenView.swift`**

```swift
//
//  LockScreenView.swift
//  DebFileVault
//

import SwiftUI
import CryptoKit

struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var errorMessage: String? = nil
    @State private var isWorking = false

    var vaultName: String {
        appState.currentVaultURL?.deletingPathExtension().lastPathComponent ?? "Vault"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text(vaultName)
                    .font(.largeTitle).fontWeight(.bold)
                Text("Enter your master password to unlock.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Master Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { handleUnlock() }

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Button(action: handleUnlock) {
                    if isWorking {
                        ProgressView().scaleEffect(0.7).frame(width: 80, height: 20)
                    } else {
                        Text("Unlock").frame(width: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isWorking)
                .keyboardShortcut(.return)

                Button("Choose Different Vault…") {
                    appState.closeVault()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 400)
    }

    private func handleUnlock() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await appState.unlock(password: password)
            } catch is CryptoKitError {
                errorMessage = "Incorrect password. Please try again."
                isWorking = false
                password = ""
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add DebFileVault/LockScreenView.swift
git commit -m "feat: simplify LockScreenView — unlock only, vault name in header, choose different vault link"
```

---

## Task 7: Update `ContentView` to handle vault picker → lock → unlocked states

**Files:**
- Modify: `DebFileVault/ContentView.swift`

Three states:
1. `!appState.hasOpenVault` → `VaultPickerView`
2. `appState.hasOpenVault && !appState.isUnlocked` → `LockScreenView`
3. `appState.hasOpenVault && appState.isUnlocked` → vault `NavigationSplitView`

**Step 1: Update `ContentView.swift`**

```swift
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
```

**Step 2: Commit**

```bash
git add DebFileVault/ContentView.swift
git commit -m "feat: update ContentView to show picker → lock → vault states"
```

---

## Task 8: Update `DebFileVaultApp` — remove static container, handle file open

**Files:**
- Modify: `DebFileVault/DebFileVaultApp.swift`

Remove the static `sharedModelContainer`. The container is now created dynamically by `AppState`. Pass `appState.modelContainer` into the view hierarchy only when available. Handle `application(_:open:)` in `AppDelegate` to support double-clicking a `.debfilevault` file in Finder.

On launch, check `VaultManager.loadLastVaultURL()` and auto-open the last vault (skipping the picker).

**Step 1: Rewrite `DebFileVaultApp.swift`**

```swift
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
                    // Auto-open the last vault on launch (skip the picker if path still exists)
                    if let url = VaultManager.loadLastVaultURL() {
                        try? appState.openVault(at: url)
                    }
                }
        }
        // No static .modelContainer here — applied dynamically per vault in ContentView
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let lockNotification = Notification.Name("DebFileVault.lockVault")
    // AppState reference set by the app on launch for file-open handling
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
            try? appState?.openVault(at: url)
        }
    }

    @objc private func handleSleep() {
        NotificationCenter.default.post(name: AppDelegate.lockNotification, object: nil)
    }
}
```

Note: `AppDelegate.appState` needs to be set. Do this in `ContentView.onAppear` or via a custom environment approach. The simplest bridge: post a notification from `ContentView` when `appState` is ready, or set it via the scene's `onChange`. See step below.

**Step 2: Wire `appState` into `AppDelegate` from `DebFileVaultApp.body`**

Add `.onChange(of: appState.hasOpenVault)` is not ideal. Instead, set it directly in `body` using a computed approach — add to `ContentView.onAppear`:

In `ContentView.swift`, add inside `body`:
```swift
.onAppear {
    // Give AppDelegate a reference to AppState for file-open handling
    if let delegate = NSApp.delegate as? AppDelegate {
        delegate.appState = appState
    }
}
```

**Step 3: Commit**

```bash
git add DebFileVault/DebFileVaultApp.swift DebFileVault/ContentView.swift
git commit -m "feat: remove static ModelContainer, add file-open handler, auto-open last vault on launch"
```

---

## Task 9: Update `NoteListView` — remove `@Query` (container now injected per vault)

**Files:**
- Modify: `DebFileVault/NoteListView.swift`

The `@Query` macro needs the `modelContainer` in the environment, which is now injected dynamically in `ContentView`. No change to the `@Query` itself — it will pick up the container from `.modelContainer(container)` applied in `ContentView`. Verify this compiles correctly.

If `@Query` does not pick up the dynamic container, wrap `NoteListView` in a helper that accepts the container explicitly and applies `.modelContainer()`.

**Step 1: Verify the build compiles after Task 8**

Build in Xcode (`Cmd+B`). If `@Query` errors about missing container, apply this fix in `ContentView.vaultView`:

```swift
NoteListView(selectedItem: $selectedItem)
    .modelContainer(container)  // already present — this feeds @Query
```

**Step 2: Commit if any changes were needed**

```bash
git add DebFileVault/NoteListView.swift
git commit -m "fix: ensure NoteListView @Query picks up dynamic model container"
```

---

## Task 10: Remove `UserDefaults` vault keys from `AppState` and clean up

**Files:**
- Modify: `DebFileVault/AppState.swift` (already done in Task 4 — verify no `UserDefaults` vault key references remain)

**Step 1: Grep for old UserDefaults vault key usage**

```bash
grep -r "vaultSalt\|sentinelCiphertext\|sentinelNonce\|VaultKeys" \
  /Users/debprakash/Documents/GitHub/DebFileVault/DebFileVault/
```
Expected: no matches (all moved to `VaultMetadata` in the SQLite file).

**Step 2: Delete old sentinel/salt from UserDefaults on first run (migration)**

In `DebFileVaultApp.body`, inside `.task { }`, add before the auto-open:
```swift
// One-time migration: remove old UserDefaults vault keys from previous app version
let legacyKeys = [
    "com.debprakash.DebFileVault.vaultSalt",
    "com.debprakash.DebFileVault.sentinelCiphertext",
    "com.debprakash.DebFileVault.sentinelNonce"
]
for key in legacyKeys {
    UserDefaults.standard.removeObject(forKey: key)
}
```

**Step 3: Commit**

```bash
git add DebFileVault/DebFileVaultApp.swift
git commit -m "chore: remove legacy UserDefaults vault keys on launch (migration)"
```

---

## Verification Checklist

1. **Build succeeds** with no warnings (`Cmd+B` in Xcode)
2. **First launch** (no last vault remembered): vault picker shown with "Create New Vault" and "Open Existing Vault"
3. **Create vault**: `NSSavePanel` opens → name a vault → set password → vault unlocks, notes list shown
4. **Quit and relaunch**: auto-opens last vault → lock screen shown with vault name → correct password unlocks
5. **Wrong password**: shows "Incorrect password" error, stays locked
6. **Lock button**: locks immediately, lock screen shown
7. **Choose Different Vault**: closes vault, returns to picker
8. **Open existing vault**: `NSOpenPanel` filtered to `.debfilevault` files → opens and shows lock screen
9. **File association**: double-click a `.debfilevault` file in Finder → app opens and shows lock screen for that vault
10. **Metadata location**: inspect the `.debfilevault` SQLite file with a DB browser → confirm `VAULTMETADATA` table exists with one row containing salt and sentinel ciphertext; confirm no plaintext in `ITEM` table
11. **5-minute idle**: after 5 min of inactivity, vault auto-locks
12. **Screen sleep**: locks on sleep
