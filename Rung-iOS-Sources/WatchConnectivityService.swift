#if os(iOS)
import Foundation
import SwiftData
import WatchConnectivity

/// iPhone-side glue between the live SwiftData store and the paired Apple
/// Watch. Activates `WCSession`, listens for the Watch's `logHabit` /
/// `toggleHabit` messages, and pushes a `WatchSnapshot` via
/// `updateApplicationContext` whenever the habit list or backend dashboard
/// changes.
///
/// The service is iOS-only (the watchOS companion is a separate target).
/// macOS Rung still compiles this file because the entire body is wrapped
/// in `#if os(iOS)`.
@MainActor
final class WatchConnectivityService: NSObject {

    static let shared = WatchConnectivityService()

    /// Latest container we know about. Set by `start(container:)` and used
    /// to fetch habits when applying inbound messages.
    private var modelContainer: ModelContainer?

    /// Latest backend store snapshot. Set by `attach(backend:)` so we can
    /// pull leaderboard / level data into the watch payload without the
    /// service knowing about the network layer.
    private weak var backend: HabitBackendStore?

    /// Debounce queue — collapses bursts of habit edits into one push so the
    /// Watch isn't woken up on every keystroke.
    private var pendingPushTimer: Timer?
    private var lastPushedJSON: Data?

    private override init() {
        super.init()
    }

    /// Activate the WCSession and start listening for Watch messages.
    /// Safe to call once at app launch — additional calls are no-ops.
    func start(container: ModelContainer) {
        self.modelContainer = container
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
            session.activate()
        }
    }

    /// Wire the backend store so leaderboard / level / streak data lands in
    /// the snapshot the Watch sees. Optional — without it the watch falls
    /// back to placeholder leaderboard data.
    func attach(backend: HabitBackendStore) {
        self.backend = backend
    }

    // MARK: - Outbound snapshot

    /// Schedule a debounced push of the current snapshot. Coalesces multiple
    /// calls within a 1-second window into a single `updateApplicationContext`
    /// call.
    func scheduleSnapshotPush(habits: [Habit]) {
        let snapshot = makeSnapshot(habits: habits)
        pendingPushTimer?.invalidate()
        pendingPushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pushSnapshot(snapshot)
            }
        }
    }

    /// Push immediately — used when the Watch explicitly asks for a fresh
    /// snapshot (`requestSnapshot` action).
    func pushSnapshotNow(habits: [Habit]) {
        let snapshot = makeSnapshot(habits: habits)
        pushSnapshot(snapshot)
    }

    private func pushSnapshot(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }

        // Skip if the payload is byte-identical to the last one we pushed —
        // saves Watch wake-ups while typing.
        if data == lastPushedJSON { return }
        lastPushedJSON = data

        let payload: [String: Any] = ["snapshot": data]

        // Live channel: sendMessage delivers in <100ms when the watch is
        // reachable (foreground or recent wrist-raise). We don't block on
        // the reply — applicationContext below guarantees eventual delivery
        // even if this fails. This is the same instant-feel pattern the
        // backend SSE channel gives us between iOS and macOS.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        }

        // Durable channel: applicationContext survives sleep + relaunches
        // and is the source of truth the watch reads on cold start.
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Most likely the Watch app isn't installed yet — ignore.
            print("[WatchConnectivity] updateApplicationContext failed: \(error)")
        }
    }

    // MARK: - Snapshot builder

    private func makeSnapshot(habits: [Habit]) -> WatchSnapshot {
        let now = Date()
        let todayKey = DateKey.key(for: now)
        let metrics = HabitMetrics.compute(for: habits, todayKey: todayKey)

        // Format weekday + time once on the phone so the watch doesn't have
        // to re-do the work every render.
        let weekdayShort: String = {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: now).uppercased()
        }()
        let timeOfDay: String = {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return f.string(from: now)
        }()

        // Split habits into pending / completed so the watch can render
        // strikethroughs without recomputing.
        var pending: [WatchSnapshot.WatchHabit] = []
        var completed: [WatchSnapshot.WatchHabit] = []
        let activeHabits = habits.filter { habit in
            !habit.isArchived
                && habit.entryType == .habit
                && (habit.weeklyTarget.map { habit.completionsInWeek(containing: now) < $0 } ?? true)
        }
        for habit in activeHabits {
            let watchHabit = makeWatchHabit(from: habit, todayKey: todayKey)
            if watchHabit.isCompleted {
                completed.append(watchHabit)
            } else {
                pending.append(watchHabit)
            }
        }

        // Leaderboard — prefer the backend's view; fall back to a single-user
        // entry so the Friends tab isn't empty for offline / brand-new users.
        let leaderboard: [WatchSnapshot.WatchLeaderboardEntry] = {
            if let entries = backend?.dashboard?.weeklyChallenge.leaderboard, !entries.isEmpty {
                return entries.enumerated().map { idx, entry in
                    WatchSnapshot.WatchLeaderboardEntry(
                        rank: idx + 1,
                        displayName: entry.displayName,
                        score: entry.score,
                        isCurrentUser: entry.currentUser
                    )
                }
            }
            return [
                WatchSnapshot.WatchLeaderboardEntry(
                    rank: 1, displayName: "You", score: metrics.xp, isCurrentUser: true
                )
            ]
        }()

        // Calendar heatmap — current month, perfect days at 1.0, partials
        // proportional to how many habits the user satisfied that day.
        let calendarHeatmap = computeMonthHeatmap(habits: activeHabits, around: now)

        // Account info — backend handles when signed in, falls back to
        // local placeholder for solo / offline use.
        let account: WatchSnapshot.AccountInfo = {
            let displayName = backend?.dashboard?.profile.displayName ?? "Rung"
            let username = backend?.dashboard?.profile.username
            let handle = (username?.isEmpty == false) ? "@\(username!)" : "@rung"
            let initial = String(displayName.prefix(1)).uppercased()
            // We can't query HealthKit auth state synchronously without
            // dragging the verifier in here. Treat any habit with an auto
            // source as a positive signal — if the user has at least one
            // HealthKit-linked habit, we know they granted scope.
            let healthKitOn = habits.contains { $0.isAutoVerified }
            return WatchSnapshot.AccountInfo(
                displayName: displayName,
                handle: handle,
                avatarInitial: initial.isEmpty ? "R" : initial,
                healthKitOn: healthKitOn,
                notificationsOn: true   // best-effort; the iPhone owns the real value
            )
        }()

        let monthLabel: String = {
            let f = DateFormatter()
            f.dateFormat = "LLL"
            return f.string(from: now).uppercased()
        }()

        let xpForNext = nextLevelXPThreshold(for: metrics.level)
        return WatchSnapshot(
            generatedAt: now,
            todayKey: todayKey,
            weekdayShort: weekdayShort,
            timeOfDay: timeOfDay,
            pendingHabits: pending,
            completedHabits: completed,
            metrics: WatchSnapshot.Metrics(
                doneToday: metrics.doneToday,
                totalToday: metrics.totalHabits,
                currentStreak: metrics.currentPerfectStreak,
                bestStreak: metrics.bestPerfectStreak,
                level: levelNumber(for: metrics.level),
                levelName: metrics.level.rawValue,
                xp: metrics.xp,
                xpForNextLevel: xpForNext,
                nextLevelProgress: metrics.nextLevelProgress,
                leaderboardRank: leaderboardRank(in: leaderboard),
                freezesAvailable: backend?.dashboard?.rewards.freezesAvailable ?? 0
            ),
            leaderboard: leaderboard,
            calendarHeatmap: calendarHeatmap,
            calendarMonthLabel: monthLabel,
            account: account,
            mentorMessages: makeMentorMessages(now: now)
        )
    }

    /// Maps the backend's mentee dashboard chat thread into the watch transport
    /// shape. Returns the most recent 8 messages (the watch only renders ~5 at
    /// a time but a small overflow lets the user scroll a touch). Unknown
    /// origin / empty thread → `nil` so the watch shows its empty state.
    private func makeMentorMessages(now: Date) -> [WatchSnapshot.WatchMentorMessage]? {
        guard let messages = backend?.dashboard?.menteeDashboard.messages,
              !messages.isEmpty else { return nil }
        let me = backend?.currentUserId
        let recent = messages.suffix(8)
        return recent.map { msg in
            let isMe = me.map { $0 == String(msg.senderId) } ?? false
            return WatchSnapshot.WatchMentorMessage(
                messageId: String(msg.id),
                origin: isMe ? .me : .mentor,
                senderName: isMe ? "You" : msg.senderName,
                preview: previewLine(from: msg.message),
                relativeTime: relativeStamp(iso: msg.createdAt, now: now),
                isUnread: !isMe && msg.nudge
            )
        }
    }

    private func previewLine(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.count <= 64 ? trimmed : String(trimmed.prefix(63)) + "\u{2026}"
    }

    private func relativeStamp(iso: String, now: Date) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
            ?? now
        let mins = Int(now.timeIntervalSince(date) / 60)
        if mins < 1 { return "now" }
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        let days = hrs / 24
        if days == 1 { return "yest" }
        return "\(days)d"
    }

    private func makeWatchHabit(from habit: Habit, todayKey: String) -> WatchSnapshot.WatchHabit {
        let kind: WatchSnapshot.HabitKind = habit.isAutoVerified ? .healthKit : .manual
        let isCompleted = habit.isSatisfied(on: todayKey)

        // Map verification source → unit label for the auto rows. Manual
        // habits default to a binary (target=0).
        let (unitsTarget, unitsLabel): (Int, String) = {
            guard kind == .healthKit, let source = habit.verificationSource else { return (0, "") }
            let param = Int(habit.effectiveVerificationParam ?? 0)
            switch source {
            case .healthKitWorkout:    return (param > 0 ? param : 30, "MIN")
            case .healthKitSteps:      return (param > 0 ? param : 8000, "STEPS")
            case .healthKitMindful:    return (param > 0 ? param : 5, "MIN")
            case .healthKitSleep:      return (param > 0 ? param : 7, "HR")
            case .healthKitBodyMass:   return (1, "LOG")
            case .healthKitHydration:  return (param > 0 ? param : 2000, "ML")
            case .healthKitNoAlcohol:  return (1, "DAY")
            case .screenTimeSocial:    return (param > 0 ? param : 60, "MIN")
            case .selfReport:          return (0, "")
            }
        }()

        let unitsLogged = isCompleted ? unitsTarget : 0
        let progress: Double = unitsTarget > 0
            ? Double(unitsLogged) / Double(unitsTarget)
            : (isCompleted ? 1.0 : 0.0)

        // Stable id — prefer the backend id, fall back to the local UUID,
        // then to the title hash. The watch sends this back verbatim.
        let id: String = {
            if let backendId = habit.backendId { return "b:\(backendId)" }
            if let uuid = habit.localUUID { return "u:\(uuid.uuidString)" }
            return "t:\(habit.title.lowercased())"
        }()

        return WatchSnapshot.WatchHabit(
            id: id,
            title: habit.title,
            emoji: emojiForHabit(habit),
            kind: kind,
            progress: progress,
            unitsLogged: unitsLogged,
            unitsTarget: unitsTarget,
            unitsLabel: unitsLabel,
            isCompleted: isCompleted,
            sourceLabel: kind == .healthKit ? "APPLE HEALTH" : "",
            canonicalKey: habit.canonicalKey
        )
    }

    /// Map canonical key → emoji using the same registry the watch keeps
    /// (mirrored in `RungWatch/Connectivity/DataModel.swift`). Returns "•"
    /// when no match is found so the watch UI never renders an empty slot.
    private func emojiForHabit(_ habit: Habit) -> String {
        switch habit.canonicalKey {
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
        default:            return "\u{2022}"   // •
        }
    }

    private func computeMonthHeatmap(habits: [Habit], around date: Date) -> [String: Double] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: date),
              let dayCount = cal.range(of: .day, in: .month, for: date)?.count
        else { return [:] }

        var out: [String: Double] = [:]
        for offset in 0..<dayCount {
            guard let day = cal.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            let key = DateKey.key(for: day)
            let activeOnDay = habits.filter { $0.createdAt <= day }
            guard !activeOnDay.isEmpty else { continue }
            let satisfied = activeOnDay.filter { $0.isSatisfied(on: key) }.count
            out[key] = Double(satisfied) / Double(activeOnDay.count)
        }
        return out
    }

    private func levelNumber(for level: UserLevel) -> Int {
        // Map symbolic levels to a 1...12 numeric ladder so the Watch's
        // circular badge has a single digit/two-digit value to render.
        // Approximate — the iOS app uses descriptive names.
        switch level {
        case .beginner:     return 1
        case .rising:       return 3
        case .consistent:   return 5
        case .elite:        return 7
        case .mentor:       return 9
        case .masterMentor: return 12
        }
    }

    private func nextLevelXPThreshold(for level: UserLevel) -> Int {
        switch level {
        case .beginner:     return 500
        case .rising:       return 1500
        case .consistent:   return 3500
        case .elite:        return 6000
        case .mentor:       return 9500
        case .masterMentor: return 0
        }
    }

    private func leaderboardRank(in entries: [WatchSnapshot.WatchLeaderboardEntry]) -> Int {
        entries.first(where: { $0.isCurrentUser })?.rank ?? 0
    }

    // MARK: - Inbound message routing

    /// Apply a `logHabit` / `toggleHabit` message from the Watch. Mutates
    /// SwiftData on the iPhone, then re-broadcasts a fresh snapshot.
    fileprivate func applyMessage(_ message: [String: Any]) {
        guard let action = message[WatchMessageKey.action] as? String else { return }
        switch action {
        case WatchMessageAction.requestSnapshot:
            forcePush()
        case WatchMessageAction.logHabit, WatchMessageAction.toggleHabit:
            applyHabitMutation(action: action, message: message)
        case WatchMessageAction.createHabit:
            applyCreateHabit(message: message)
        default:
            return
        }
    }

    /// Insert a SwiftData habit from a watch-originated voice/Scribble entry.
    /// Mirrors what `AddHabitBar` does on the iPhone for a freshly-typed
    /// title — no canonical match, no verification metadata, just a plain
    /// self-report habit. `staleResourceTick` triggers ContentView's sync
    /// loop, which uploads the new row to the backend on its next pass.
    private func applyCreateHabit(message: [String: Any]) {
        guard let container = modelContainer,
              let title = (message[WatchMessageKey.title] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return }
        let context = ModelContext(container)
        let habit = Habit(title: title)
        context.insert(habit)
        try? context.save()
        forcePush()
        backend?.staleResourceTick &+= 1
    }

    private func applyHabitMutation(action: String, message: [String: Any]) {
        guard let container = modelContainer,
              let id = message[WatchMessageKey.habitId] as? String else { return }
        let context = ModelContext(container)
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        guard let habit = matchHabit(habits, id: id) else { return }
        if habit.isAutoVerified { return }   // auto-verified rows ignore manual toggles

        let todayKey = DateKey.key(for: Date())
        var didFlipToDone = false

        switch action {
        case WatchMessageAction.toggleHabit:
            var keys = habit.completedDayKeys
            if let i = keys.firstIndex(of: todayKey) {
                keys.remove(at: i)
                habit.pendingCheckDayKey = todayKey
                habit.pendingCheckIsDone = false
            } else {
                keys.append(todayKey)
                habit.pendingCheckDayKey = todayKey
                habit.pendingCheckIsDone = true
                didFlipToDone = true
            }
            habit.completedDayKeys = keys.sorted()
            habit.updatedAt = Date()
            habit.syncStatus = .pending
        case WatchMessageAction.logHabit:
            // Treat any non-zero delta as "the user worked on this habit".
            // Without per-unit storage we can only flip the day to done; the
            // count UI on the watch is for guidance, not durable state.
            let delta = (message[WatchMessageKey.delta] as? Int) ?? 1
            if delta > 0, !habit.completedDayKeys.contains(todayKey) {
                habit.completedDayKeys = (habit.completedDayKeys + [todayKey]).sorted()
                habit.pendingCheckDayKey = todayKey
                habit.pendingCheckIsDone = true
                habit.updatedAt = Date()
                habit.syncStatus = .pending
                didFlipToDone = true
            }
        default:
            break
        }

        try? context.save()
        forcePush()

        // Mirror what ContentView.toggleHabit does on the iPhone side: stamp
        // a self-report verification tier so leaderboard points stay honest,
        // then bump backend.staleResourceTick. ContentView observes that
        // tick and runs syncWithBackend, which flushes our `.pending` row to
        // the server — the same path Mac + iOS already use, so all three
        // surfaces converge through the backend SSE stream within seconds.
        if let backend {
            if didFlipToDone {
                Task { @MainActor in
                    await backend.verifyCompletion(
                        habit: habit,
                        dayKey: todayKey,
                        modelContext: context
                    )
                    backend.staleResourceTick &+= 1
                }
            } else {
                backend.staleResourceTick &+= 1
            }
        }
    }

    private func matchHabit(_ habits: [Habit], id: String) -> Habit? {
        if id.hasPrefix("b:"), let backendId = Int64(id.dropFirst(2)) {
            return habits.first { $0.backendId == backendId }
        }
        if id.hasPrefix("u:") {
            let uuidStr = String(id.dropFirst(2))
            return habits.first { $0.localUUID?.uuidString == uuidStr }
        }
        if id.hasPrefix("t:") {
            let title = String(id.dropFirst(2))
            return habits.first { $0.title.lowercased() == title }
        }
        return nil
    }

    private func forcePush() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        pushSnapshotNow(habits: habits)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith activationState: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.forcePush()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so the next paired Watch can talk to us.
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            self.applyMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.applyMessage(userInfo)
        }
    }
}

#endif
