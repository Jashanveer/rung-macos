import Foundation
import WatchConnectivity
import Combine

/// Owns the `WCSession` lifecycle on the Watch side. Receives `WatchSnapshot`
/// payloads from the iPhone via `updateApplicationContext` and exposes them
/// through an `@Published` property so SwiftUI views update automatically.
///
/// All work happens on the main actor — Watch screens are tiny, the snapshot
/// is small, and `WCSessionDelegate` callbacks come on a background queue
/// that we hop off immediately.
@MainActor
final class WatchSession: NSObject, ObservableObject {

    static let shared = WatchSession()

    /// Latest snapshot the iPhone pushed. Starts EMPTY (no fake friends or
    /// messages) — the root view checks `hasReceivedRealData` and shows a
    /// "connecting" UI until the iPhone delivers a real payload.
    @Published private(set) var snapshot: WatchSnapshot = .empty()

    /// `true` once we've received at least one real snapshot from the phone.
    /// UI uses this to dim "stale" placeholder data so users know the phone
    /// hasn't connected yet.
    @Published private(set) var hasReceivedRealData: Bool = false

    /// `true` while WCSession is activated and the phone is reachable for
    /// `sendMessage`. We don't hard-block sends on this — application context
    /// queues automatically when the phone is asleep.
    @Published private(set) var isReachable: Bool = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    #if DEBUG
    /// Build a fully-loaded session for SwiftUI #Previews without touching
    /// `WCSession`. Production code never calls this — `shared` is the only
    /// instance that lives in a real watch process.
    static func preview(hasRealData: Bool, snapshot: WatchSnapshot = .empty()) -> WatchSession {
        let s = WatchSession()
        s.snapshot = snapshot
        s.hasReceivedRealData = hasRealData
        s.isReachable = hasRealData
        return s
    }
    #endif

    // MARK: - Outbound messages

    /// Tell the iPhone to log a +N count delta against a manual habit.
    /// Used by `HabitDetailView` when the user rotates the crown.
    /// Also patches the local snapshot so the ring fills in instantly —
    /// the iPhone's authoritative re-broadcast lands a beat later via
    /// sendMessage / applicationContext and overwrites our optimistic state.
    func logHabit(id: String, delta: Int) {
        applyOptimistic(id: id, completing: delta > 0)
        send([
            WatchMessageKey.action: WatchMessageAction.logHabit,
            WatchMessageKey.habitId: id,
            WatchMessageKey.delta: delta
        ])
    }

    /// Tell the iPhone to flip a binary habit's done-state for today.
    /// Mutates the cached snapshot first so the row checks/unchecks the
    /// instant the user taps; the iPhone's re-broadcast confirms or corrects
    /// within a few hundred milliseconds when reachable.
    func toggleHabit(id: String) {
        applyOptimistic(id: id, completing: nil)
        send([
            WatchMessageKey.action: WatchMessageAction.toggleHabit,
            WatchMessageKey.habitId: id
        ])
    }

    /// Mutate `snapshot.pendingHabits` / `snapshot.completedHabits` to reflect
    /// a tap before the iPhone replies. `completing == true` forces "done",
    /// `false` forces "not done", `nil` flips whatever the row's current
    /// state is. Idempotent: matching by `id` means we never duplicate a row.
    private func applyOptimistic(id: String, completing: Bool?) {
        var snap = snapshot
        let allRows = snap.pendingHabits + snap.completedHabits
        guard let row = allRows.first(where: { $0.id == id }) else { return }
        guard row.kind == .manual else { return }   // auto-verified rows are read-only

        let target: Bool
        switch completing {
        case .some(let value): target = value
        case .none:            target = !row.isCompleted
        }

        let updated = WatchSnapshot.WatchHabit(
            id: row.id, title: row.title, emoji: row.emoji, kind: row.kind,
            progress: target ? max(row.progress, 1.0) : 0.0,
            unitsLogged: target && row.unitsTarget > 0 ? row.unitsTarget : 0,
            unitsTarget: row.unitsTarget, unitsLabel: row.unitsLabel,
            isCompleted: target, sourceLabel: row.sourceLabel,
            canonicalKey: row.canonicalKey
        )
        snap.pendingHabits   = snap.pendingHabits.filter   { $0.id != id }
        snap.completedHabits = snap.completedHabits.filter { $0.id != id }
        if target { snap.completedHabits.append(updated) }
        else      { snap.pendingHabits.append(updated) }

        // Bump the metrics counter so the header "4/7" updates in lockstep.
        let totalDone = snap.completedHabits.count
        snap.metrics = WatchSnapshot.Metrics(
            doneToday: totalDone,
            totalToday: snap.metrics.totalToday,
            currentStreak: snap.metrics.currentStreak,
            bestStreak: snap.metrics.bestStreak,
            level: snap.metrics.level,
            levelName: snap.metrics.levelName,
            xp: snap.metrics.xp,
            xpForNextLevel: snap.metrics.xpForNextLevel,
            nextLevelProgress: snap.metrics.nextLevelProgress,
            leaderboardRank: snap.metrics.leaderboardRank,
            freezesAvailable: snap.metrics.freezesAvailable
        )
        self.snapshot = snap
    }

    /// Ask the iPhone to push a fresh snapshot — used on first launch so the
    /// Watch isn't stuck on the empty initial state until the user does
    /// something on the phone.
    func requestSnapshot() {
        send([WatchMessageKey.action: WatchMessageAction.requestSnapshot])
    }

    /// Quick-add a habit from the watch (dictation / Scribble entry on the
    /// Habits tab). The iPhone owns SwiftData, so we send the title across
    /// and let it create the row + flush to backend; the next snapshot
    /// re-broadcast lands the new habit in our pending list.
    func createHabit(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send([
            WatchMessageKey.action: WatchMessageAction.createHabit,
            WatchMessageKey.title: trimmed
        ])
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            // Live phone: best-effort. We don't block the UI on the reply —
            // the iPhone re-broadcasts a fresh snapshot via application
            // context after applying the change.
            session.sendMessage(payload, replyHandler: nil) { _ in }
        } else {
            // Phone asleep / unreachable: queue via transferUserInfo so the
            // change isn't dropped. iPhone delivers it on next wake.
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Snapshot ingestion

    /// Decode a payload the phone sent and update `snapshot` if it parses.
    /// Centralised so application-context, user-info, and message payloads
    /// all funnel through one path.
    fileprivate func ingest(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(WatchSnapshot.self, from: data)
            self.snapshot = snap
            self.hasReceivedRealData = true
        } catch {
            // Malformed payload — keep the existing snapshot so the UI
            // doesn't flash empty. Log so a paired test surfaces the
            // mismatch.
            print("[WatchSession] decode failed: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSession: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith state: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            // Kick the phone for a fresh snapshot the first time we activate.
            if state == .activated {
                self.requestSnapshot()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.ingest(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.ingest(message)
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.ingest(userInfo)
        }
    }
}
