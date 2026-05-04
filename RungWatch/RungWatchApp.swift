import SwiftUI

@main
struct RungWatchApp: App {
    @StateObject private var session = WatchSession.shared
    @StateObject private var backendStore = WatchBackendStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(backendStore)
                .preferredColorScheme(.dark)
                .task {
                    // Kick off the standalone backend poller alongside
                    // WC. The two race; whichever fresh snapshot lands
                    // first wins (`acceptBackendSnapshot` keeps the
                    // newer one). On a watch-only travel session, this
                    // is the path that keeps the UI live.
                    backendStore.start()
                }
        }
    }
}
