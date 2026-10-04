import Foundation

enum AppInfo {
    /// CFBundleShortVersionString, e.g. "1.0.0".
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Marker the server looks for in the User-Agent to tell the app from a browser (same as Android).
    static var userAgentToken: String { "KTXDriverApp/\(version)" }

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
