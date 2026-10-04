import Combine
import CoreLocation
import SwiftUI

/// App status and the server address, opened by swiping left→right across the top of the main
/// screen. Status is open to everyone; changing the address needs the admin PIN.
/// The iOS counterpart of the Android SettingsActivity.
struct SettingsView: View {
    let onClose: () -> Void

    @State private var rows: [(label: LocalizedStringKey, value: String)] = []
    @State private var serverURL = ServerConfig.startURL.absoluteString
    @State private var serverCustom = ServerConfig.startURLOverride != nil

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            List {
                Section("settings_status") {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline) {
                            Text(rows[i].label)
                            Spacer(minLength: 16)
                            Text(rows[i].value)
                                .foregroundColor(Color("KTXBlue"))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button("settings_permissions") { PermissionFlow.shared.start() }
                }
                Section("settings_server") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serverURL).textSelection(.enabled)
                        Text(serverCustom ? "settings_server_custom" : "settings_server_default")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Button("settings_change_server") { ServerAddressEditor(onSaved: onClose).start() }
                }
            }
            .navigationTitle("settings_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings_close", action: onClose)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .trackingStatusChanged)) { _ in refresh() }
    }

    private func refresh() {
        let state = TrackingState()
        let tracker = LocationTracker.shared
        let lastSent = state.lastSentAt
        let lastError = state.lastSendError.map { error -> String in
            let at = Date(timeIntervalSince1970: TimeInterval(state.lastSendErrorAt) / 1000)
            return at.formatted(date: .omitted, time: .shortened) + " " + error
        }
        let permission: String
        switch tracker.authorization {
        case .authorizedAlways: permission = String(localized: "settings_perm_always")
        case .authorizedWhenInUse: permission = String(localized: "settings_perm_while_in_use")
        default: permission = String(localized: "settings_perm_denied")
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        rows = [
            ("settings_tracking", String(localized: tracker.isRunning ? "settings_on" : "settings_off")),
            ("settings_last_sent", lastSent > 0
                ? Date(timeIntervalSince1970: TimeInterval(lastSent) / 1000).formatted(date: .numeric, time: .standard)
                : String(localized: "settings_never")),
            ("settings_queued", String(format: String(localized: "settings_queued_value"), FixQueue.shared.count())),
            ("settings_last_error", lastError ?? String(localized: "settings_no_error")),
            ("settings_location", permission),
            ("settings_precise", String(localized: tracker.hasLocationPermission && tracker.isPreciseLocation
                                        ? "settings_on" : "settings_off")),
            ("settings_cadence", String(format: String(localized: "settings_cadence_value"),
                                        state.intervalSec, state.heartbeatSec)),
            ("settings_version", "\(AppInfo.version) (\(build))"),
        ]
        serverURL = ServerConfig.startURL.absoluteString
        serverCustom = ServerConfig.startURLOverride != nil
    }
}
