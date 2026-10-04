import CoreLocation
import UIKit

/// Walks the driver through what tracking needs: the in-app location disclosure, then location
/// "while using", then "always", then precise location. A step already granted is skipped; a
/// refusal moves on. When iOS will no longer ask (denied, or "always" was asked before), it explains
/// and opens this app's page in Settings. Ends with a status event for the page.
/// The iOS counterpart of the Android PermissionFlow. Main thread only.
final class PermissionFlow {

    static let shared = PermissionFlow()

    private enum Step: Hashable { case disclosure, whenInUse, always, settings, precise }

    /// iOS shows the "Change to Always Allow" prompt only once per install.
    private static let keyAlwaysRequested = "always_location_requested"

    private var running = false
    private var asked: Set<Step> = []
    private var disclosureAccepted = false
    private var waitToken = 0 // identifies the system prompt or Settings visit being waited for
    private var observers: [NSObjectProtocol] = []

    private var tracker: LocationTracker { .shared }

    func start() {
        guard !running else { return }
        running = true
        asked = []
        disclosureAccepted = false
        next()
    }

    private func next() {
        let status = tracker.authorization
        let needsLocation = status == .notDetermined
        let needsAlways = status == .authorizedWhenInUse
        let alwaysAskedBefore = UserDefaults.standard.bool(forKey: Self.keyAlwaysRequested)

        // The disclosure comes first, once per run, whenever a system location prompt is about to appear.
        if !disclosureAccepted && !asked.contains(.disclosure) &&
            (needsLocation || (needsAlways && !alwaysAskedBefore)) {
            asked.insert(.disclosure)
            return showDisclosure()
        }
        if needsLocation && disclosureAccepted && !asked.contains(.whenInUse) {
            asked.insert(.whenInUse)
            waitForAnswer()
            return tracker.requestWhenInUse()
        }
        if needsAlways && disclosureAccepted && !alwaysAskedBefore && !asked.contains(.always) {
            asked.insert(.always)
            UserDefaults.standard.set(true, forKey: Self.keyAlwaysRequested)
            waitForAnswer()
            return tracker.requestAlways()
        }
        // iOS will not ask again: denied, restricted, or "always" already asked once.
        if (status == .denied || status == .restricted || (needsAlways && alwaysAskedBefore)) &&
            !asked.contains(.settings) && !asked.contains(.whenInUse) && !asked.contains(.always) {
            asked.insert(.settings)
            return showSettingsGuide(message: String(localized: "permission_settings_always"))
        }
        if tracker.hasLocationPermission && !tracker.isPreciseLocation && !asked.contains(.precise) {
            asked.insert(.precise)
            return showSettingsGuide(message: String(localized: "permission_settings_precise"))
        }
        finish()
    }

    private func finish() {
        running = false
        tracker.resumeIfTracking()
        NotificationCenter.default.post(name: .trackingStatusChanged, object: nil)
    }

    // MARK: Waiting for the system prompt / Settings

    /// Moves on when the permission changes, or when the app is active again without a change
    /// (the driver kept the current setting, or came back from Settings).
    private func waitForAnswer() {
        waitToken += 1
        let token = waitToken
        let center = NotificationCenter.default
        removeObservers()
        observers.append(center.addObserver(forName: .locationAuthorizationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.resume(token)
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // The authorization callback can arrive just after the app becomes active.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.resume(token) }
        })
    }

    private func resume(_ token: Int) {
        guard running, token == waitToken else { return }
        waitToken += 1
        removeObservers()
        next()
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    // MARK: Dialogs

    private func showDisclosure() {
        let alert = UIAlertController(title: String(localized: "disclosure_title"),
                                      message: String(localized: "disclosure_message"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "disclosure_decline"), style: .cancel) { [weak self] _ in
            self?.next() // declined: no location prompts in this run
        })
        alert.addAction(UIAlertAction(title: String(localized: "disclosure_accept"), style: .default) { [weak self] _ in
            self?.disclosureAccepted = true
            self?.next()
        })
        present(alert)
    }

    private func showSettingsGuide(message: String) {
        let alert = UIAlertController(title: String(localized: "permission_settings_title"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "later"), style: .cancel) { [weak self] _ in
            self?.next()
        })
        alert.addAction(UIAlertAction(title: String(localized: "open_settings"), style: .default) { [weak self] _ in
            guard let self, let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.waitForAnswer()
            UIApplication.shared.open(url) { opened in if !opened { self.next() } }
        })
        present(alert)
    }

    private func present(_ alert: UIAlertController) {
        guard let top = UIApplication.shared.topViewController else { return finish() }
        top.present(alert, animated: true)
    }
}

extension Notification.Name {
    /// CLLocationManager reported a permission change (posted by LocationTracker).
    static let locationAuthorizationChanged = Notification.Name("KTXLocationAuthorizationChanged")
}

extension UIApplication {
    /// The view controller on top of the key window, to present dialogs from anywhere.
    var topViewController: UIViewController? {
        let window = connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
