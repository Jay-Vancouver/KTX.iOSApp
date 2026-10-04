import Foundation

/// The driver site address. Normally the built-in default; an administrator can override it in the
/// settings screen (behind the admin PIN) when that server cannot be reached. The tracking URL still
/// comes from startTracking. Mirrors the Android app's ServerConfig.
enum ServerConfig {

    private static let keyStartURL = "start_url"
    private static var defaults: UserDefaults { .standard }

    static let defaultStartURL = URL(string: "https://driver.withktx.com/")!

    /// Administrator's address, or nil for the built-in one.
    static var startURLOverride: URL? {
        get { defaults.string(forKey: keyStartURL).flatMap(URL.init(string:)) }
        set {
            if let value = newValue?.absoluteString.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                defaults.set(value, forKey: keyStartURL)
            } else {
                defaults.removeObject(forKey: keyStartURL)
            }
        }
    }

    static var startURL: URL { startURLOverride ?? defaultStartURL }

    /// https with a host; debug builds also accept http (local test servers).
    static func isValidStartURL(_ string: String?) -> Bool {
        guard let url = URL(string: (string ?? "").trimmingCharacters(in: .whitespaces)),
              let host = url.host, !host.isEmpty else { return false }
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || (AppInfo.isDebug && scheme == "http")
    }

    /// "https://host[:port]" of `url`.
    static func origin(_ url: URL) -> String {
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(url.scheme ?? "https")://\(url.host ?? "")\(port)"
    }
}
