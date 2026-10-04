import Foundation

/// Hands URLs that open the app (Universal Links such as the SMS login link) to the web screen,
/// holding one until the screen exists (cold start).
@MainActor
final class LinkRouter {
    static let shared = LinkRouter()

    private var pending: URL?

    var handler: ((URL) -> Void)? {
        didSet {
            if let handler, let url = pending {
                pending = nil
                handler(url)
            }
        }
    }

    /// Accepts only links to our own site; returns whether the URL was taken.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard WebHosts.isAppURL(url) else { return false }
        if let handler { handler(url) } else { pending = url }
        return true
    }

    func takePending() -> URL? {
        defer { pending = nil }
        return pending
    }
}
