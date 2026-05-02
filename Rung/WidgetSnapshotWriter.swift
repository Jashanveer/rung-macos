import Foundation
import SwiftData
import WidgetKit

/// Produces WidgetSnapshot JSON from the live SwiftData store and writes it to
/// the App Group container so the widget extension can render without hitting
/// SwiftData directly. Runs on the main actor because SwiftData's ModelContext
/// is main-actor-isolated.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private var container: ModelContainer?
    private var timer: Timer?
    private var lastPayload: Data?
    /// Latest server dashboard snapshot. Nil until the user signs in and the
    /// dashboard has loaded at least once.
    private var latestBackend: WidgetSnapshot.BackendData?

    /// Call once at app launch with the shared container.
    /// Writes an initial snapshot, then refreshes every 15s.
    func start(container: ModelContainer) {
        self.container = container
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let writer = self else { return }
            Task { @MainActor in writer.refresh() }
        }
    }

    /// Called by HabitBackendStore whenever a fresh dashboard arrives.
    /// Cheap — just caches and triggers a refresh so widgets pick it up.
    func updateBackendData(_ dashboard: AccountabilityDashboard) {
        latestBackend = Self.makeBackendData(from: dashboard)
        refresh()
    }

    /// Called on sign-out to clear cached backend data from the snapshot.
    func clearBackendData() {
        latestBackend = nil
        refresh()
    }

    /// Build a snapshot from the current store and persist it.
    /// Cheap; skips the file write + WidgetCenter reload when nothing changed.
    func refresh() {
        guard let container else { return }
        guard let url = WidgetSnapshot.fileURL else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>()
        guard let habits = try? context.fetch(descriptor) else { return }

        drainToggleOutbox(context: context, habits: habits)

        let visible = habits.filter { !$0.isArchived }
        let todayKey = DateKey.key(for: Date())
        let metrics = HabitMetrics.compute(for: visible, todayKey: todayKey)

        let entries: [WidgetSnapshot.HabitEntry] = visible
            .sorted { $0.createdAt < $1.createdAt }
            .map { h in
                return WidgetSnapshot.HabitEntry(
                    id: Self.widgetId(for: h),
                    title: h.title,
                    doneToday: h.completedDayKeys.contains(todayKey),
                    icon: nil
                )
            }

        let recent = DateKey.recentDays(count: 7)
        let weekly: [WidgetSnapshot.WeekdayPct] = recent.map { day in
            let total = visible.filter { Calendar.current.startOfDay(for: $0.createdAt) <= DateKey.date(from: day.key) }.count
            guard total > 0 else {
                return WidgetSnapshot.WeekdayPct(label: day.shortLabel, key: day.key, pct: 0)
            }
            let done = visible.filter { $0.completedDayKeys.contains(day.key) }.count
            return WidgetSnapshot.WeekdayPct(label: day.shortLabel, key: day.key, pct: Double(done) / Double(total))
        }

        let last28 = DateKey.recentDays(count: 28).map { day in
            guard !visible.isEmpty else { return false }
            return visible.allSatisfy { $0.completedDayKeys.contains(day.key) }
        }

        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            todayKey: todayKey,
            habits: entries,
            doneToday: metrics.doneToday,
            totalToday: metrics.totalHabits,
            currentPerfectStreak: metrics.currentPerfectStreak,
            bestPerfectStreak: metrics.bestPerfectStreak,
            weeklyPcts: weekly,
            perfectDaysCount: metrics.perfectDaysCount,
            last28DaysDone: last28,
            backend: latestBackend
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }

        // Skip write + reload if nothing changed (cheap; widgets reload is rate-limited by the system anyway).
        if data == lastPayload { return }
        lastPayload = data

        do {
            if let dir = WidgetSnapshot.containerURL {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Silent — App Group may not be provisioned in dev.
        }

        // Re-broadcast the new state to the paired Apple Watch. Debounced
        // inside the service so a burst of toggles becomes one push.
        #if os(iOS)
        WatchConnectivityService.shared.scheduleSnapshotPush(habits: visible)
        #endif
    }

    // MARK: - Toggle outbox

    /// Drain widget-originated toggles into SwiftData. The regular sync engine
    /// picks up the resulting `pendingCheckDayKey` on its next flush.
    private func drainToggleOutbox(context: ModelContext, habits: [Habit]) {
        let pending = WidgetToggleOutbox.readAll()
        guard !pending.isEmpty else { return }

        var mutated = false
        for entry in pending {
            guard let habit = habits.first(where: { Self.widgetId(for: $0) == entry.habitId }) else { continue }
            // Auto-verified habits (HealthKit/Screen Time) own their own
            // completion state via AutoVerificationCoordinator. The widget
            // must never push a manual day-key toggle for them — doing so
            // would inject phantom dots into the 7-day strip (the user's
            // "2 dots" bug if the widget is tapped on a different day than
            // today's verified completion).
            if habit.isAutoVerified { continue }
            applyToggle(to: habit, dayKey: entry.dayKey)
            mutated = true
        }
        WidgetToggleOutbox.clear()
        if mutated {
            try? context.save()
        }
    }

    private func applyToggle(to habit: Habit, dayKey: String) {
        var keys = habit.completedDayKeys
        let wasUnchecked = !keys.contains(dayKey)
        if let i = keys.firstIndex(of: dayKey) {
            keys.remove(at: i)
        } else {
            keys.append(dayKey)
        }
        habit.completedDayKeys = keys.sorted()
        habit.updatedAt = Date()
        if habit.backendId != nil {
            habit.syncStatus = .pending
            habit.pendingCheckDayKey = dayKey
            habit.pendingCheckIsDone = wasUnchecked
        }
    }

    static func widgetId(for habit: Habit) -> String {
        if let b = habit.backendId {
            switch habit.entryType {
            case .habit:
                return "h\(b)"
            case .task:
                return "t\(b)"
            }
        }
        return "l\(habit.persistentModelID.hashValue)"
    }

    // MARK: - Mapping

    private static func makeBackendData(
        from d: AccountabilityDashboard
    ) -> WidgetSnapshot.BackendData {
        let mentorCard: WidgetSnapshot.BackendData.MentorCard? = {
            guard let match = d.match else { return nil }
            return .init(
                displayName: match.mentor.displayName,
                consistencyPercent: match.mentor.weeklyConsistencyPercent,
                tip: d.menteeDashboard.mentorTip,
                missedHabitsToday: d.menteeDashboard.missedHabitsToday,
                progressScore: d.menteeDashboard.progressScore
            )
        }()

        let mentees: [WidgetSnapshot.BackendData.MenteeCard] = d.mentorDashboard.mentees.map {
            .init(
                matchId: $0.matchId,
                userId: $0.userId,
                displayName: $0.displayName,
                missedHabitsToday: $0.missedHabitsToday,
                consistencyPercent: $0.weeklyConsistencyPercent,
                suggestedAction: $0.suggestedAction
            )
        }

        let friends: [WidgetSnapshot.BackendData.FriendCard] = (d.social?.suggestions ?? []).map {
            .init(
                userId: $0.userId,
                displayName: $0.displayName,
                progressPercent: $0.progressPercent,
                consistencyPercent: $0.weeklyConsistencyPercent
            )
        }

        let leaderboard: [WidgetSnapshot.BackendData.LeaderEntry] = d.weeklyChallenge.leaderboard.map {
            .init(displayName: $0.displayName, score: $0.score, currentUser: $0.currentUser)
        }

        let todayKey = DateKey.key(for: Date())
        return WidgetSnapshot.BackendData(
            xp: d.rewards.xp,
            levelName: d.level.name,
            weeklyConsistencyPercent: d.level.weeklyConsistencyPercent,
            accountabilityScore: d.level.accountabilityScore,
            checksToday: d.rewards.checksToday,
            dailyCap: d.rewards.dailyCap,
            freezesAvailable: d.rewards.freezesAvailable,
            frozenToday: d.rewards.frozenDates.contains(todayKey),
            challenge: .init(
                title: d.weeklyChallenge.title,
                completedPerfectDays: d.weeklyChallenge.completedPerfectDays,
                targetPerfectDays: d.weeklyChallenge.targetPerfectDays,
                rank: d.weeklyChallenge.rank
            ),
            leaderboard: leaderboard,
            mentor: mentorCard,
            mentees: mentees,
            activeMenteeCount: d.mentorDashboard.activeMenteeCount,
            friends: friends,
            friendCount: d.social?.friendCount ?? friends.count
        )
    }
}
