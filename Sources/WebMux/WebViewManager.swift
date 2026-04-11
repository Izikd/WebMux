import SwiftUI
import WebKit

@MainActor @Observable
final class WebViewManager {
    private var webViews: [UUID: WKWebView] = [:]

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    func webView(for service: Service) -> WKWebView {
        if let existing = webViews[service.id] { return existing }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.load(URLRequest(url: service.url))
        webViews[service.id] = wv
        applyFont(to: wv)
        return wv
    }

    func removeWebView(for id: UUID) {
        webViews.removeValue(forKey: id)
    }

    func reload(for id: UUID) {
        webViews[id]?.reload()
    }

    func applyFontToAll() {
        for wv in webViews.values { applyFont(to: wv) }
    }

    private func applyFont(to wv: WKWebView) {
        let settings = FontSettings.shared
        if !settings.enabled {
            let remove = "var s = document.getElementById('webmux-font'); if (s) s.remove();"
            wv.evaluateJavaScript(remove, completionHandler: nil)
            return
        }
        guard !settings.fontFamily.isEmpty else { return }
        let css = """
            var existingStyle = document.getElementById('webmux-font');
            if (existingStyle) existingStyle.remove();
            var style = document.createElement('style');
            style.id = 'webmux-font';
            style.textContent = `
                * {
                    font-family: "\(settings.fontFamily)", -apple-system, sans-serif !important;
                    -webkit-font-smoothing: antialiased !important;
                    text-rendering: optimizeLegibility !important;
                    \(settings.fontSize > 0 ? "font-size: \(settings.fontSize)px !important;" : "")
                }
                code, pre { font-family: ui-monospace, Menlo, monospace !important; }
            `;
            document.head.appendChild(style);
            """
        wv.evaluateJavaScript(css, completionHandler: nil)
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
