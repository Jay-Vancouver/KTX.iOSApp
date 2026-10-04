import UIKit
import WebKit

/// `window.KtxAndroidApp` for the driver web pages: the same name and methods as the Android app,
/// so the TMS pages call it unchanged. Change both sides together.
///
/// The pages call it synchronously (`ok = KtxAndroidApp.startTracking(...)`), but WebKit's script
/// message handlers are asynchronous. The injected object therefore calls
/// `prompt("ktx:" + JSON)`, which blocks the page until `handle` answers through
/// `runJavaScriptTextInputPanelWithPrompt`. The answer is `{"v": value}` (no "v" = undefined).
///
/// Every call is refused unless the main frame is the driver site (WebHosts.isBridgeURL), checked
/// at the moment of the call.
enum KtxBridge {

    static let name = "KtxAndroidApp"
    static let promptPrefix = "ktx:"

    /// Fired on window and document after permissions or tracking may have changed; detail = status().
    static let statusEvent = "ktxappstatus"

    /// Injected at document start into the main frame only (iframes never get the object).
    static let userScript = WKUserScript(source: """
        (function () {
          if (window.\(name)) return;
          var ask = window.prompt.bind(window); // keep working if the page replaces window.prompt
          function call(method, args) {
            var list = Array.prototype.map.call(args, function (a) {
              return a === undefined || a === null ? null : String(a);
            });
            var answer = ask('\(promptPrefix)' + JSON.stringify({ method: method, args: list }));
            if (typeof answer !== 'string') return undefined;
            try { return JSON.parse(answer).v; } catch (e) { return undefined; }
          }
          var bridge = {
            startTracking: function () { return call('startTracking', arguments); },
            stopTracking: function () { call('stopTracking', arguments); },
            status: function () { return call('status', arguments); },
            requestPermissions: function () { call('requestPermissions', arguments); },
            version: function () { return call('version', arguments); }
          };
          Object.defineProperty(window, '\(name)', {
            value: Object.freeze(bridge), writable: false, configurable: false, enumerable: true
          });
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)

    static func isBridgeCall(_ prompt: String) -> Bool { prompt.hasPrefix(promptPrefix) }

    /// Answers one call. `allowed` = the main frame is the driver site and the call came from it.
    static func handle(prompt: String, allowed: Bool) -> String {
        guard let data = prompt.dropFirst(promptPrefix.count).data(using: .utf8),
              let call = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = call["method"] as? String else { return answer(nil) }
        let args = (call["args"] as? [Any]) ?? []
        func arg(_ i: Int) -> String? { i < args.count ? args[i] as? String : nil }

        switch method {
        case "startTracking":
            return answer(allowed && startTracking(phone: arg(0), url: arg(1), options: arg(2)))
        case "stopTracking":
            if allowed { LocationTracker.shared.stop() }
            return answer(nil)
        case "status":
            return answer(allowed ? statusJSON() : "{}")
        case "requestPermissions":
            if allowed { DispatchQueue.main.async { PermissionFlow.shared.start() } }
            return answer(nil)
        case "version":
            return answer(allowed ? AppInfo.version : "")
        default:
            return answer(nil)
        }
    }

    /// Starts sending positions for this driver. `options` is a JSON **string**
    /// `{"interval":30,"heartbeat":300}` (seconds; interval 10..600, heartbeat 60..3600, missing keys
    /// use the defaults). Calling again while tracking applies the new values. False when the phone,
    /// url or options are unusable.
    private static func startTracking(phone: String?, url: String?, options: String?) -> Bool {
        guard let cadence = TrackingState.parseCadence(options),
              LocationTracker.shared.start(phone: phone, url: url, cadence: cadence) else { return false }
        // Tracking is saved as on; it begins as soon as location is allowed.
        if !LocationTracker.shared.hasLocationPermission {
            DispatchQueue.main.async { PermissionFlow.shared.start() }
        }
        return true
    }

    /// {"tracking": bool, "lastSentAt": epoch ms | null, "permission": "always" | "whileInUse" | "denied",
    ///  "battery": "unrestricted", "interval": s, "heartbeat": s, "queued": n, "lastError": string | null}
    /// `tracking` is whether positions are actually being collected now. iOS has no battery
    /// restriction setting, so battery is always "unrestricted" (the page then hides its battery button).
    static func statusJSON() -> String {
        let state = TrackingState()
        let tracker = LocationTracker.shared
        let status: [String: Any] = [
            "tracking": tracker.isRunning,
            "lastSentAt": state.lastSentAt > 0 ? NSNumber(value: state.lastSentAt) : NSNull(),
            "permission": tracker.permissionLevel,
            "battery": "unrestricted",
            "interval": state.intervalSec,
            "heartbeat": state.heartbeatSec,
            "queued": FixQueue.shared.count(),
            "lastError": state.lastSendError ?? NSNull(),
        ]
        return jsonString(status) ?? "{}"
    }

    /// Script that fires "ktxappstatus" on window and on document with the current status.
    static func statusEventScript() -> String {
        let json = statusJSON()
        return """
            (function (d) {
              window.dispatchEvent(new CustomEvent('\(statusEvent)', { detail: d }));
              document.dispatchEvent(new CustomEvent('\(statusEvent)', { detail: d }));
            })(\(json));
            """
    }

    private static func answer(_ value: Any?) -> String {
        guard let value else { return "{}" }
        return jsonString(["v": value]) ?? "{}"
    }

    private static func jsonString(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
