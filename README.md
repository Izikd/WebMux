# WebMux

A lightweight native macOS app that aggregates web services (WhatsApp, Telegram, Google Messages, etc.) into a single window with a sidebar — similar to [Ferdium](https://ferdium.org), but built as a ~5MB native Swift app instead of a ~250MB Electron bundle.

Each service runs in its own isolated WebKit webview with persistent sessions, so you stay logged in across app restarts.

## Requirements

- **macOS 14 (Sonoma)** or newer
- **Swift 6.0+** (included with Xcode 16+ or Command Line Tools)

## Quick Start

```bash
# Build and launch
./build.sh run

# Or step by step
./build.sh build    # compile
./build.sh bundle   # create .app bundle
open WebMux.app     # launch
```

## Build Commands

| Command | Description |
|---|---|
| `./build.sh build` | Debug build (default) |
| `./build.sh release` | Optimized release build |
| `./build.sh run` | Build + bundle + launch |
| `./build.sh bundle` | Build + create `WebMux.app` |
| `./build.sh install` | Release build + copy to `/Applications` |
| `./build.sh clean` | Remove build artifacts |

## Usage

### Default Services

WebMux comes pre-configured with:
- **WhatsApp** — web.whatsapp.com
- **Telegram** — web.telegram.org
- **Google Messages** — messages.google.com/web

### Adding a Service

1. Click the **+** button in the sidebar toolbar
2. Enter a name (e.g., "Slack")
3. Enter the URL (e.g., `https://app.slack.com`) — `https://` is auto-prepended if omitted
4. Click **Add**

The favicon is automatically fetched and displayed in the sidebar.

### Removing a Service

Right-click a service in the sidebar → **Remove**. This deletes the service and all its stored data (cookies, localStorage).

### Session Isolation

Each service has its own isolated browser session via `WKWebsiteDataStore`. This means:
- You can be logged into multiple accounts simultaneously
- Cookies and localStorage are separate per service
- Sessions persist across app restarts — no need to re-scan QR codes

## Architecture

```
WebMux/
├── Package.swift              # SPM config, macOS 14+, FaviconFinder dependency
├── build.sh                   # Build/deploy script
├── Sources/WebMux/
│   ├── WebMuxApp.swift        # App entry point, SwiftUI lifecycle
│   ├── ServiceStore.swift     # Service model + JSON persistence
│   ├── WebViewManager.swift   # WKWebView lifecycle + session isolation
│   ├── ContentView.swift      # NavigationSplitView sidebar + webview
│   ├── AddServiceView.swift   # Add service sheet
│   └── FaviconFetcher.swift   # Favicon auto-fetch + disk cache
└── WebMux.app/                # Generated app bundle (after build)
```

### Key Components

- **`Service`** — Codable struct: `id` (UUID), `name`, `url`, `faviconPath`
- **`ServiceStore`** — `@Observable` class that persists services to `~/Library/Application Support/WebMux/services.json`
- **`WebViewManager`** — Holds live `WKWebView` instances keyed by service UUID. Each gets a `WKWebsiteDataStore(forIdentifier:)` for session isolation. Webviews stay alive when switching between services.
- **`WebViewContainer`** — `NSViewRepresentable` wrapper to embed WKWebView in SwiftUI
- **`FaviconFetcher`** — Uses [FaviconFinder](https://github.com/will-lumley/FaviconFinder) to detect and cache favicons to `~/Library/Application Support/WebMux/favicons/`

### Data Storage

| What | Where |
|---|---|
| Service list | `~/Library/Application Support/WebMux/services.json` |
| Cached favicons | `~/Library/Application Support/WebMux/favicons/` |
| Per-service cookies/storage | Managed by WebKit via `WKWebsiteDataStore(forIdentifier:)` |

## Dependencies

- [FaviconFinder](https://github.com/will-lumley/FaviconFinder) (v5.0+) — Favicon detection from any URL
  - Transitive: [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML parsing

## License

MIT
