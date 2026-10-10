import SwiftUI
import WebKit
import os

@MainActor @Observable
final class WebViewManager {
    private static let logger = Logger(subsystem: "com.webmux.app", category: "WebViewManager")
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

        let wv = WKWebView(frame: CGRect(origin: .zero, size: contentSize), configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.uiDelegate = linkDelegate
        wv.navigationDelegate = linkDelegate
        wv.load(URLRequest(url: service.url))
        webViews[service.id] = wv
        pendingLoads.insert(ObjectIdentifier(wv))
        applyFont(to: wv)
        return wv
    }

    private let linkDelegate = WebViewLinkDelegate()

    /// Size of the web content area, kept up to date by ContentView. New web views
    /// (especially preloaded ones, which load before they're on screen) start at this
    /// size so pages never lay out against a 0×0 viewport.
    @ObservationIgnored var contentSize = CGSize(width: 948, height: 700)

    init() {
        linkDelegate.onLoadFinished = { [weak self] wv in self?.loadFinished(wv) }
    }

    // MARK: Staggered preload

    /// Web views whose initial page load hasn't finished or failed yet.
    @ObservationIgnored private var pendingLoads: Set<ObjectIdentifier> = []
    @ObservationIgnored private var loadWaiters: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    /// Creates web views for `services` one at a time, starting the next only after
    /// the previous one finishes loading (or `timeout` passes), to avoid a launch storm.
    func preload(_ services: [Service], timeout: Duration = .seconds(15)) async {
        for service in services {
            guard !Task.isCancelled else { return }
            let start = ContinuousClock.now
            let wv = webView(for: service)
            await waitForInitialLoad(of: wv, timeout: timeout)
            Self.logger.info("Preloaded \(service.name, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
        }
    }

    private func waitForInitialLoad(of wv: WKWebView, timeout: Duration) async {
        let key = ObjectIdentifier(wv)
        guard pendingLoads.contains(key) else { return }
        await withCheckedContinuation { continuation in
            loadWaiters[key] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resumeWaiter(for: key)
            }
        }
    }

    private func loadFinished(_ wv: WKWebView) {
        let key = ObjectIdentifier(wv)
        pendingLoads.remove(key)
        resumeWaiter(for: key)
    }

    private func resumeWaiter(for key: ObjectIdentifier) {
        loadWaiters.removeValue(forKey: key)?.resume()
    }

    func removeWebView(for id: UUID) {
        if let wv = webViews.removeValue(forKey: id) {
            wv.stopLoading()
            // The content controller retains its message handlers; drop them with the view.
            wv.configuration.userContentController.removeAllScriptMessageHandlers()
            loadFinished(wv)  // don't leave a preload waiting on a removed view
        }
    }

    /// Throws away the service's web view (and its web content process) and loads the
    /// service's home URL in a brand-new one — the same as quitting and relaunching,
    /// for a single service. Cookies and storage are kept, so the user stays logged in.
    func refresh(_ service: Service) {
        if let old = webViews[service.id] {
            old.stopLoading()
            removeWebView(for: service.id)
        }
        _ = webView(for: service)
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

// MARK: - Camera / microphone decisions

/// Per-site camera/microphone choices the user asked to remember, stored in UserDefaults
/// as "<scheme>://<host>:<port>|<device>" → granted.
@MainActor
enum MediaPermissions {
    enum Device: String { case camera, microphone }

    private static let defaultsKey = "mediaPermissions"

    static func devices(for type: WKMediaCaptureType) -> [Device] {
        switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: [.camera, .microphone]
        }
    }

    /// The remembered decision if every requested device has one and they agree; otherwise nil (ask).
    static func decision(for origin: WKSecurityOrigin, devices: [Device]) -> Bool? {
        let saved = stored()
        let values = devices.map { saved[key(origin, $0)] }
        guard let first = values.first ?? nil, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    static func remember(_ granted: Bool, for origin: WKSecurityOrigin, devices: [Device]) {
        var saved = stored()
        for device in devices { saved[key(origin, device)] = granted }
        UserDefaults.standard.set(saved, forKey: defaultsKey)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static var hasRememberedDecisions: Bool { !stored().isEmpty }

    private static func stored() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
    }

    private static func key(_ origin: WKSecurityOrigin, _ device: Device) -> String {
        "\(origin.protocol)://\(origin.host):\(origin.port)|\(device.rawValue)"
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

    // MARK: WKUIDelegate — <input type="file">

    // On macOS, WKWebView shows no file picker unless the UI delegate provides one.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            // nil tells WebKit the user cancelled, leaving the input unchanged.
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    // MARK: WKUIDelegate — JavaScript alert / confirm / prompt

    // Without these, WebKit behaves as if the user pressed Cancel: alert() is
    // dropped, confirm() returns false and prompt() returns null.

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = Self.makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        Self.present(alert, for: webView) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = Self.makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        Self.present(alert, for: webView) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = Self.makeAlert(message: prompt, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        Self.present(alert, for: webView) {
            completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    /// Titles the dialog with the requesting frame's host, like Safari does,
    /// so users can tell which site (or embedded iframe) is asking.
    private static func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says:" : "\(host) says:"
        alert.informativeText = message
        return alert
    }

    /// Shows the alert as a sheet. Only the selected service's web view is in a
    /// window, so a background service falls back to the app's main window.
    private static func present(_ alert: NSAlert, for webView: WKWebView,
                                completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window ?? NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { completion($0) }
        } else {
            completion(alert.runModal())
        }
    }

    // MARK: WKUIDelegate — camera / microphone

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        let devices = MediaPermissions.devices(for: type)
        if let remembered = MediaPermissions.decision(for: origin, devices: devices) {
            decisionHandler(remembered ? .grant : .deny)
            return
        }

        let alert = NSAlert()
        let site = origin.host.isEmpty ? "This page" : origin.host
        alert.messageText = "Allow \(site) to use your \(devices.map(\.rawValue).joined(separator: " and "))?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remember my choice for this site"
        Self.present(alert, for: webView) { response in
            let granted = response == .alertFirstButtonReturn
            if alert.suppressionButton?.state == .on {
                MediaPermissions.remember(granted, for: origin, devices: devices)
            }
            decisionHandler(granted ? .grant : .deny)
        }
    }

    // MARK: WKNavigationDelegate

    /// Called when a web view's navigation finishes or fails (used for staggered preload).
    var onLoadFinished: ((WKWebView) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFinished?(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadFinished?(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        onLoadFinished?(webView)
    }

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
