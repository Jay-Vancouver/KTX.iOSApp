import SwiftUI

/// First-run guide progress. Once completed the guide is never shown again.
enum SetupState {
    private static let key = "setup_completed"

    static var completed: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// First-run guide: location "Always" with Precise Location. "Allow" walks through the disclosure
/// and the system prompts (PermissionFlow); once granted the button becomes "Start". Shown at every
/// launch until done, then never again. (iOS has no battery exemption, unknown-app installs or
/// ongoing notification, so unlike Android there is only the location item.)
struct SetupView: View {
    let onClose: () -> Void

    @State private var locationDone = SetupView.isLocationDone()
    @Environment(\.scenePhase) private var scenePhase

    private static let blue = Color("KTXBlue")
    private static let red = Color(red: 0xD7 / 255, green: 0x18 / 255, blue: 0x2A / 255)
    private static let green = Color(red: 0x1E / 255, green: 0x8E / 255, blue: 0x3E / 255)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(uiImage: UIImage(named: "SetupLogo") ?? UIImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Text("setup_title")
                        .font(.title.bold())
                        .foregroundColor(Self.blue)
                        .padding(.top, 16)
                    Text("setup_intro")
                        .font(.body)
                        .padding(.top, 8)
                    locationRow
                        .padding(.top, 16)
                }
                .padding(24)
            }

            Button(action: allowOrStart) {
                Text(locationDone ? "setup_start" : "setup_allow")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundColor(.white)
                    .background(Self.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)

            if !locationDone {
                Button("setup_later", action: onClose)
                    .foregroundColor(Self.blue)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 16)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .trackingStatusChanged)) { _ in refresh() }
        .onChange(of: scenePhase) { phase in if phase == .active { refresh() } }
    }

    private var locationRow: some View {
        Button {
            if !locationDone { PermissionFlow.shared.start() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(locationDone ? "✓" : "!")
                    .font(.title2.bold())
                    .foregroundColor(locationDone ? Self.green : Self.red)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("setup_location_title")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("setup_location_desc")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .multilineTextAlignment(.leading)
        }
        .disabled(locationDone)
    }

    private func allowOrStart() {
        if locationDone { onClose() } else { PermissionFlow.shared.start() }
    }

    private func refresh() {
        locationDone = Self.isLocationDone()
        if locationDone { SetupState.completed = true }
    }

    private static func isLocationDone() -> Bool {
        let tracker = LocationTracker.shared
        return tracker.authorization == .authorizedAlways && tracker.isPreciseLocation
    }
}
