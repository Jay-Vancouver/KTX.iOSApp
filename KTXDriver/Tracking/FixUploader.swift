import Foundation
import Network
import UIKit

/// Posts queued positions in order on one serial queue (OsmAnd protocol, form body).
/// The server stores a repeated (id, timestamp) once, so re-sending after an unclear failure is safe.
///
/// Watchdog: on an Android phone the sender once blocked inside a request and nothing was sent for
/// two hours. Here every send waits at most `stuckSeconds`; past that the request is cancelled,
/// the error recorded, and the queue moves on to the next trigger.
final class FixUploader {

    static let shared = FixUploader()

    private static let timeoutSeconds: TimeInterval = 15
    private static let stuckSeconds: TimeInterval = 60

    private let queue = DispatchQueue(label: "com.ktxtransport.driver.FixUploader")
    private let session: URLSession
    private let pathMonitor = NWPathMonitor()
    private var state: TrackingState { TrackingState() }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.timeoutSeconds
        config.timeoutIntervalForResource = Self.stuckSeconds
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)

        // Back online (dead zone ended, airplane mode off): send what is waiting right away.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { self?.flush() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.ktxtransport.driver.FixUploader.path"))
    }

    func enqueue(url: String, body: String) {
        queue.async {
            FixQueue.shared.add(url: url, body: body)
            self.flushNow()
        }
    }

    func flush() {
        queue.async { self.flushNow() }
    }

    /// Sends until the queue is empty or a send fails (then waits for the next trigger).
    /// Runs on `queue`; a background task keeps it going briefly if the app is leaving the foreground.
    private func flushNow() {
        guard FixQueue.shared.count() > 0 else { return }
        let task = BackgroundTask.begin("FixUploader")
        defer { task.end() }

        while true {
            let batch = FixQueue.shared.oldest(limit: 50)
            if batch.isEmpty { return }
            for fix in batch {
                switch post(fix) {
                case .sent:
                    FixQueue.shared.remove(id: fix.id)
                    state.lastSentAt = TrackingState.nowMs()
                    state.recordSendError(nil)
                case .rejected(let reason):
                    FixQueue.shared.remove(id: fix.id)
                    NSLog("FixUploader: server rejected a fix (%@); dropped", reason)
                    state.recordSendError(reason)
                case .retry(let reason):
                    NSLog("FixUploader: send failed (%@); %d waiting, will retry", reason, FixQueue.shared.count())
                    state.recordSendError(reason)
                    return
                }
            }
        }
    }

    private enum Result {
        case sent
        case rejected(String)
        case retry(String)
    }

    private func post(_ fix: FixQueue.Fix) -> Result {
        guard let url = URL(string: fix.url), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return .rejected("bad url \(fix.url)")
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppInfo.userAgentToken, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(fix.body.utf8)

        var result = Result.retry("no response")
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, response, error in
            if let error {
                result = .retry(Self.describe(error))
            } else if let code = (response as? HTTPURLResponse)?.statusCode {
                switch code {
                case 200...299: result = .sent
                // 4xx other than timeout / rate limit: the server will never take this one.
                case 400...499 where code != 408 && code != 429: result = .rejected("HTTP \(code)")
                default: result = .retry("HTTP \(code)") // 3xx, 408, 429, 5xx
                }
            }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + Self.stuckSeconds) == .timedOut {
            task.cancel()
            return .retry("stuck \(Int(Self.stuckSeconds))s, cancelled")
        }
        return result
    }

    /// Short English text for lastError (the page shows it as is; not localized, like Android).
    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain else { return "\(e.domain) \(e.code)" }
        let names: [Int: String] = [
            NSURLErrorTimedOut: "timed out",
            NSURLErrorCannotConnectToHost: "cannot connect to host",
            NSURLErrorCannotFindHost: "cannot find host",
            NSURLErrorDNSLookupFailed: "DNS lookup failed",
            NSURLErrorNetworkConnectionLost: "connection lost",
            NSURLErrorNotConnectedToInternet: "offline",
            NSURLErrorSecureConnectionFailed: "TLS failed",
            NSURLErrorServerCertificateUntrusted: "untrusted certificate",
            NSURLErrorCancelled: "cancelled",
            NSURLErrorAppTransportSecurityRequiresSecureConnection: "blocked by ATS (http)",
        ]
        return "URLError \(e.code)" + (names[e.code].map { " (\($0))" } ?? "")
    }
}

/// UIApplication background task wrapper that is safe to start and end from any thread.
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    static func begin(_ name: String) -> BackgroundTask {
        let task = BackgroundTask()
        let start = {
            task.id = UIApplication.shared.beginBackgroundTask(withName: name) {
                // Time is up: unsent fixes stay queued and go out on the next trigger.
                task.finish()
            }
        }
        if Thread.isMainThread { start() } else { DispatchQueue.main.sync(execute: start) }
        return task
    }

    func end() {
        DispatchQueue.main.async { self.finish() }
    }

    /// Main thread only.
    private func finish() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
