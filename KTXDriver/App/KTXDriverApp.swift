import SwiftUI

@main
struct KTXDriverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // Back from Settings or another app: permission may have changed, queued fixes may be waiting.
            LocationTracker.shared.resumeIfTracking()
            FixUploader.shared.flush()
            NotificationCenter.default.post(name: .trackingStatusChanged, object: nil)
        }
    }
}
