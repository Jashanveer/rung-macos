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

    /// Tunable foreground poll interval. 30 s by default — fast enough
    /// that a habit toggled on iOS feels live within one wrist-raise,
    /// slow enough that a wrist worn all day doesn't burn through a
    /// disproportionate amount of battery. The watch's connectivity
    /// stack doesn't really wake the radio for these — it piggybacks
    /// on whatever the system was already doing.
    static let foregroundPollInterval: TimeInterval = 30

    /// Bumped on every successful or attempted fetch so callers can
    /// rate-limit their own refresh requests (e.g. avoid two rapid
    /// scenePhase->refresh ticks within a second of each other).
    private var lastFetchAttemptedAt: Date = .distantPast

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
    /// - scenePhase transitions (wrist raise / app foreground)
    /// - watch-side toggles, ~1.2s after the user taps a habit so the
    ///   server has time to round-trip the change before we re-fetch
    func refreshNow() async {
        await fetchOnce()
    }

    /// Coalesced refresh — guards against multiple "user did a thing"
    /// events firing the same fetch within a second. Skips the request
    /// when the last attempt was less than `minimumGap` seconds ago.
    func refreshIfStale(minimumGap: TimeInterval = 2) async {
        if Date().timeIntervalSince(lastFetchAttemptedAt) < minimumGap { return }
        await fetchOnce()
    }

    /// Schedule a refresh to fire `delay` seconds from now. Used after
    /// a watch-side toggle so the optimistic UI commits, then the
    /// server's authoritative snapshot back-fills any state the toggle
    /// can't compute locally (XP, streak, leaderboard rank).
    func scheduleRefresh(after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await self.refreshIfStale()
        }
    }

    private func runPollLoop() async {
        // Initial fetch as soon as we start so the first paint after a
        // cold launch shows server-fresh data. After that we poll on
        // the foreground cadence — the watch is foregrounded only when
        // the user is actively looking at it, so 30 s is the right
        // balance between "feels live" and battery.
        await fetchOnce()
        while !Task.isCancelled {
            let nanos = UInt64(Self.foregroundPollInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
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
        lastFetchAttemptedAt = Date()
        isFetching = true
        defer { isFetching = false }
        do {
            let result = try await client.fetchSnapshot()
            lastError = nil
            lastFetchedAt = result.updatedAt
            // Merge against the live session — adopt anything the
            // backend hands us that's at least as fresh as what we're
            // showing. The server is authoritative for derived state
            // (streak, XP, leaderboard) that the watch can't recompute
            // locally, so a tie on `generatedAt` should still win.
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

    /// Persist tokens after a successful Apple sign-in completed
    /// directly on the watch. Triggers an immediate snapshot fetch so
    /// the connecting view can flip to the populated tabs without a
    /// poll-cycle wait. This is the path that makes the watch genuinely
    /// independent — when WC is broken, the user can sign in on the
    /// watch with their Apple ID and never need to open Rung on iPhone.
    func acceptAuthResult(_ result: WatchBackendClient.AuthResult) async {
        WatchAuthStore.shared.set(
            accessToken: result.accessToken,
            expiresAtEpoch: result.accessTokenExpiresAtEpochSeconds.map { TimeInterval($0) },
            refreshToken: result.refreshToken
        )
        await fetchOnce()
    }
}
