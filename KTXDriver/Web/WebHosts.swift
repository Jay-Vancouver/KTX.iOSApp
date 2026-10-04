import Foundation

/// Which hosts the app treats as its own; everything else opens in Safari.
/// Besides withktx.com this follows the driver site address in ServerConfig, so an address set by
/// the administrator keeps working (in-app navigation, bridge, tracking URL). Mirrors Android's WebHosts.
enum WebHosts {

    private static var defaultStartHost: String? { ServerConfig.defaultStartURL.host?.lowercased() }
    private static var startHost: String? { ServerConfig.startURL.host?.lowercased() }

    /// withktx.com and its subdomains (driver., pod., www.), plus the built-in and the configured start host.
    static func isAppHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return h == "withktx.com" || h.hasSuffix(".withktx.com") || h == defaultStartHost || h == startHost
    }

    static func isAppURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return isPageScheme(url.scheme) && isAppHost(url.host)
    }

    /// Pages allowed to use the KtxAndroidApp bridge: the driver site only.
    /// driver.withktx.com redirects to www.withktx.com/driver/, so both count; a configured start
    /// address counts on its own host under its own path (e.g. /driver/).
    static func isBridgeURL(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        let scheme = url.scheme?.lowercased()
        let path = pathOf(url)
        if scheme == "https" &&
            (host == "driver.withktx.com" || (host == "www.withktx.com" && underPath(path, "/driver"))) {
            return true
        }
        guard let start = ServerConfig.startURLOverride, isPageScheme(scheme) else { return false }
        var prefix = pathOf(start)
        while prefix.hasSuffix("/") { prefix.removeLast() }
        return host == start.host?.lowercased() && url.port == start.port && underPath(path, prefix)
    }

    /// Hosts a tracking URL may point at: our hosts, or another host in the configured site's domain
    /// (the site moved to example.com → gps.example.com is fine).
    static func isTrackingHost(_ host: String?) -> Bool {
        if isAppHost(host) { return true }
        guard let h = host?.lowercased(), let domain = siteDomain(startHost) else { return false }
        return h == domain || h.hasSuffix(".\(domain)")
    }

    /// "tms.ktxtransport.com" → "ktxtransport.com"; nil for IP addresses and single labels.
    static func siteDomain(_ host: String?) -> String? {
        guard let host, !host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) else { return nil }
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : nil
    }

    /// Path as written (URL.path drops a trailing slash, which matters for "/driver/").
    private static func pathOf(_ url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path
    }

    private static func underPath(_ path: String, _ prefix: String) -> Bool {
        prefix.isEmpty || path == prefix || path.hasPrefix(prefix + "/")
    }

    private static func isPageScheme(_ scheme: String?) -> Bool {
        let s = scheme?.lowercased()
        return s == "https" || (AppInfo.isDebug && s == "http")
    }
}
