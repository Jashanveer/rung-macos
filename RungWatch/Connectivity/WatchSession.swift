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

    /// Live diagnostic snapshot the connecting view exposes so the user can
    /// see WHY the watch isn't loading data — activation pending, phone
    /// asleep, watch-app-not-installed-on-companion, etc. Updated on every
    /// delegate callback and on every send attempt.
    @Published private(set) var diagnostic: Diagnostic = Diagnostic()

    /// Number of explicit retry / requestSnapshot calls fired since launch.
    /// The connecting view shows this so the user has visual feedback that
    /// their tap is doing something even when sendMessage swallows errors.
    @Published private(set) var retryCount: Int = 0

    /// Last error string from `sendMessage`'s error callback, if any. Helps
    /// diagnose "iPhone not reachable" or stale companion bundle id issues.
    @Published private(set) var lastSendError: String?

    struct Diagnostic: Equatable {
        var activationState: String = "unknown"
        var isReachable: Bool = false
        var isCompanionAppInstalled: Bool = false
        var lastUpdated: Date = Date()
    }

    private override init() {
        super.init()
        // Hydrate from the persistent cache before WCSession even tries
        // to activate. Without this, the connecting view blocks the
        // whole UI on cold launch — the user sees "Open Rung on iPhone"
        // for as long as it takes the watch to (re-)negotiate with the
        // phone, even when we already have a perfectly good snapshot
        // from the previous session sitting on disk.
        if let cached = WatchSnapshotCache.load() {
            self.snapshot = cached
            self.hasReceivedRealData = !cached.account.handle.isEmpty
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshDiagnostic()
        ingestCachedApplicationContext(from: session)
    }

    #if DEBUG
    /// Build a fully-loaded session for SwiftUI #Previews without touching
    /// `WCSession`. Production code never calls this — `shared` is the only
    /// instance that lives in a real watch process.
    static func preview(hasRealData: Bool, snapshot: WatchSnapshot? = nil) -> WatchSession {
        let s = WatchSession()
        s.snapshot = snapshot ?? .empty()
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
        // Look up the row's pre-flip state so we can compute the target
        // `done` flag and pick the correct backend path (habit vs task).
        let allRows = snapshot.pendingHabits + snapshot.completedHabits
        guard let row = allRows.first(where: { $0.id == id }) else { return }
        let targetDone = !row.isCompleted
        let kind: WatchBackendClient.CheckKind =
            row.entryType == .task ? .task : .habit
        let dayKey = snapshot.todayKey

        applyOptimistic(id: id, completing: nil)

        // WC channel — fire-and-forget. Keeps iPhone's local SwiftData
        // in step instantly when reachable, and stays harmless when not.
        send([
            WatchMessageKey.action: WatchMessageAction.toggleHabit,
            WatchMessageKey.habitId: id
        ])

        // Durable channel — POST straight to the backend so the change
        // persists even when WC silently drops (the failure mode that
        // was making watch-side toggles revert after the optimistic
        // refresh tick). The server is authoritative; when this lands
        // every other device picks the change up via SSE / poll.
        if id.hasPrefix("b:"), let backendID = Int64(id.dropFirst(2)) {
            Task { @MainActor in
                await WatchBackendStore.shared.toggleCheck(
                    kind: kind,
                    backendID: backendID,
                    dayKey: dayKey,
                    done: targetDone
                )
            }
        } else {
            // Local-only entry (no backend ID assigned yet). WC is the
            // only path; schedule a refresh so we pick up the assigned
            // backend ID once iPhone syncs the new row upstream.
            WatchBackendStore.shared.scheduleRefresh(after: 1.5)
        }
    }

    /// Mutate `snapshot.pendingHabits` / `snapshot.completedHabits` to reflect
    /// a tap before the iPhone replies. `completing == true` forces "done",
    /// `false` forces "not done", `nil` flips whatever the row's current
    /// state is. Idempotent: matching by `id` means we never duplicate a row.
    /// Also stamps `lastOptimisticChangeAt` so the next backend payload
    /// older than this moment can't silently undo the user's tap.
    private func applyOptimistic(id: String, completing: Bool?) {
        markOptimisticChange()
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
            canonicalKey: row.canonicalKey,
            entryType: row.entryType,
            suggestionLabel: row.suggestionLabel
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

    /// Ask the iPhone to push a fresh snapshot. Called on first launch, on
    /// reachability transitions, on auto-retry from the connecting view,
    /// and on every Retry button tap. Bumps `retryCount` so the UI can
    /// confirm the user's tap registered.
    func requestSnapshot() {
        retryCount += 1
        // Re-activate the WCSession in case it dropped — activate() is
        // idempotent if already activated, and forces a fresh handshake
        // when the previous activation never completed.
        if WCSession.isSupported() {
            let s = WCSession.default
            if s.activationState != .activated {
                s.activate()
            }
            refreshDiagnostic()
            ingestCachedApplicationContext(from: s)
        }
        send([WatchMessageKey.action: WatchMessageAction.requestSnapshot])
    }

    private func refreshDiagnostic() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        let stateLabel: String = {
            switch s.activationState {
            case .notActivated:    return "notActivated"
            case .inactive:        return "inactive"
            case .activated:       return "activated"
            @unknown default:      return "unknown"
            }
        }()
        diagnostic = Diagnostic(
            activationState: stateLabel,
            isReachable: s.isReachable,
            isCompanionAppInstalled: s.isCompanionAppInstalled,
            lastUpdated: Date()
        )
    }

    /// Quick-add a habit from the watch (dictation / Scribble entry on the
    /// Habits tab). The iPhone owns SwiftData, so we send the title across
    /// and let it create the row + flush to backend; the next snapshot
    /// re-broadcast lands the new habit in our pending list.
    func createHabit(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // WC channel — fire-and-forget for instant iPhone-side parity
        // when reachable. Used to be the only channel, which meant a
        // dead WC link silently dropped every Add tap on the watch.
        send([
            WatchMessageKey.action: WatchMessageAction.createHabit,
            WatchMessageKey.title: trimmed
        ])
        // Durable channel — POST `/api/tasks` directly so the new task
        // lands on the server even when WC is unreachable. The
        // backend's SSE / poll fan-out then propagates the row to
        // iPhone, Mac, and iPad. Mark an optimistic stamp so the next
        // backend snapshot whose `generatedAt` predates this call gets
        // ignored (the polling fetch can't undo what the user just
        // committed).
        markOptimisticChange()
        Task { @MainActor in
            _ = await WatchBackendStore.shared.createTask(title: trimmed)
        }
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // Don't bail on non-activated state — kick activation and queue
        // through transferUserInfo so the message survives the gap.
        if session.activationState != .activated {
            print("[WatchSession] send: activation \(session.activationState.rawValue), kicking activate() and queuing via transferUserInfo")
            session.activate()
            session.transferUserInfo(payload)
            return
        }

        if session.isReachable {
            // Live phone: try sendMessage for instant delivery, AND queue
            // via transferUserInfo as a durable backup — sendMessage
            // silently drops if the iPhone goes background between the
            // reachability check and the actual delivery, so the backup
            // means a missed retry can never be lost.
            session.sendMessage(
                payload,
                replyHandler: { reply in
                    Task { @MainActor [weak self] in
                        self?.lastSendError = nil
                        self?.ingest(reply)
                        self?.refreshDiagnostic()
                    }
                },
                errorHandler: { err in
                    Task { @MainActor [weak self] in
                        print("[WatchSession] sendMessage error: \(err)")
                        self?.lastSendError = err.localizedDescription
                    }
                }
            )
        }
        // Always queue via transferUserInfo — survives sleep, relaunches,
        // and reachability hiccups. Cost is tiny (a few KB queued).
        session.transferUserInfo(payload)
        refreshDiagnostic()
    }

    // MARK: - Snapshot ingestion

    /// Bumped whenever the user toggles or creates an entry on the
    /// watch. `acceptBackendSnapshot` honours this — a backend payload
    /// is only allowed to replace the live snapshot when its
    /// `generatedAt` is strictly newer than this stamp, so a polling
    /// fetch that races a fresh tap can't revert what the user just
    /// committed.
    private var lastOptimisticChangeAt: Date?

    /// Mark that the watch just applied an optimistic mutation. Any
    /// backend snapshot generated before this instant is treated as
    /// stale (it pre-dates the user's tap) and gets dropped.
    fileprivate func markOptimisticChange() {
        lastOptimisticChangeAt = Date()
    }

    /// Wipe the in-memory snapshot and flip `hasReceivedRealData` back
    /// off so the root view falls into the connecting / sign-in screen
    /// the next render. Paired with `WatchAuthStore.clear()` +
    /// `WatchBackendStore.stop()` to cover the full sign-out path —
    /// the Account tab's Logout button calls all three.
    func signOut() {
        self.snapshot = .empty()
        self.hasReceivedRealData = false
        self.lastSendError = nil
        WatchSnapshotCache.clear()
    }

    /// Adopt a snapshot fetched directly from the backend by
    /// `WatchBackendStore`. Only overwrites the live snapshot when the
    /// backend payload is strictly newer than what's already on screen,
    /// so a slow server response can never clobber an optimistic toggle
    /// the user just made. Persists to cache + flips
    /// `hasReceivedRealData` exactly like a WC push so the existing
    /// SwiftUI gates work without modification.
    func acceptBackendSnapshot(_ snap: WatchSnapshot, updatedAt: Date) {
        // The backend's `updatedAt` is when iPhone last uploaded.
        //
        // We accept anything the server says is at-or-newer than what
        // we're already displaying. A strict `<` rejected ties — and a
        // freshly-restored snapshot from the local cache often has the
        // same `generatedAt` as the backend payload (the iPhone built
        // it once, both stores echo it). Letting equal timestamps
        // through means a re-fetch always brings the watch back in
        // sync with the server, fixing the "have to logout/login to
        // see new data" footgun.
        //
        // We still avoid clobbering when the backend payload is
        // strictly older than what's on screen — that protects an
        // optimistic toggle the user just made from being undone by a
        // stale server response that hadn't picked the change up yet.
        if snap.generatedAt < self.snapshot.generatedAt
            && self.hasReceivedRealData {
            return
        }
        // Optimistic guard: if the user just toggled or created
        // something on the watch, any backend payload generated before
        // that tap is by definition stale — it can't have seen the
        // change yet. Dropping it prevents the "tap → momentary check
        // → silent revert" footgun the previous version had.
        if let stamp = lastOptimisticChangeAt, snap.generatedAt < stamp {
            return
        }
        self.snapshot = snap
        self.hasReceivedRealData = !snap.account.handle.isEmpty
        WatchSnapshotCache.save(snap)
    }

    /// Decode a payload the phone sent and update `snapshot` if it parses.
    /// Centralised so application-context, user-info, and message payloads
    /// all funnel through one path. Side-effect: writes the snapshot to
    /// the persistent cache so the next cold launch shows data
    /// immediately instead of stalling on "Open Rung on iPhone".
    fileprivate func ingest(_ payload: [String: Any]) {
        // Auth token handoff. iOS pushes the live token as part of every
        // snapshot push so the Watch can later refresh on its own and
        // talk to the backend directly when the phone is in another room.
        if let token = payload["accessToken"] as? String {
            WatchAuthStore.shared.set(
                accessToken: token,
                expiresAtEpoch: payload["accessTokenExpiresAt"] as? TimeInterval,
                refreshToken: payload["refreshToken"] as? String
            )
        }
        guard let data = payload["snapshot"] as? Data else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(WatchSnapshot.self, from: data)
            self.snapshot = snap
            self.hasReceivedRealData = !snap.account.handle.isEmpty
            // Persist for the next cold launch. Cheap — Codable round-
            // trip is microseconds — and pays back as instant first-paint
            // when the watch boots while the phone is unreachable.
            WatchSnapshotCache.save(snap)
        } catch {
            // Malformed payload — keep the existing snapshot so the UI
            // doesn't flash empty. Log so a paired test surfaces the
            // mismatch.
            print("[WatchSession] decode failed: \(error)")
        }
    }

    private func ingestCachedApplicationContext(from session: WCSession = .default) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        ingest(context)
    }
}

// MARK: - WCSessionDelegate

extension WatchSession: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith state: WCSessionActivationState,
                              error: Error?) {
        if let error {
            print("[WatchSession] activation error: \(error)")
        }
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.refreshDiagnostic()
            self.ingestCachedApplicationContext(from: session)
            // Kick the phone for a fresh snapshot the first time we activate.
            if state == .activated {
                self.requestSnapshot()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.refreshDiagnostic()
            self.ingestCachedApplicationContext(from: session)
            // The iPhone just came online — ask for fresh data immediately
            // in case the Connecting view is currently visible.
            if session.isReachable, !self.hasReceivedRealData {
                self.requestSnapshot()
            }
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

    /// Symmetric ack for any sendMessage-with-reply that the iPhone might
    /// fire at us in future. Currently the iPhone uses fire-and-forget
    /// sendMessage for its snapshot pushes, but if that ever changes we
    /// don't want the iPhone to mirror the same `WCErrorCodeTransferTimedOut`
    /// problem we just fixed on the iPhone side. Reply FIRST, then ingest.
    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any],
                              replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler([:])
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
