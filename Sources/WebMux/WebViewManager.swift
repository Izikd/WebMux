import SwiftUI
import WebKit

@MainActor @Observable
final class WebViewManager {
    private var webViews: [UUID: WKWebView] = [:]

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func webView(for service: Service) -> WKWebView {
        if let existing = webViews[service.id] { return existing }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.load(URLRequest(url: service.url))
        webViews[service.id] = wv
        return wv
    }

    func removeWebView(for id: UUID) {
        webViews.removeValue(forKey: id)
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
