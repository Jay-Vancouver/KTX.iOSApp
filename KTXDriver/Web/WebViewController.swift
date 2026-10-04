import SwiftUI
import UIKit
import WebKit

/// The single screen: the TMS driver site in a WKWebView. Login, pickup, delivery, logs and
/// inspections are all handled by the page; the app only adds what a browser cannot do.
final class WebViewController: UIViewController {

    private(set) var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let errorView = ErrorView()
    private var progressObservation: NSKeyValueObservation?
    private var statusObserver: NSObjectProtocol?

    /// Site address the page was loaded from; a change in settings reloads the new one.
    private var loadedStartURL: URL?

    /// Left→right swipe across the top strip opens the settings screen.
    private let settingsSwipe = UIPanGestureRecognizer()
    private var settingsSwipeTriggered = false
    private static let swipeZoneHeight: CGFloat = 64 // top strip of the page that starts the swipe
    private static let swipeEdgeWidth: CGFloat = 20  // left edge belongs to the back gesture

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "KTXBlue") // shows behind the status bar

        webView = makeWebView()
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        progressView.progressTintColor = UIColor(red: 0xD7 / 255, green: 0x18 / 255, blue: 0x2A / 255, alpha: 1) // ktx_red
        progressView.trackTintColor = .clear
        progressView.isHidden = true
        view.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false

        errorView.isHidden = true
        errorView.onRetry = { [weak self] in self?.retry() }
        view.addSubview(errorView)
        errorView.translatesAutoresizingMaskIntoConstraints = false

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safe.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            progressView.topAnchor.constraint(equalTo: safe.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),

            errorView.topAnchor.constraint(equalTo: safe.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else { return }
            let progress = Float(webView.estimatedProgress)
            self.progressView.setProgress(progress, animated: progress > self.progressView.progress)
            self.progressView.isHidden = progress >= 1
        }

        let start = ServerConfig.startURL
        loadedStartURL = start
        webView.load(URLRequest(url: LinkRouter.shared.takePending() ?? start))
        LinkRouter.shared.handler = { [weak self] url in
            self?.errorView.isHidden = true
            self?.webView.load(URLRequest(url: url))
        }
        settingsSwipe.addTarget(self, action: #selector(handleSettingsSwipe(_:)))
        settingsSwipe.delegate = self
        settingsSwipe.cancelsTouchesInView = false // taps and scrolls there still reach the page
        webView.addGestureRecognizer(settingsSwipe)

        // Permission flow ended, tracking started/stopped, app back in the foreground.
        statusObserver = NotificationCenter.default.addObserver(
            forName: .trackingStatusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dispatchStatus()
        }
    }

    /// Tells the page that permissions or tracking may have changed: "ktxappstatus" on window and document.
    private func dispatchStatus() {
        guard let webView, WebHosts.isBridgeURL(webView.url) else { return }
        webView.evaluateJavaScript(KtxBridge.statusEventScript(), completionHandler: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadIfServerChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        // Screenshots / tests: open the settings screen right away.
        if ProcessInfo.processInfo.arguments.contains("-debugOpenSettings") { openSettings() }
        #endif
    }

    // MARK: Settings screen

    @objc private func handleSettingsSwipe(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed:
            let t = pan.translation(in: webView)
            if !settingsSwipeTriggered && t.x > webView.bounds.width / 4 && t.x > abs(t.y) * 2 {
                settingsSwipeTriggered = true
                openSettings()
            }
        case .ended, .cancelled, .failed:
            settingsSwipeTriggered = false
        default:
            break
        }
    }

    func openSettings() {
        guard presentedViewController == nil else { return }
        let settings = UIHostingController(rootView: SettingsView { [weak self] in
            self?.dismiss(animated: true) { self?.settingsClosed() }
        })
        settings.presentationController?.delegate = self
        present(settings, animated: true)
    }

    private func settingsClosed() {
        reloadIfServerChanged()
        dispatchStatus() // permissions may have been changed from there
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent cookies: the login lasts 6 months
        config.allowsInlineMediaPlayback = true // QR scan video stays in the page, not fullscreen
        config.mediaTypesRequiringUserActionForPlayback = []
        // Keep WebKit's default "Mobile/15E148" so the site still sees a mobile browser.
        config.applicationNameForUserAgent = "Mobile/15E148 \(AppInfo.userAgentToken)"
        config.userContentController.addUserScript(KtxBridge.userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .white
        if #available(iOS 16.4, *) {
            webView.isInspectable = AppInfo.isDebug // Safari Web Inspector in debug builds
        }
        return webView
    }

    /// Loads the new start page after the administrator changed the server address.
    func reloadIfServerChanged() {
        guard webView != nil, loadedStartURL != ServerConfig.startURL else { return }
        loadedStartURL = ServerConfig.startURL
        errorView.isHidden = true
        webView.load(URLRequest(url: ServerConfig.startURL))
    }

    private func retry() {
        errorView.isHidden = true
        if webView.url == nil {
            webView.load(URLRequest(url: ServerConfig.startURL))
        } else {
            webView.reload()
        }
    }

    private func showError() {
        errorView.isHidden = false
        progressView.isHidden = true
    }

    /// Hands a URL to the system: Safari for web pages, Phone/Messages/Mail for tel:/sms:/mailto:.
    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - Settings swipe and sheet

extension WebViewController: UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === settingsSwipe else { return true }
        let p = gestureRecognizer.location(in: webView)
        return p.y <= Self.swipeZoneHeight && p.x > Self.swipeEdgeWidth
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === settingsSwipe
    }

    /// Settings closed by swiping the sheet down.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        settingsClosed()
    }
}

// MARK: - Navigation

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        let scheme = url.scheme?.lowercased() ?? ""

        // Embedded frames (maps, captchas) load as they are; only top-level navigations are routed.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame || ["about", "blob", "data"].contains(scheme) {
            return decisionHandler(.allow)
        }
        switch scheme {
        case "https", "http":
            if WebHosts.isAppURL(url) && !navigationAction.shouldPerformDownload {
                decisionHandler(.allow)
            } else { // other sites and <a download> links
                decisionHandler(.cancel)
                openExternal(url)
            }
        default: // tel:, sms:, mailto:, maps:, itms-apps:
            decisionHandler(.cancel)
            openExternal(url)
        }
    }

    /// Files the web view cannot show (or that the server marks as attachments) go to Safari.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let isDownload = !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment")
        if navigationResponse.isForMainFrame, isDownload, let url = navigationResponse.response.url {
            decisionHandler(.cancel)
            openExternal(url)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        errorView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if Self.isLoadFailure(error) { showError() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if Self.isLoadFailure(error) { showError() }
    }

    /// The web content process crashed or was killed for memory; start the page again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView.url == nil {
            webView.load(URLRequest(url: ServerConfig.startURL))
        } else {
            webView.reload()
        }
    }

    /// A real network failure, not a navigation we cancelled ourselves (link sent to Safari, new load).
    private static func isLoadFailure(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return false }
        // WebKitErrorFrameLoadInterruptedByPolicyChange = 102, plugin handled load = 204.
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204) { return false }
        return true
    }
}

// MARK: - UI (camera, new windows, JavaScript dialogs)

extension WebViewController: WKUIDelegate {

    /// Camera for pickup QR scan / inspection photos (getUserMedia), only for our own site.
    /// Microphone is never granted.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = type == .camera && WebHosts.isAppHost(origin.host) &&
            (origin.protocol == "https" || AppInfo.isDebug)
        decisionHandler(allowed ? .grant : .deny)
    }

    /// target="_blank" and window.open: our pages load in place, others go to Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if WebHosts.isAppURL(url) {
                webView.load(navigationAction.request)
            } else if url.scheme != "about" {
                openExternal(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "ok"), style: .default) { _ in completionHandler() })
        presentDialog(alert) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: String(localized: "ok"), style: .default) { _ in completionHandler(true) })
        presentDialog(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        // window.KtxAndroidApp calls: answered at once, never shown.
        if KtxBridge.isBridgeCall(prompt) {
            let allowed = frame.isMainFrame && WebHosts.isBridgeURL(webView.url)
            return completionHandler(KtxBridge.handle(prompt: prompt, allowed: allowed))
        }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: String(localized: "ok"), style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        presentDialog(alert) { completionHandler(nil) }
    }

    /// WebKit requires every dialog's completion handler to be called, even when it cannot be shown.
    private func presentDialog(_ alert: UIAlertController, otherwise fallback: @escaping () -> Void) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return fallback() }
        present(alert, animated: true)
    }
}
