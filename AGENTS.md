# AGENTS.md — WebMux

## Project Overview

WebMux is a native macOS (14+) desktop app that aggregates web services into a single sidebar-driven window. It is a lightweight alternative to Ferdium/Franz, built with Swift 6 / SwiftUI / WKWebView. The app is ~5MB and uses the system WebKit engine.

## Tech Stack

- **Language:** Swift 6.0 (strict concurrency enabled)
- **UI:** SwiftUI with `NavigationSplitView`
- **Web engine:** WKWebView (system WebKit)
- **Session isolation:** `WKWebsiteDataStore(forIdentifier: UUID)` — requires macOS 14+
- **Build system:** Swift Package Manager (SPM)
- **Dependencies:** FaviconFinder (→ SwiftSoup)

## Project Structure

```
WebMux/
├── Package.swift                 # SPM manifest
├── build.sh                      # Build/bundle/install script
├── Sources/WebMux/
│   ├── WebMuxApp.swift           # @main App entry, WindowGroup
│   ├── ServiceStore.swift        # Service model + JSON persistence
│   ├── WebViewManager.swift      # WKWebView pool with isolated data stores
│   ├── ContentView.swift         # Main UI: sidebar + webview detail
│   ├── AddServiceView.swift      # "Add Service" sheet (name + URL)
│   └── FaviconFetcher.swift      # Favicon download + disk cache
```

## Key Patterns

### Concurrency
All UI-facing classes use `@MainActor @Observable`. Swift 6 strict concurrency is enforced — do not use `nonisolated` or `@Sendable` workarounds without good reason.

### Service Persistence
Services are stored as a JSON array at `~/Library/Application Support/WebMux/services.json`. The `ServiceStore` class handles load/save. Default services are written on first launch.

### WebView Lifecycle
`WebViewManager` lazily creates `WKWebView` instances and keeps them alive in a `[UUID: WKWebView]` dictionary. This prevents page reloads when switching between services in the sidebar. Each webview gets its own `WKWebsiteDataStore(forIdentifier:)` for cookie/storage isolation.

### Favicon Caching
Favicons are fetched via `FaviconFinder` and cached as PNG files in `~/Library/Application Support/WebMux/favicons/{uuid}.png`. The path is stored in `Service.faviconPath`. Missing favicons fall back to the SF Symbol `globe`.

## Build & Run

```bash
./build.sh run          # debug build + launch
./build.sh install      # release build + copy to /Applications
./build.sh clean        # remove build artifacts
```

The script creates a `.app` bundle with an `Info.plist` so macOS treats it as a proper application (Dock icon, Cmd+Tab).

## Common Modifications

### Adding a default service
Edit `Service.defaults` in `ServiceStore.swift`. Note: defaults are only written on first launch (when `services.json` doesn't exist). To reset, delete `~/Library/Application Support/WebMux/services.json`.

### Changing the user agent
Edit `WebViewManager.userAgent`. The current value mimics Safari 17 on macOS to prevent web apps from serving mobile layouts.

### Adding notification badge support
Would require implementing `WKNavigationDelegate` and/or `WKScriptMessageHandler` on each webview to observe title changes or inject JS that monitors unread counts.

### Adding keyboard shortcuts for service switching
Add `.keyboardShortcut()` modifiers to sidebar items in `ContentView`, or use `Cmd+1..9` bindings mapped to `store.services` indices.

### Adding drag-to-reorder services
Replace the `ForEach` in `ContentView` with one that supports `.onMove` and persist the new order via `ServiceStore.save()`.

## Constraints

- macOS 14+ only (for `WKWebsiteDataStore(forIdentifier:)`)
- No Xcode project — built entirely via SPM + `build.sh`
- No code signing — the app runs unsigned locally. For distribution, add signing to `build.sh`
- Web services that block embedded browsers (e.g., some Google services) may require user-agent tweaks
