import SwiftUI

@main
struct RungWatchApp: App {
    @StateObject private var session = WatchSession.shared
    @StateObject private var backendStore = WatchBackendStore.shared

    /// Drives the wrist-raise / wake-from-suspend refresh path. Every
    /// time the scene transitions back to `.active` we ask the backend
    /// for the latest snapshot — that's how the watch picks up changes
    /// the user made on iPhone or macOS without needing to re-launch.
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, phase in
                    // Wrist raise fires `.active`. Coalesced refresh so
                    // a quick suspend/resume burst doesn't fire two
                    // requests within a second of each other.
                    if phase == .active {
                        Task { await backendStore.refreshIfStale() }
                    }
                }
        }
    }
}
