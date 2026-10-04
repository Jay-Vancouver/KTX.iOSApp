import SwiftUI

/// Root view: the web screen, edge to edge (it paints KTX blue behind the status bar itself),
/// with the first-run guide on top until it is completed. The page keeps loading behind it.
struct ContentView: View {
    @State private var showSetup = !SetupState.completed

    var body: some View {
        WebScreen()
            .ignoresSafeArea()
            .onOpenURL { url in
                // Universal Links (e.g. SMS login link /driver/s/<token>) arrive here.
                LinkRouter.shared.open(url)
            }
            .fullScreenCover(isPresented: $showSetup) {
                SetupView { showSetup = false }
            }
    }
}

private struct WebScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}
