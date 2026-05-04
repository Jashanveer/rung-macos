import Foundation
import Combine

/// Drives the watch's standalone backend fetch loop. Together with
/// `WatchSession` (the WC channel), this is the second source of truth
/// the watch can use to render data — fetched directly from the Rung
/// backend, no iPhone reachability required.
///
/// Lifecycle:
/// - Fires immediately on launch — pulls the latest snapshot the
///   iPhone uploaded so the watch has fresh data within seconds even
///   when iPhone is in another room.
/// - Polls every 90s while the app is foregrounded. Light enough to
///   not chew battery; frequent enough that travelling-with-just-watch
///   feels live.
/// - Updates `WatchSession`'s shared snapshot when a fetch beats the
///   currently-displayed `generatedAt` so newer data wins regardless
///   of source (WC or HTTP, whichever arrived first).
@MainActor
final class WatchBackendStore: ObservableObject {
    static let shared = WatchBackendStore()

    /// Most recent error from a backend fetch, surfaced into the
    /// connecting view's diagnostic block so the user can see WHY data
    /// isn't loading (no token yet, network down, etc.).
    @Published private(set) var lastError: String?

    /// True while a fetch is in flight. Connecting view dims its retry
    /// button so the user can't fire ten requests in a row.
    @Published private(set) var isFetching = false

    /// Server-stamped timestamp of the last successful fetch. The
    /// connecting view uses this to show "Last synced 2m ago".
    @Published private(set) var lastFetchedAt: Date?

    private let client = WatchBackendClient()
    private var pollTask: Task<Void, Never>?

    private init() {}

    /// Kick off the background poll loop. Idempotent — extra calls are
    /// no-ops, so the watch app can call this on every onAppear of the
    /// root view without leaking tasks.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    /// Tear the poll loop down. Used by sign-out so a logged-out watch
    /// stops hammering the server with 401s after the iPhone clears the
    /// token.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Run a fetch immediately. Used by:
    /// - the connecting view's Retry button
    /// - the SSE handler when `watch.snapshot.changed` fires
    /// - the cold-launch entry point in `RungWatchApp`
    func refreshNow() async {
        await fetchOnce()
    }

    private func runPollLoop() async {
        // Initial fetch as soon as we start so the first paint after a
        // cold launch shows server-fresh data. After that we poll
        // every 90 s — enough to feel live for a watch-only travel
        // session, light enough to not crater battery.
        await fetchOnce()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
            if Task.isCancelled { return }
            await fetchOnce()
        }
    }

    private func fetchOnce() async {
        // Don't bother making a request if we don't even have a token —
        // the watch has never been paired with a signed-in iPhone.
        guard WatchAuthStore.shared.current() != nil else {
            lastError = WatchBackendClient.Error.noToken.localizedDescription
            return
        }
        isFetching = true
        defer { isFetching = false }
        do {
            let result = try await client.fetchSnapshot()
            lastError = nil
            lastFetchedAt = result.updatedAt
            // Merge against the live session — only adopt the backend
            // snapshot when it's strictly newer than what's already
            // displayed (cache or WC). This keeps the live optimistic
            // toggles the user just made from being clobbered by an
            // older server payload.
            WatchSession.shared.acceptBackendSnapshot(
                result.snapshot,
                updatedAt: result.updatedAt
            )
        } catch let error as WatchBackendClient.Error {
            // Only overwrite the previous error if this one is a real
            // failure — `noSnapshotYet` is a normal first-launch state
            // that shouldn't surface as a user-visible error if we
            // already have cached data.
            if case .noSnapshotYet = error,
               WatchSession.shared.hasReceivedRealData {
                return
            }
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }
}
