import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Also runs when iOS relaunches the app in the background for a location event
        // (launchOptions[.location]) after it was terminated or the phone rebooted: creating the
        // tracker re-attaches the location manager, and tracking resumes if it was on.
        if launchOptions?[.location] != nil {
            NSLog("AppDelegate: relaunched for a location event")
        }
        LocationTracker.shared.resumeIfTracking()
        FixUploader.shared.flush() // positions left over from before the app was stopped
        DebugCommands.runLaunchArguments()
        return true
    }
}

/// Debug builds only: start and stop tracking without the web page / bridge.
///
///     xcrun simctl launch --terminate-running-process booted com.ktxtransport.driver \
///         -debugTracking start -debugPhone 6045551234 -debugURL http://127.0.0.1:8099/gps \
///         -debugOptions '{"interval":10,"heartbeat":60}'
///     xcrun simctl launch --terminate-running-process booted com.ktxtransport.driver -debugTracking stop
///     xcrun simctl launch --terminate-running-process booted com.ktxtransport.driver \
///         -debugOpenURL https://www.withktx.com/driver/s/<token>    # SMS login link without Universal Links
///
/// On a device: `xcrun devicectl device process launch --device <id> com.ktxtransport.driver -debugTracking start ...`.
/// Arguments are read raw (UserDefaults would parse the JSON options as a property list).
enum DebugCommands {
    @MainActor
    static func runLaunchArguments() {
        #if DEBUG
        if let url = argument("-debugOpenURL").flatMap(URL.init(string:)) {
            NSLog("DebugCommands: open %@ -> %@", url.absoluteString, LinkRouter.shared.open(url) ? "true" : "false")
        }
        switch argument("-debugTracking") {
        case "start":
            guard let cadence = TrackingState.parseCadence(argument("-debugOptions")) else {
                NSLog("DebugCommands: -debugOptions is not valid JSON")
                return
            }
            let ok = LocationTracker.shared.start(phone: argument("-debugPhone"),
                                                  url: argument("-debugURL"), cadence: cadence)
            NSLog("DebugCommands: start tracking -> %@", ok ? "true" : "false")
            if ok && !LocationTracker.shared.hasLocationPermission { PermissionFlow.shared.start() }
        case "stop":
            LocationTracker.shared.stop()
            NSLog("DebugCommands: stop tracking")
        default:
            break
        }
        #endif
    }

    /// The value after `name` on the command line.
    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
