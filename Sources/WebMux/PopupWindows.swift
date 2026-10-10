import AppKit
import WebKit

/// Decides whether a new window requested by a page (window.open / target="_blank")
/// opens inside WebMux or in the user's default browser.
///
/// In WebMux: sign-in style popups, which need `window.opener` to hand the result back,
/// and same-site new windows, which would be logged out in the browser because each
/// service has its own cookies. Everything else (e.g. a news link) goes to the browser.
@MainActor
enum PopupPolicy {
    /// `requestedSize`: the page passed a width/height to window.open.
    static func opensInApp(url: URL?, openerURL: URL?, requestedSize: Bool) -> Bool {
        // A blank window is filled in by script afterwards (Google sign-in does this).
        guard let url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" else { return true }
        // Pages ask for an explicit size for popups; plain links never do.
        if requestedSize { return true }
        if looksLikeSignIn(url) { return true }
        if let openerHost = openerURL?.host, let host = url.host, isSameSite(host, openerHost) { return true }
        return false
    }

    static func isSameSite(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

    private static let signInHosts: Set<String> = [
        "accounts.google.com", "login.microsoftonline.com", "login.live.com", "login.microsoft.com",
        "appleid.apple.com", "idmsa.apple.com", "login.yahoo.com", "id.atlassian.com",
    ]

    static func looksLikeSignIn(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if signInHosts.contains(host) { return true }
        let path = url.path.lowercased()
        if ["/oauth", "/oauth2", "/authorize", "/saml", "/sso"].contains(where: { path.contains($0) }) { return true }
        if host == "github.com", path.hasPrefix("/login") { return true }
        let query = Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.map { $0.name.lowercased() } ?? [])
        return query.contains("client_id") && (query.contains("redirect_uri") || query.contains("response_type"))
    }
}

/// A small window hosting a popup's web view. It closes when the page calls
/// window.close() (via `webViewDidClose`) or when the user closes it (Cmd+W).
@MainActor
final class PopupWindowController: NSObject, NSWindowDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private var titleObservation: NSKeyValueObservation?
    private let onClose: (PopupWindowController) -> Void

    init(webView: WKWebView, features: WKWindowFeatures, isSignIn: Bool,
         parentWindow: NSWindow?, onClose: @escaping (PopupWindowController) -> Void) {
        self.webView = webView
        self.onClose = onClose

        let defaultSize = isSignIn ? NSSize(width: 520, height: 680) : NSSize(width: 1000, height: 760)
        let width = features.width.map { min(max(CGFloat(truncating: $0), 320), 1600) } ?? defaultSize.width
        let height = features.height.map { min(max(CGFloat(truncating: $0), 320), 1200) } ?? defaultSize.height

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        super.init()

        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        window.title = "Loading…"
        if let parent = parentWindow {
            // Centre over the main window.
            let p = parent.frame
            window.setFrameOrigin(NSPoint(x: p.midX - width / 2, y: p.midY - height / 2))
        } else {
            window.center()
        }

        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
            MainActor.assumeIsolated {
                let title = wv.title ?? ""
                self?.window.title = title.isEmpty ? (wv.url?.host ?? "WebMux") : title
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        titleObservation = nil
        webView.stopLoading()
        onClose(self)
    }
}
