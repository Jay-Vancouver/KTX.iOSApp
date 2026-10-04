import CoreLocation
import UIKit

extension Notification.Name {
    /// Tracking or location permission may have changed (the web page gets a "ktxappstatus" event).
    static let trackingStatusChanged = Notification.Name("KTXTrackingStatusChanged")
}

/// Sends the phone's position while the driver carries a load: a fix every `interval`, and at least
/// one report every `heartbeat` even when no new fix arrives (so the server can tell "parked" from
/// "phone off"). The iOS counterpart of the Android LocationService. Main thread only.
final class LocationTracker: NSObject {

    static let shared = LocationTracker()

    /// Heartbeat check; the shortest heartbeat allowed is 60 s.
    private static let checkSeconds: TimeInterval = 30
    private static let mpsToKnots = 1.943844

    private let manager = CLLocationManager()
    private var state: TrackingState { TrackingState() }

    private(set) var isRunning = false
    private var checkTimer: Timer?     // every checkSeconds: heartbeat check + retry of failed sends
    private var heartbeatTimer: Timer? // one-shot, due `heartbeat` after the last report
    private var backgroundSession: AnyObject? // CLBackgroundActivitySession on iOS 17+

    private var lastFix: CLLocation?
    private var lastQueuedAt: UInt64? // monotonic ns of the last queued report (counts while asleep)

    private override init() {
        super.init()
        // Created at launch so a relaunch for a location event (app killed, phone rebooted) is delivered.
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: Permission

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    var hasLocationPermission: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    var isPreciseLocation: Bool { manager.accuracyAuthorization == .fullAccuracy }

    /// "always" | "whileInUse" | "denied" for status(). Approximate location reports "whileInUse"
    /// so the page keeps showing its permission button.
    var permissionLevel: String {
        switch authorization {
        case .authorizedAlways: return isPreciseLocation ? "always" : "whileInUse"
        case .authorizedWhenInUse: return "whileInUse"
        default: return "denied"
        }
    }

    /// System prompts; the order, disclosure and Settings fallback live in PermissionFlow.
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }

    // MARK: Start / stop

    /// Saves the settings as tracking-on and starts if location is allowed (otherwise it starts as
    /// soon as it is). False when phone or url is unusable.
    @discardableResult
    func start(phone: String?, url: String?, cadence: TrackingState.Cadence = .default) -> Bool {
        guard let digits = TrackingState.normalizePhone(phone), TrackingState.isUsableURL(url),
              let url = url?.trimmingCharacters(in: .whitespaces) else { return false }
        let s = state
        s.phone = digits
        s.url = url
        s.intervalSec = cadence.intervalSec
        s.heartbeatSec = cadence.heartbeatSec
        s.tracking = true
        resumeIfTracking()
        NotificationCenter.default.post(name: .trackingStatusChanged, object: nil)
        return true
    }

    func stop() {
        state.tracking = false
        stopUpdates()
        manager.stopMonitoringSignificantLocationChanges()
        FixUploader.shared.flush() // deliver whatever is still queued
        NotificationCenter.default.post(name: .trackingStatusChanged, object: nil)
    }

    /// At launch (including a relaunch by a location event), when the app returns to the foreground
    /// and when permission is granted: start if tracking is on and location is allowed.
    func resumeIfTracking() {
        let s = state
        if !s.tracking {
            // Monitoring survives app restarts; never leave it on (and relaunching the app) when stopped.
            manager.stopMonitoringSignificantLocationChanges()
            return
        }
        guard s.phone != nil, s.url != nil, hasLocationPermission else { return }
        if !isRunning { startUpdates() }
    }

    private func startUpdates() {
        isRunning = true
        lastFix = nil
        lastQueuedAt = nil
        UIDevice.current.isBatteryMonitoringEnabled = true

        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true // blue status bar pill while in the background
        manager.startUpdatingLocation()
        // Relaunches the app after it was terminated or the phone rebooted, while tracking is on.
        manager.startMonitoringSignificantLocationChanges()
        if #available(iOS 17.0, *) {
            backgroundSession = CLBackgroundActivitySession()
        }

        checkTimer?.invalidate()
        let timer = Timer(timeInterval: Self.checkSeconds, repeats: true) { [weak self] _ in
            self?.checkHeartbeat(retryFailedSends: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        NSLog("LocationTracker: started (interval %ds, heartbeat %ds)", state.intervalSec, state.heartbeatSec)
    }

    private func stopUpdates() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        checkTimer?.invalidate()
        checkTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if #available(iOS 17.0, *) {
            (backgroundSession as? CLBackgroundActivitySession)?.invalidate()
        }
        backgroundSession = nil
        NSLog("LocationTracker: stopped")
    }

    // MARK: Reports

    private static func monotonicNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

    private func secondsSinceLastQueued() -> Double? {
        lastQueuedAt.map { Double(Self.monotonicNow() &- $0) / 1_000_000_000 }
    }

    private func onFix(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return } // invalid fix
        // iOS reports about once a second; keep one report per interval (5/6 allows for jitter).
        let interval = Double(state.intervalSec)
        if let since = secondsSinceLastQueued(), since < interval * 5 / 6 {
            lastFix = location // newest position, for the heartbeat
            checkHeartbeat(retryFailedSends: false) // fixes arrive every second; retries wait for the timer
            return
        }
        lastFix = location
        queue(location, at: location.timestamp)
    }

    /// Re-sends the last position with the current time when nothing went out for `heartbeat`.
    /// Called from the timer and the location callback (a background timer may not fire).
    /// The timer also retries a failed send (new fixes and a restored network retry as well).
    private func checkHeartbeat(retryFailedSends: Bool) {
        if isRunning, let fix = lastFix, let since = secondsSinceLastQueued(), since >= Double(state.heartbeatSec) {
            queue(fix, at: Date())
        } else if retryFailedSends {
            FixUploader.shared.flush()
        }
    }

    private func scheduleHeartbeat(after seconds: TimeInterval) {
        heartbeatTimer?.invalidate()
        // A little late rather than early, so the elapsed-time check in checkHeartbeat passes.
        let timer = Timer(timeInterval: seconds + 0.5, repeats: false) { [weak self] _ in
            self?.checkHeartbeat(retryFailedSends: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func queue(_ location: CLLocation, at time: Date) {
        let s = state
        guard let phone = s.phone, let url = s.url else { return }
        lastQueuedAt = Self.monotonicNow()
        scheduleHeartbeat(after: TimeInterval(s.heartbeatSec))
        FixUploader.shared.enqueue(url: url, body: Self.osmAndBody(phone: phone, location: location, time: time))
    }

    /// OsmAnd form fields, the same as the Android app sends. Numbers always use "." decimals.
    static func osmAndBody(phone: String, location: CLLocation, time: Date) -> String {
        var items = [
            URLQueryItem(name: "id", value: phone),
            URLQueryItem(name: "lat", value: fmt(location.coordinate.latitude, 6)),
            URLQueryItem(name: "lon", value: fmt(location.coordinate.longitude, 6)),
            URLQueryItem(name: "timestamp", value: String(Int64(time.timeIntervalSince1970))),
            URLQueryItem(name: "speed", value: fmt(max(location.speed, 0) * mpsToKnots, 1)),
            URLQueryItem(name: "bearing", value: fmt(max(location.course, 0), 1)),
            URLQueryItem(name: "altitude", value: fmt(location.altitude, 1)),
            URLQueryItem(name: "accuracy", value: fmt(location.horizontalAccuracy, 1)),
        ]
        if let batt = batteryPercent() { items.append(URLQueryItem(name: "batt", value: String(batt))) }
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }

    private static func batteryPercent() -> Int? {
        let level = UIDevice.current.batteryLevel // -1 when unknown (simulator, monitoring off)
        return level >= 0 ? Int((level * 100).rounded()) : nil
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func fmt(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: posix, value)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning else { return } // significant-change events while stopped
        for location in locations { onFix(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return } // transient; updates continue
        NSLog("LocationTracker: %@", error.localizedDescription)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if hasLocationPermission {
            resumeIfTracking()
        } else {
            stopUpdates() // tracking stays on and resumes once location is allowed again
        }
        NotificationCenter.default.post(name: .locationAuthorizationChanged, object: nil)
        NotificationCenter.default.post(name: .trackingStatusChanged, object: nil)
    }
}
