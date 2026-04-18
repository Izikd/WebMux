import SwiftUI
import WebKit

@MainActor @Observable
final class WebViewManager {
    private var webViews: [UUID: WKWebView] = [:]

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    func webView(for service: Service) -> WKWebView {
        if let existing = webViews[service.id] { return existing }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)

        // Blob download JS injection
        let blobScript = WKUserScript(
            source: WebViewLinkDelegate.blobInterceptJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(blobScript)
        config.userContentController.add(linkDelegate, name: "blobDownload")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.uiDelegate = linkDelegate
        wv.navigationDelegate = linkDelegate
        wv.load(URLRequest(url: service.url))
        webViews[service.id] = wv
        applyFont(to: wv)
        return wv
    }

    private let linkDelegate = WebViewLinkDelegate()

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

// MARK: - Save Panel Helper

enum DownloadHelper {
    @MainActor
    static func promptSave(suggestedName: String) async -> URL? {
        let name = suggestedName.isEmpty ? "download" : suggestedName
        let panel = NSSavePanel()
        panel.nameFieldStringValue = addExtensionIfNeeded(name: name)
        panel.canCreateDirectories = true
        let result = await panel.begin()
        return result == .OK ? panel.url : nil
    }

    @MainActor
    static func promptSaveAndWrite(suggestedName: String, data: Data) async {
        guard let url = await promptSave(suggestedName: suggestedName) else { return }
        try? data.write(to: url)
    }

    static func addExtensionIfNeeded(name: String, mime: String = "") -> String {
        if name.contains(".") { return name }
        let ext: String? = switch mime {
        case let m where m.contains("pdf"):  "pdf"
        case let m where m.contains("png"):  "png"
        case let m where m.contains("jpeg"): "jpg"
        case let m where m.contains("jpg"):  "jpg"
        case let m where m.contains("gif"):  "gif"
        case let m where m.contains("webp"): "webp"
        case let m where m.contains("zip"):  "zip"
        case let m where m.contains("mp4"):  "mp4"
        case let m where m.contains("webm"): "webm"
        case let m where m.contains("mp3"):  "mp3"
        case let m where m.contains("wav"):  "wav"
        case let m where m.contains("ogg"):  "ogg"
        case let m where m.contains("svg"):  "svg"
        case let m where m.contains("json"): "json"
        case let m where m.contains("html"): "html"
        case let m where m.contains("text"): "txt"
        default: nil
        }
        if let ext { return "\(name).\(ext)" }
        return name
    }
}

// MARK: - WebView Delegate (Navigation + UI + Downloads + Blob)

final class WebViewLinkDelegate: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler {

    // MARK: JS for blob URL interception

    static let blobInterceptJS = """
    (function() {
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a[href^="blob:"]');
            if (!a) return;
            e.preventDefault();
            e.stopPropagation();
            var filename = a.download || 'download';
            fetch(a.href).then(function(r) { return r.blob(); }).then(function(blob) {
                var reader = new FileReader();
                reader.onloadend = function() {
                    var base64 = reader.result.split(',')[1] || '';
                    window.webkit.messageHandlers.blobDownload.postMessage({
                        filename: filename, base64: base64, mime: blob.type || ''
                    });
                };
                reader.readAsDataURL(blob);
            }).catch(function(err) { console.error('WebMux blob download failed:', err); });
        }, true);

        var _open = window.open;
        window.open = function(url) {
            if (typeof url === 'string' && url.startsWith('blob:')) {
                fetch(url).then(function(r) { return r.blob(); }).then(function(blob) {
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = reader.result.split(',')[1] || '';
                        window.webkit.messageHandlers.blobDownload.postMessage({
                            filename: 'download', base64: base64, mime: blob.type || ''
                        });
                    };
                    reader.readAsDataURL(blob);
                });
                return null;
            }
            return _open.apply(this, arguments);
        };
    })();
    """

    // MARK: WKScriptMessageHandler — blob downloads

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "blobDownload",
              let body = message.body as? [String: String],
              let base64 = body["base64"],
              let data = Data(base64Encoded: base64) else { return }
        let filename = DownloadHelper.addExtensionIfNeeded(
            name: body["filename"] ?? "download",
            mime: body["mime"] ?? ""
        )
        Task { @MainActor in
            await DownloadHelper.promptSaveAndWrite(suggestedName: filename, data: data)
        }
    }

    // MARK: WKUIDelegate — window.open / target="_blank"

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.shouldPerformDownload, let url = navigationAction.request.url {
            Task { @MainActor in
                let download = await webView.startDownload(using: URLRequest(url: url))
                download.delegate = self
            }
            return nil
        }
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences)
            return
        }

        let host = url.host ?? ""

        guard let currentHost = webView.url?.host else {
            decisionHandler(.allow, preferences)
            return
        }

        if navigationAction.targetFrame != nil,
           (host == currentHost || host.hasSuffix(".\(currentHost)") || currentHost.hasSuffix(".\(host)")) {
            decisionHandler(.allow, preferences)
            return
        }

        if navigationAction.navigationType == .linkActivated, host != currentHost {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel, preferences)
            return
        }

        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        await DownloadHelper.promptSave(suggestedName: suggestedFilename)
    }

    func downloadDidFinish(_ download: WKDownload) {}

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {}
}
