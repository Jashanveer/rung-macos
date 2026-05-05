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

    /// Tunable foreground poll interval. 15 s — fast enough that a
    /// habit toggled on iPad / iPhone shows up on the wrist within a
    /// glance, slow enough that an all-day wear doesn't burn through
    /// disproportionate battery. The watch's connectivity stack
    /// doesn't really wake the radio for these — it piggybacks on
    /// whatever the system was already doing. ScenePhase-active
    /// transitions (wrist raise) trigger an immediate refresh on top
    /// of this, so the upper bound on staleness is ~one glance.
    static let foregroundPollInterval: TimeInterval = 15

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

    /// POST a new task straight to the backend so the row exists on
    /// the server immediately — no dependency on the iPhone WC roundtrip.
    /// Returns true when the create succeeded so the caller can decide
    /// whether to dismiss the Add screen or surface an error. On
    /// success we schedule a snapshot refresh so the new task lands in
    /// the watch's pending list within a second.
    func createTask(title: String) async -> Bool {
        do {
            _ = try await client.createTask(title: title)
            scheduleRefresh(after: 0.5)
            return true
        } catch let error as WatchBackendClient.Error {
            lastError = error.localizedDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// PUT a single habit/task check straight to the backend, then
    /// schedule a refresh so the watch picks up server-derived state
    /// (XP, streak, leaderboard rank) the toggle just changed. This
    /// is the durable channel for watch-side toggles — much more
    /// reliable than the iPhone WC roundtrip, which silently drops
    /// when the phone is unreachable.
    func toggleCheck(
        kind: WatchBackendClient.CheckKind,
        backendID: Int64,
        dayKey: String,
        done: Bool
    ) async {
        do {
            try await client.setCheck(
                kind: kind,
                backendID: backendID,
                dayKey: dayKey,
                done: done
            )
            scheduleRefresh(after: 0.4)
        } catch let error as WatchBackendClient.Error {
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
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

        // Run all three reads in parallel. The iPhone-built snapshot
        // is the source for fields only iPhone can compute (energy,
        // mentor messages, leaderboard, account, level/XP). The
        // primary `/api/habits` + `/api/tasks` lists are the source
        // of truth for what's checked off — fetching them directly
        // means a habit toggled on iPad shows up on the wrist within
        // one poll tick, even when iPhone hasn't re-uploaded its
        // cached snapshot. Each fetch handles its own 401 → refresh.
        async let snapshotResult = client.fetchSnapshot()
        async let habitsResult = client.listHabits()
        async let tasksResult = client.listTasks()

        var snapshot: WatchSnapshot? = nil
        var snapshotUpdatedAt: Date? = nil
        var snapshotError: WatchBackendClient.Error? = nil
        do {
            let result = try await snapshotResult
            snapshot = result.snapshot
            snapshotUpdatedAt = result.updatedAt
        } catch let err as WatchBackendClient.Error {
            snapshotError = err
        } catch {
            snapshotError = .transport(error)
        }

        var habits: [WatchBackendClient.BackendHabitRow] = []
        var tasks: [WatchBackendClient.BackendHabitRow] = []
        do { habits = try await habitsResult } catch {}
        do { tasks  = try await tasksResult  } catch {}

        // Merge — primary endpoints win for the habit/task list, the
        // iPhone-built snapshot wins for everything else. If the
        // primary lists failed (network blip, server down) we fall
        // back to the snapshot's own habits so the watch keeps
        // rendering rather than going blank.
        if let snapshot, let snapshotUpdatedAt {
            let merged = mergeSnapshot(
                snapshot,
                habits: habits,
                tasks: tasks,
                hasLivePrimary: !habits.isEmpty || !tasks.isEmpty
            )
            lastError = nil
            lastFetchedAt = snapshotUpdatedAt
            WatchSession.shared.acceptBackendSnapshot(
                merged,
                updatedAt: snapshotUpdatedAt
            )
        } else if !habits.isEmpty || !tasks.isEmpty {
            // Snapshot fetch failed but the primary lists succeeded —
            // build a minimal snapshot from them. This is the
            // standalone-without-iPhone case: a brand-new account
            // has no `/api/watch/snapshot` payload yet but `/api/habits`
            // already returns rows, so we can still paint Today.
            let merged = mergeSnapshot(
                WatchSession.shared.snapshot,
                habits: habits,
                tasks: tasks,
                hasLivePrimary: true
            )
            lastError = nil
            WatchSession.shared.acceptBackendSnapshot(merged, updatedAt: Date())
        } else if let snapshotError {
            // Both paths failed. Surface the snapshot error since
            // that's the primary one users recognise.
            if case .noSnapshotYet = snapshotError,
               WatchSession.shared.hasReceivedRealData {
                return
            }
            lastError = snapshotError.localizedDescription
        }
    }

    /// Replace the iPhone-built snapshot's `pendingHabits` /
    /// `completedHabits` with rows freshly fetched from `/api/habits`
    /// + `/api/tasks`. Falls back to the snapshot's lists when the
    /// primary endpoints didn't produce anything — protects against
    /// transient empty results that would briefly blank the watch.
    /// Recomputes `metrics.doneToday` / `totalToday` from the new
    /// rows so the daily-ring header stays in step with the merged
    /// list.
    private func mergeSnapshot(
        _ snapshot: WatchSnapshot,
        habits: [WatchBackendClient.BackendHabitRow],
        tasks: [WatchBackendClient.BackendHabitRow],
        hasLivePrimary: Bool
    ) -> WatchSnapshot {
        guard hasLivePrimary else { return snapshot }
        let todayKey = snapshot.todayKey

        var pending: [WatchSnapshot.WatchHabit] = []
        var completed: [WatchSnapshot.WatchHabit] = []

        // Pull title / suggestion / emoji metadata from the iPhone
        // snapshot when it's there — the primary endpoints don't ship
        // the AI suggestion label or the canonical-emoji map. Keyed
        // by the same "b:<id>" string the snapshot uses so a row's
        // sticky metadata survives a primary-driven refresh.
        let snapshotById: [String: WatchSnapshot.WatchHabit] = {
            var dict: [String: WatchSnapshot.WatchHabit] = [:]
            for row in snapshot.pendingHabits + snapshot.completedHabits {
                dict[row.id] = row
            }
            return dict
        }()

        for row in habits {
            let watchRow = makeWatchHabit(
                row, todayKey: todayKey, entryType: .habit,
                inheritFrom: snapshotById["b:\(row.id)"]
            )
            if watchRow.isCompleted {
                completed.append(watchRow)
            } else {
                pending.append(watchRow)
            }
        }
        for row in tasks {
            let watchRow = makeWatchHabit(
                row, todayKey: todayKey, entryType: .task,
                inheritFrom: snapshotById["b:\(row.id)"]
            )
            if watchRow.isCompleted {
                completed.append(watchRow)
            } else {
                pending.append(watchRow)
            }
        }

        let totalToday = pending.count + completed.count
        let doneToday = completed.count

        let metrics = WatchSnapshot.Metrics(
            doneToday: doneToday,
            totalToday: totalToday,
            currentStreak: snapshot.metrics.currentStreak,
            bestStreak: snapshot.metrics.bestStreak,
            level: snapshot.metrics.level,
            levelName: snapshot.metrics.levelName,
            xp: snapshot.metrics.xp,
            xpForNextLevel: snapshot.metrics.xpForNextLevel,
            nextLevelProgress: snapshot.metrics.nextLevelProgress,
            leaderboardRank: snapshot.metrics.leaderboardRank,
            freezesAvailable: snapshot.metrics.freezesAvailable
        )

        return WatchSnapshot(
            generatedAt: Date(),
            todayKey: snapshot.todayKey,
            weekdayShort: snapshot.weekdayShort,
            timeOfDay: snapshot.timeOfDay,
            pendingHabits: pending,
            completedHabits: completed,
            metrics: metrics,
            leaderboard: snapshot.leaderboard,
            calendarHeatmap: snapshot.calendarHeatmap,
            calendarMonthLabel: snapshot.calendarMonthLabel,
            account: snapshot.account,
            mentorMessages: snapshot.mentorMessages,
            energy: snapshot.energy,
            perfectDays: snapshot.perfectDays
        )
    }

    /// Build a `WatchSnapshot.WatchHabit` from a primary backend row.
    /// Inherits emoji / suggestion / unit metadata from the iPhone
    /// snapshot when it's available — those come from canonical-key
    /// lookup tables and the AI advisor that only iPhone can compute.
    /// New rows (not yet in the iPhone snapshot, e.g. created on
    /// another device since the iPhone last uploaded) get sensible
    /// fallbacks until iPhone catches up.
    private func makeWatchHabit(
        _ row: WatchBackendClient.BackendHabitRow,
        todayKey: String,
        entryType: WatchSnapshot.EntryType,
        inheritFrom prior: WatchSnapshot.WatchHabit?
    ) -> WatchSnapshot.WatchHabit {
        let isCompleted = row.checksByDate[todayKey] ?? false
        let isHealthKit: Bool = {
            if let source = row.verificationSource {
                return source.hasPrefix("healthKit") || source == "screenTimeSocial"
            }
            return prior?.kind == .healthKit
        }()
        let kind: WatchSnapshot.HabitKind = isHealthKit ? .healthKit : .manual
        let emoji = prior?.emoji ?? Self.fallbackEmoji(for: row.canonicalKey)
        let unitsTarget = prior?.unitsTarget ?? 0
        let unitsLabel = prior?.unitsLabel ?? ""
        let unitsLogged = isCompleted ? unitsTarget : 0
        let progress: Double = isCompleted ? 1.0 : 0.0

        return WatchSnapshot.WatchHabit(
            id: "b:\(row.id)",
            title: row.title,
            emoji: emoji,
            kind: kind,
            progress: progress,
            unitsLogged: unitsLogged,
            unitsTarget: unitsTarget,
            unitsLabel: unitsLabel,
            isCompleted: isCompleted,
            sourceLabel: kind == .healthKit ? "APPLE HEALTH" : "",
            canonicalKey: row.canonicalKey,
            entryType: entryType,
            suggestionLabel: prior?.suggestionLabel
        )
    }

    /// Tiny canonical-key → emoji fallback. Mirrors
    /// `WatchDataModel.emojiByCanonicalKey` so a row that arrives
    /// from the primary endpoint before the iPhone has uploaded its
    /// canonical-emoji decoration still gets a glyph.
    private static func fallbackEmoji(for canonicalKey: String?) -> String {
        guard let key = canonicalKey else { return "\u{2022}" }
        switch key {
        case "run":         return "\u{1F3C3}"
        case "workout":     return "\u{1F3CB}"
        case "walk":        return "\u{1F6B6}"
        case "yoga":        return "\u{1F9D8}"
        case "cycle":       return "\u{1F6B4}"
        case "swim":        return "\u{1F3CA}"
        case "meditate":    return "\u{1F9D8}"
        case "sleep":       return "\u{1F319}"
        case "weighIn":     return "\u{2696}\u{FE0F}"
        case "water":       return "\u{1F4A7}"
        case "noAlcohol":   return "\u{1F6AB}"
        case "screenTime":  return "\u{1F4F1}"
        case "read":        return "\u{1F4DA}"
        case "study":       return "\u{270F}\u{FE0F}"
        case "journal":     return "\u{1F4DD}"
        case "gratitude":   return "\u{1F64F}"
        case "floss":       return "\u{1F9B7}"
        case "makeBed":     return "\u{1F6CF}\u{FE0F}"
        case "eatHealthy":  return "\u{1F957}"
        case "family":      return "\u{1F46A}"
        default:            return "\u{2022}"
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
