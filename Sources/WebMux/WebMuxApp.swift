import SwiftUI

@main
struct WebMuxApp: App {
    @State private var store = ServiceStore()
    @State private var showingAbout = false

    var body: some Scene {
        // A single window: each service's session must only be open once.
        Window("WebMux", id: "main") {
            ContentView(store: store)
                .background(WindowFrameKeeper(key: "mainWindowFrame"))
                .task {
                    await store.removeOrphanedServiceData()
                    await FaviconFetcher.fetchAll(store: store)
                }
                .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WebMux") { showingAbout = true }
            }
        }
    }
}

/// Remembers the main window's frame in UserDefaults and restores it at launch.
///
/// Done by hand because the automatic options didn't hold: WindowGroup keyed the saved
/// frame by the root view's type (which changed with most code changes), and AppKit's
/// frame autosave didn't record user resizes for this SwiftUI-managed window.
struct WindowFrameKeeper: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView { KeeperView(key: key) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeeperView: NSView {
        private let key: String
        private var observers: [NSObjectProtocol] = []

        init(key: String) {
            self.key = key
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // Restore after SwiftUI has applied its own initial size, and only then
            // start saving, so that initial size never overwrites the saved one.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.restore(window)
                self.startSaving(window)
            }
        }

        private func restore(_ window: NSWindow) {
            guard let saved = UserDefaults.standard.string(forKey: key) else { return }
            let frame = NSRectFromString(saved)
            // Ignore garbage, and frames that are no longer on any screen (e.g. an unplugged display).
            guard frame.width >= 300, frame.height >= 200,
                  NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
            window.setFrame(frame, display: true)
        }

        private func startSaving(_ window: NSWindow) {
            let center = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated { if let window { self?.save(window) } }
                })
            }
            observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated { if let window { self?.save(window) } }
            })
        }

        private func save(_ window: NSWindow) {
            // Don't store a full-screen or minimized frame as the normal window size.
            guard !window.styleMask.contains(.fullScreen), !window.isMiniaturized else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
        }
    }
}
