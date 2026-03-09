# DebFileVault

A native macOS encrypted notes vault built with SwiftUI and SwiftData. All note content is encrypted at rest with AES-256-GCM — nothing is ever stored in plaintext.

## Features

- Master password protection with a lock screen on every launch
- AES-256-GCM encryption for all note titles and content
- Create, rename, and delete notes
- Editable title and body per note, with auto-save on change
- Created and last modified timestamps shown per note
- Auto-locks after 5 minutes of inactivity
- Manual lock button in the toolbar
- Locks automatically on screen sleep

## Requirements

- macOS Sequoia (26.2+)
- Xcode 26.2+
- Swift 5.0+

## Getting Started

1. Clone the repository
2. Open `DebFileVault.xcodeproj` in Xcode
3. Select your development team in the project signing settings
4. Build and run (`Cmd+R`)
5. On first launch, create a master password (minimum 8 characters)

## Project Structure

```
DebFileVault/
├── DebFileVaultApp.swift    # App entry point, SwiftData container, sleep/lock delegate
├── AppState.swift           # @Observable vault lifecycle: unlock, lock, idle timer
├── EncryptionService.swift  # AES-256-GCM + PBKDF2-SHA256 crypto (CryptoKit + CommonCrypto)
├── Item.swift               # SwiftData @Model — encrypted title, content, nonces, timestamps
├── ContentView.swift        # Root view: lock screen gate + NavigationSplitView
├── LockScreenView.swift     # First-launch setup and subsequent unlock UI
├── NoteListView.swift       # Sidebar: decrypted note titles, add/delete
├── NoteDetailView.swift     # Detail pane: editable title + body, auto-save, metadata footer
└── Assets.xcassets/         # App icons and accent color
```

## Architecture

- **UI:** SwiftUI with `NavigationSplitView` (master-detail)
- **Persistence:** SwiftData (`@Model`, `ModelContainer`, `@Query`)
- **State:** `@Observable` `AppState` injected via SwiftUI environment
- **Crypto:** `EncryptionService` — pure stateless struct, no third-party dependencies

## Data Storage

All data is stored locally on-device in two locations:

### SwiftData SQLite store — note content (encrypted)
```
~/Library/Containers/com.debprakash.DebFileVault/Data/Library/Application Support/default.store
```
Contains the `Item` table with columns: `id`, `createdAt`, `modifiedAt`, `encryptedTitle`, `titleNonce`, `encryptedContent`, `contentNonce`. All note data is stored as AES-256-GCM ciphertext. No plaintext is ever written to disk.

### UserDefaults — vault metadata (not secret)
```
~/Library/Containers/com.debprakash.DebFileVault/Data/Library/Preferences/com.debprakash.DebFileVault.plist
```
Contains three keys:
- `vaultSalt` — random PBKDF2 salt (not sensitive; prevents rainbow table attacks)
- `sentinelCiphertext` — encrypted known string used to verify the master password on unlock
- `sentinelNonce` — GCM nonce for the sentinel

**The derived AES-256 key is never stored anywhere.** It exists only in memory while the vault is unlocked (`AppState.vaultKey`) and is released when you lock.

## Security

| Property | Detail |
|---|---|
| Encryption | AES-256-GCM |
| Key derivation | PBKDF2-SHA256, 310,000 iterations (OWASP 2023) |
| Nonce | Fresh cryptographically random 12-byte nonce per save |
| Password verification | GCM authentication tag failure on sentinel decryption — no password hash stored |
| Key storage | In-memory only; `nil`-ed on lock |
| Wrong password | `CryptoKitError.authenticationFailure` — cannot decrypt, no information leaked |
| Libraries | Apple CryptoKit + CommonCrypto only — no third-party dependencies |
| App Sandbox | Enabled |
| Hardened Runtime | Enabled |
