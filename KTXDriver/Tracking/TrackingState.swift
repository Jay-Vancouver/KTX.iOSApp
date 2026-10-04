import Foundation

/// Tracking settings and progress, kept in UserDefaults so they survive relaunches and reboots.
/// Mirrors the Android app's TrackingState (same keys, defaults and validation rules).
struct TrackingState {

    private var defaults: UserDefaults { .standard }

    /// Whether the web page asked for tracking (startTracking) and has not stopped it since.
    var tracking: Bool {
        get { defaults.bool(forKey: Keys.tracking) }
        nonmutating set { defaults.set(newValue, forKey: Keys.tracking) }
    }

    /// Driver phone, 10 digits: the `id` field the server matches pickups by.
    var phone: String? {
        get { defaults.string(forKey: Keys.phone) }
        nonmutating set { defaults.set(newValue, forKey: Keys.phone) }
    }

    /// Where positions are posted; given by the web page, never hard-coded.
    var url: String? {
        get { defaults.string(forKey: Keys.url) }
        nonmutating set { defaults.set(newValue, forKey: Keys.url) }
    }

    /// Seconds between reports while tracking.
    var intervalSec: Int {
        get { (defaults.object(forKey: Keys.interval) as? Int) ?? Self.defaultIntervalSec }
        nonmutating set { defaults.set(newValue, forKey: Keys.interval) }
    }

    /// At least one report this often (seconds) even when no new fix arrives.
    var heartbeatSec: Int {
        get { (defaults.object(forKey: Keys.heartbeat) as? Int) ?? Self.defaultHeartbeatSec }
        nonmutating set { defaults.set(newValue, forKey: Keys.heartbeat) }
    }

    /// Wall-clock time (epoch ms) the server last accepted a position; 0 = never.
    var lastSentAt: Int64 {
        get { (defaults.object(forKey: Keys.lastSent) as? NSNumber)?.int64Value ?? 0 }
        nonmutating set { defaults.set(NSNumber(value: newValue), forKey: Keys.lastSent) }
    }

    /// Last failed send ("HTTP 503", "timed out", "stuck 60s, cancelled"); nil after a success.
    var lastSendError: String? { defaults.string(forKey: Keys.lastError) }

    /// Wall-clock time (epoch ms) of `lastSendError`; 0 = none.
    var lastSendErrorAt: Int64 { (defaults.object(forKey: Keys.lastErrorAt) as? NSNumber)?.int64Value ?? 0 }

    func recordSendError(_ error: String?) {
        if let error {
            defaults.set(String(error.prefix(200)), forKey: Keys.lastError)
            defaults.set(NSNumber(value: Self.nowMs()), forKey: Keys.lastErrorAt)
        } else if defaults.object(forKey: Keys.lastError) != nil {
            defaults.removeObject(forKey: Keys.lastError)
            defaults.removeObject(forKey: Keys.lastErrorAt)
        }
    }

    /// Report cadence set by the web page through startTracking's options.
    struct Cadence: Equatable {
        var intervalSec: Int
        var heartbeatSec: Int
        static let `default` = Cadence(intervalSec: defaultIntervalSec, heartbeatSec: defaultHeartbeatSec)
    }

    private enum Keys {
        static let tracking = "tracking"
        static let phone = "phone"
        static let url = "url"
        static let lastSent = "last_sent_at"
        static let interval = "interval_sec"
        static let heartbeat = "heartbeat_sec"
        static let lastError = "last_send_error"
        static let lastErrorAt = "last_send_error_at"
    }

    // Defaults match the Traccar Client setup (interval=60, heartbeat=300).
    static let defaultIntervalSec = 60
    static let defaultHeartbeatSec = 300
    private static let intervalRange = 10...600
    private static let heartbeatRange = 60...3600

    static func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    /// startTracking options, a JSON string such as `{"interval":30,"heartbeat":300}` (seconds).
    /// nil/blank/"undefined"/"null" → defaults; a missing or non-numeric key → its default;
    /// out of range → clamped; heartbeat is never shorter than interval. nil result = not valid JSON.
    static func parseCadence(_ options: String?) -> Cadence? {
        let text = options?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text == "undefined" || text == "null" { return .default }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let interval = clamp(intValue(json["interval"]) ?? defaultIntervalSec, intervalRange)
        let heartbeat = clamp(intValue(json["heartbeat"]) ?? defaultHeartbeatSec, heartbeatRange)
        return Cadence(intervalSec: interval, heartbeatSec: max(heartbeat, interval))
    }

    /// Numbers and numeric strings, like Android's JSONObject.optInt.
    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber where !(n === kCFBooleanTrue || n === kCFBooleanFalse):
            return n.doubleValue.isFinite ? Int(clamping: Int64(n.doubleValue)) : nil
        case let s as String:
            return Double(s.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? Int(clamping: Int64($0)) : nil }
        default:
            return nil
        }
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// "(604) 555-1234", "+1 604 555 1234" → "6045551234"; nil unless it is 10 digits.
    static func normalizePhone(_ raw: String?) -> String? {
        var digits = (raw ?? "").filter { $0.isASCII && $0.isNumber }
        if digits.count == 11 && digits.hasPrefix("1") { digits.removeFirst() }
        return digits.count == 10 ? digits : nil
    }

    /// https on a withktx.com host (www.withktx.com/gps today) or in the domain of an
    /// administrator-set site address (WebHosts.isTrackingHost).
    /// Debug builds also accept http://127.0.0.1 / localhost for a local test receiver.
    static func isUsableURL(_ string: String?) -> Bool {
        guard let url = URL(string: (string ?? "").trimmingCharacters(in: .whitespaces)) else { return false }
        let host = url.host?.lowercased()
        switch url.scheme?.lowercased() {
        case "https": return WebHosts.isTrackingHost(host)
        case "http": return AppInfo.isDebug && (host == "127.0.0.1" || host == "localhost")
        default: return false
        }
    }
}
