# DebFileVault

A macOS application built with SwiftUI and SwiftData for managing timestamped items with persistent local storage.

## Overview

DebFileVault is a native macOS app that demonstrates modern Apple development patterns using SwiftUI for the interface and SwiftData for persistence. It features a master-detail navigation layout for creating, viewing, and deleting items.

## Features

- Create timestamped items with a single click
- Persistent local storage (survives app restarts)
- Master-detail split view navigation
- Swipe-to-delete with smooth animations

## Requirements

- macOS Sequoia (26.2+)
- Xcode 26.2+
- Swift 5.0+

## Project Structure

```
DebFileVault/
├── DebFileVaultApp.swift    # App entry point, SwiftData model container setup
├── ContentView.swift        # Main UI: NavigationSplitView with list and detail pane
├── Item.swift               # SwiftData @Model with a single timestamp property
└── Assets.xcassets/         # App icons and accent color
```

## Architecture

- **UI:** SwiftUI with `NavigationSplitView` (master-detail pattern)
- **Persistence:** SwiftData (`@Model`, `ModelContainer`, `@Query`)
- **Pattern:** Reactive MVVM via SwiftUI property wrappers (`@Environment`, `@Query`)

## Getting Started

1. Clone the repository
2. Open `DebFileVault.xcodeproj` in Xcode
3. Select your development team in the project signing settings
4. Build and run (`Cmd+R`)

## Security

- App Sandbox enabled
- Hardened Runtime enabled
- Read-only access to user-selected files
