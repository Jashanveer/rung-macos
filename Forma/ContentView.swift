import Combine
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.createdAt) private var habits: [Habit]
    @StateObject private var backend = HabitBackendStore()
    @StateObject private var timeReminderManager = TimeReminderManager()

    @State private var hasCompletedOnboarding = false
    @State private var newHabitTitle = ""
    @State private var newEntryType: HabitEntryType = .task
    @State private var progressOpen = false
    @State private var calendarOpen = false
    @State private var settingsOpen = false
    @State private var showCelebration = false
    @State private var mentorNudge: String? = nil
    /// Freshly-checked habits that should linger in the list for a short beat so
    /// the 7-day dot row can fill in place before the card morphs into a
    /// background stamp via matched geometry.
    @State private var stampStagingIds: Set<PersistentIdentifier> = []
    @Namespace private var stampNamespace

    private var showOnboarding: Bool { backend.isAuthenticated && !hasCompletedOnboarding }

    private var onboardingKey: String {
        "onboarded_\(backend.currentUserId ?? "anon")"
    }

    private static let nudgeMessages = [
        "Well done! 💪", "Keep it up!", "That's the way!", "Proud of you!",
        "One step closer!", "You're crushing it!", "Consistency wins!",
        "Nice work! 🎉", "That's a win!", "Stay the course!",
    ]

    private var todayKey: String { DateKey.key(for: Date()) }
    private var metrics: HabitMetrics { HabitMetrics.compute(for: habits, todayKey: todayKey) }

    /// True only when the main dashboard is the foreground view — no overlay
    /// panels (progress / settings / calendar / onboarding) are covering it.
    /// Bruce and the rival mentee live strictly on this dashboard so they
    /// don't peek out from behind the side panels or calendar sheet.
    private var isDashboardForeground: Bool {
        !showOnboarding && !progressOpen && !settingsOpen && !calendarOpen
    }

    // AI mentor is always on once the user is signed in — but only on the
    // dashboard. Any overlay (onboarding, stats sidebar, settings, calendar)
    // suppresses Bruce so he doesn't peek out from behind the cover.
    private var showMentorCharacter: Bool {
        backend.isAuthenticated && isDashboardForeground
    }

    // Mentee slot surfaces a top-leaderboard friend — only shown when the
    // user has at least one friend on the leaderboard. Same dashboard-only
    // gate as Bruce so the orange character doesn't appear over any panel.
    private var showMenteeCharacter: Bool {
        guard backend.isAuthenticated, isDashboardForeground else { return false }
        let friendCount = backend.dashboard?.social?.friendCount ?? 0
        let leaderboard = backend.dashboard?.weeklyChallenge.leaderboard ?? []
        return friendCount > 0 && !leaderboard.isEmpty
    }

    var body: some View {
        ContentViewScaffold(
            colorScheme: colorScheme,
            habits: habits,
            todayKey: todayKey,
            newHabitTitle: $newHabitTitle,
            newEntryType: $newEntryType,
            metrics: metrics,
            backend: backend,
            progressOpen: $progressOpen,
            calendarOpen: $calendarOpen,
            settingsOpen: $settingsOpen,
            showCelebration: showCelebration,
            mentorNudge: $mentorNudge,
            showMentorCharacter: showMentorCharacter,
            showMenteeCharacter: showMenteeCharacter,
            showOnboarding: showOnboarding,
            stampNamespace: stampNamespace,
            stampStagingIds: stampStagingIds,
            onAddHabit: addHabit,
            onToggleHabit: toggleHabit,
            onDeleteHabit: archiveHabit,
            onSync: syncWithBackend,
            onReminderChange: updateReminderWindow,
            onCompleteOnboarding: completeOnboarding
        )
        .onChange(of: backend.isAuthenticated) { _, isAuth in
            hasCompletedOnboarding = isAuth ? resolveOnboardingState() : false
        }
        .onChange(of: backend.isOnline) { wasOnline, isOnline in
            // Connectivity restored — flush any offline edits to the server.
            // flushOutbox inside syncWithBackend replays pending creates,
            // metadata updates, and check toggles captured via pendingCheckDayKey.
            guard !wasOnline, isOnline, backend.isAuthenticated else { return }
            syncWithBackend()
        }
        .onChange(of: backend.justRegistered) { _, isNew in
            guard isNew else { return }
            // Fresh registration — force the James Clear overview to appear once,
            // overriding any stale onboarded_<userId> UserDefaults key left from
            // a prior dev database reset or a re-registered deleted account.
            UserDefaults.standard.removeObject(forKey: onboardingKey)
            hasCompletedOnboarding = false
            backend.justRegistered = false
        }
        .onAppear {
            if backend.isAuthenticated {
                hasCompletedOnboarding = resolveOnboardingState()
            }
            refreshTimeReminders()
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            refreshTimeReminders()
            handleOverdueTasks()
        }
        .animation(.smooth(duration: 0.2), value: colorScheme)
        .task {
            guard backend.isAuthenticated else { return }
            syncWithBackend()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsTokenReceived)) { note in
            guard let token = note.object as? Data else { return }
            Task { await backend.registerDeviceToken(token) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apnsNudgeReceived)) { note in
            guard let message = note.object as? String else { return }
            mentorNudge = message
        }
    }

    // MARK: - Add habit

    private func addHabit(
        _ entryType: HabitEntryType,
        dueAt: Date? = nil,
        canonical: CanonicalHabit? = nil,
        weeklyTarget: Int? = nil
    ) {
        let title = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        guard backend.isAuthenticated else {
            backend.errorMessage = "Sign in before adding items."
            return
        }

        // Defensive guard mirroring AddHabitBar's UI block: an unfinished
        // overdue task must be cleared before any new task is created.
        if entryType == .task && habits.contains(where: { $0.entryType == .task && $0.isOverdue() }) {
            backend.errorMessage = "Finish your overdue task before adding a new one."
            return
        }

        // Duplicate guard: refuse if the same title already exists (habits
        // always, tasks only while the previous one is still pending).
        if Habit.hasDuplicate(title: title, entryType: entryType, in: habits) {
            backend.errorMessage = entryType == .habit
                ? "You already have a habit called \u{201C}\(title)\u{201D}."
                : "You already have a pending task called \u{201C}\(title)\u{201D}."
            return
        }

        // Optimistic local insert with .pending status. Canonical metadata
        // is applied locally only for now — the backend doesn't yet accept
        // verification fields (Phase 2) so we don't send them on create.
        let localHabit = Habit(
            title: title,
            entryType: entryType,
            syncStatus: .pending,
            dueAt: entryType == .task ? dueAt : nil,
            verificationTier: canonical?.tier ?? .selfReport,
            verificationSource: canonical?.source,
            verificationParam: canonical?.param,
            canonicalKey: canonical?.key,
            weeklyTarget: entryType == .habit ? weeklyTarget : nil
        )
        withAnimation { modelContext.insert(localHabit) }
        newHabitTitle = ""
        saveAndRefreshWidgets()

        Task {
            do {
                let remoteHabit: BackendHabit
                switch entryType {
                case .habit:
                    remoteHabit = try await backend.createHabit(
                        title: title,
                        reminderWindow: localHabit.reminderWindow
                    )
                case .task:
                    remoteHabit = try await backend.createTask(title: title)
                }
                localHabit.backendId  = remoteHabit.id
                localHabit.reminderWindow = remoteHabit.reminderWindow
                localHabit.syncStatus = .synced
                localHabit.updatedAt  = Date()
                backend.errorMessage  = nil
                saveAndRefreshWidgets()
                await backend.refreshDashboard()
            } catch {
                localHabit.syncStatus = .failed
                backend.errorMessage  = error.localizedDescription
                saveAndRefreshWidgets()
            }
            refreshTimeReminders()
        }
    }

    // MARK: - Full sync (outbox flush → pull → reconcile)

    private func syncWithBackend() {
        guard backend.isAuthenticated else { return }

        Task {
            do {
                try await flushOutbox()
                async let habitsResponse = backend.listHabits()
                async let tasksResponse = backend.listTasks()
                let remoteHabits = try await habitsResponse
                let remoteTasks = try await tasksResponse
                let remote = remoteHabits + remoteTasks
                applyReconcile(SyncEngine.reconcile(local: habits, remote: remote))
                saveAndRefreshWidgets()
                backend.errorMessage  = nil
                // Load the dashboard before handling overdue tasks so the
                // freeze count is accurate — otherwise a cold launch with
                // overdue tasks will fall back to the XP-dock path because
                // `backend.dashboard` is still nil.
                await backend.refreshDashboard()
                handleOverdueTasks()
                saveAndRefreshWidgets()
                refreshTimeReminders()
            } catch {
                backend.errorMessage = error.localizedDescription
            }
        }
    }

    /// Upload all local habits not yet confirmed by the server.
    /// Server-wins: once a backendId is assigned the pull will overwrite local values.
    private func flushOutbox() async throws {
        // 1. Create habits that have never been uploaded
        for habit in SyncEngine.pendingCreates(in: habits) {
            habit.syncStatus = .pending
            do {
                let remote: BackendHabit
                switch habit.entryType {
                case .habit:
                    remote = try await backend.createHabit(
                        title: habit.title,
                        reminderWindow: habit.reminderWindow
                    )
                case .task:
                    remote = try await backend.createTask(title: habit.title)
                }
                habit.backendId  = remote.id
                habit.reminderWindow = remote.reminderWindow
                // Upload any pre-existing checks for this habit
                for dayKey in habit.completedDayKeys {
                    switch habit.entryType {
                    case .habit:
                        try await backend.setCheck(habitID: remote.id, dateKey: dayKey, done: true)
                    case .task:
                        try await backend.setTaskCheck(taskID: remote.id, dateKey: dayKey, done: true)
                    }
                }
                habit.syncStatus = .synced
                habit.updatedAt  = Date()
            } catch {
                habit.syncStatus = .failed
                throw error
            }
        }

        // 2. Push metadata changes for existing habits, including reminder windows.
        for habit in habits where habit.backendId != nil && (habit.syncStatus == .pending || habit.syncStatus == .failed) {
            guard let bid = habit.backendId else { continue }
            do {
                let remote: BackendHabit
                switch habit.entryType {
                case .habit:
                    remote = try await backend.updateHabit(
                        habitID: bid,
                        title: habit.title,
                        reminderWindow: habit.reminderWindow
                    )
                case .task:
                    remote = try await backend.updateTask(taskID: bid, title: habit.title)
                }
                habit.title = remote.title
                habit.reminderWindow = remote.reminderWindow
                if habit.pendingCheckDayKey == nil && habit.syncStatus == .pending {
                    habit.syncStatus = .synced
                }
                habit.updatedAt = Date()
            } catch {
                habit.syncStatus = .failed
                throw error
            }
        }

        // 3. Retry failed habits with no specific pending check — re-push all done keys
        // (Skip habits that have a pendingCheckDayKey; those are handled precisely in step 3.)
        for habit in SyncEngine.failedUploads(in: habits) where habit.pendingCheckDayKey == nil {
            guard let bid = habit.backendId else { continue }
            do {
                for dayKey in habit.completedDayKeys {
                    switch habit.entryType {
                    case .habit:
                        try await backend.setCheck(habitID: bid, dateKey: dayKey, done: true)
                    case .task:
                        try await backend.setTaskCheck(taskID: bid, dateKey: dayKey, done: true)
                    }
                }
                if habit.pendingCheckDayKey == nil {
                    habit.syncStatus = .synced
                }
                habit.updatedAt  = Date()
            } catch {
                // Leave as .failed — the badge will invite the user to retry manually
            }
        }

        // 4. Push pending check-state (toggles that weren't confirmed, including unchecks).
        // This is the fix for: offline toggle → sync → server-wins overwrites the pending toggle.
        // We process habits where pendingCheckDayKey is set regardless of syncStatus so that
        // both the in-flight `.pending` case and the failed `.failed` case are retried.
        let pendingChecks = habits.filter { $0.backendId != nil && $0.pendingCheckDayKey != nil }
        for habit in pendingChecks {
            guard let bid = habit.backendId, let dayKey = habit.pendingCheckDayKey else { continue }
            let done = habit.pendingCheckIsDone
            do {
                switch habit.entryType {
                case .habit:
                    try await backend.setCheck(habitID: bid, dateKey: dayKey, done: done)
                case .task:
                    try await backend.setTaskCheck(taskID: bid, dateKey: dayKey, done: done)
                }
                habit.pendingCheckDayKey = nil   // confirmed — reconcile may now overwrite safely
                habit.syncStatus = .synced
                habit.updatedAt  = Date()
            } catch {
                habit.syncStatus = .failed
                // pendingCheckDayKey stays set so the next sync can retry
            }
        }
    }

    /// Apply a `ReconcileResult` to SwiftData. Conflict policy: server-wins.
    private func applyReconcile(_ result: SyncEngine.ReconcileResult) {
        for (local, remote) in result.toUpdate {
            // Never overwrite while a check toggle is pending confirmation.
            // Once flushOutbox confirms the upload it clears pendingCheckDayKey,
            // allowing the next reconcile pass to apply server state safely.
            guard local.pendingCheckDayKey == nil else { continue }
            // Also skip in-flight creates (syncStatus == .pending with no backendId is
            // already excluded from toUpdate, but guard against future edge cases).
            guard local.syncStatus == .synced || local.syncStatus == .failed else { continue }
            local.title             = remote.title
            local.reminderWindow    = remote.reminderWindow
            local.entryType         = remote.entryType
            if remote.localCreatedAt < local.createdAt {
                local.createdAt = remote.localCreatedAt
            }
            local.completedDayKeys  = remote.completedDayKeys
            local.syncStatus        = .synced
            local.updatedAt         = Date()
        }
        for remote in result.toInsert {
            modelContext.insert(Habit(
                title: remote.title,
                entryType: remote.entryType,
                createdAt: remote.localCreatedAt,
                completedDayKeys: remote.completedDayKeys,
                backendId: remote.id,
                syncStatus: .synced,
                reminderWindow: remote.reminderWindow
            ))
        }
        for habit in result.toDelete {
            modelContext.delete(habit)
        }
    }

    // MARK: - Toggle habit

    private func toggleHabit(_ habit: Habit) {
        // Tasks stay completed once checked — clicking a done task is a no-op.
        if habit.entryType == .task && habit.isTaskCompleted { return }

        var keys = habit.completedDayKeys
        let wasUnchecked: Bool
        if habit.entryType == .task {
            // Tasks: mark as completed for today (single key marking permanent completion).
            wasUnchecked = true
            keys = [todayKey]
        } else {
            wasUnchecked = !keys.contains(todayKey)
            if let i = keys.firstIndex(of: todayKey) { keys.remove(at: i) } else { keys.append(todayKey) }
        }

        let habitID = habit.persistentModelID

        if wasUnchecked {
            // Hold the card in the list while the 7th day dot fills, then release
            // so matched geometry can morph the card into a background stamp.
            stampStagingIds.insert(habitID)
        }

        withAnimation(.snappy(duration: 0.2)) {
            habit.completedDayKeys = keys.sorted()
            habit.updatedAt = Date()
            if habit.backendId != nil {
                habit.syncStatus = .pending
                // Record the exact operation so flushOutbox can upload the right done value,
                // including unchecks (done=false) which were previously never retried.
                habit.pendingCheckDayKey = todayKey
                habit.pendingCheckIsDone = wasUnchecked
            }
        }
        saveAndRefreshWidgets()

        if wasUnchecked {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    _ = stampStagingIds.remove(habitID)
                }
            }
        } else {
            // Unchecking a habit that was showing as a stamp — skip staging so it
            // reappears in the list immediately.
            stampStagingIds.remove(habitID)
        }

        if wasUnchecked && showMentorCharacter {
            mentorNudge = Self.nudgeMessages.randomElement()
        }

        if wasUnchecked && habits.count > 1 {
            let doneAfter = habits.filter { h in
                h.id == habit.id ? keys.contains(todayKey) : h.completedDayKeys.contains(todayKey)
            }.count
            if doneAfter == habits.count { triggerCelebration() }
        }

        refreshTimeReminders()

        guard let backendId = habit.backendId, backend.isAuthenticated else { return }
        Task {
            do {
                switch habit.entryType {
                case .habit:
                    try await backend.setCheck(habitID: backendId, dateKey: todayKey, done: wasUnchecked)
                case .task:
                    try await backend.setTaskCheck(taskID: backendId, dateKey: todayKey, done: wasUnchecked)
                }
                habit.pendingCheckDayKey = nil   // operation confirmed — safe to reconcile
                habit.syncStatus = .synced
                saveAndRefreshWidgets()
                // Only verify on the done→true transition; unchecking never
                // deserves credit, and sync-replay callers skip this method.
                if wasUnchecked {
                    Task { await backend.verifyCompletion(habit: habit, dayKey: todayKey, modelContext: modelContext) }
                }
                await backend.refreshDashboard()
            } catch {
                // Keep pendingCheckDayKey set so flushOutbox can retry the exact operation
                habit.syncStatus = .failed
                backend.errorMessage = error.localizedDescription
                saveAndRefreshWidgets()
            }
            refreshTimeReminders()
        }
    }

    // MARK: - Overdue task enforcement

    /// Overdue tasks stay on the list and continue to block new task creation
    /// until the user finishes them. The first time a task crosses its due
    /// date we dock local XP. Streak freezes are never spent automatically —
    /// the user must tap "Use today" in the StreakFreezeCard to protect a day.
    private func handleOverdueTasks() {
        let unpenalised = habits.filter {
            $0.entryType == .task && $0.isOverdue() && !$0.overduePenaltyApplied
        }
        guard !unpenalised.isEmpty else { return }

        var xpDocked = 0
        let userId = backend.currentUserId

        for task in unpenalised {
            task.overduePenaltyApplied = true
            task.updatedAt = Date()
            xpDocked += OverduePenaltyStore.xpPerOverdueTask
            OverduePenaltyStore.add(OverduePenaltyStore.xpPerOverdueTask, for: userId)
        }

        saveAndRefreshWidgets()

        let count = unpenalised.count
        let noun = count == 1 ? "task" : "tasks"
        let freezeHint = (backend.dashboard?.rewards.freezesAvailable ?? 0) > 0
            ? " Tap the freeze card to protect today."
            : ""
        backend.statusMessage = "\(count) overdue \(noun) — -\(xpDocked) XP. Finish them to unblock new tasks.\(freezeHint)"
    }

    // MARK: - Archive habits / delete tasks

    private func archiveHabit(_ habit: Habit) {
        if habit.entryType == .task {
            deleteTask(habit)
            return
        }

        let backendId = habit.backendId
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            habit.isArchived = true
            habit.updatedAt = Date()
        }
        saveAndRefreshWidgets()

        guard let backendId, backend.isAuthenticated else { return }
        Task {
            do {
                switch habit.entryType {
                case .habit:
                    try await backend.deleteHabit(habitID: backendId)
                case .task:
                    try await backend.deleteTask(taskID: backendId)
                }
                await backend.refreshDashboard()
                refreshTimeReminders()
            } catch {
                backend.errorMessage = error.localizedDescription
            }
            saveAndRefreshWidgets()
        }
    }

    private func deleteTask(_ task: Habit) {
        let backendId = task.backendId
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            modelContext.delete(task)
        }
        saveAndRefreshWidgets()

        guard let backendId, backend.isAuthenticated else {
            refreshTimeReminders()
            return
        }

        Task {
            do {
                try await backend.deleteTask(taskID: backendId)
                await backend.refreshDashboard()
            } catch {
                backend.errorMessage = error.localizedDescription
            }
            saveAndRefreshWidgets()
            refreshTimeReminders()
        }
    }

    private func updateReminderWindow(_ habit: Habit, _ window: HabitReminderWindow?) {
        guard habit.entryType == .habit else { return }

        withAnimation(.smooth(duration: 0.16)) {
            habit.reminderWindow = window?.rawValue
            habit.updatedAt = Date()
            if habit.backendId != nil {
                habit.syncStatus = .pending
            }
        }
        saveAndRefreshWidgets()

        refreshTimeReminders()

        guard let backendId = habit.backendId, backend.isAuthenticated else { return }
        Task {
            do {
                let remote = try await backend.updateHabit(
                    habitID: backendId,
                    title: habit.title,
                    reminderWindow: habit.reminderWindow
                )
                habit.title = remote.title
                habit.reminderWindow = remote.reminderWindow
                habit.syncStatus = .synced
                habit.updatedAt = Date()
                saveAndRefreshWidgets()
                refreshTimeReminders()
            } catch {
                habit.syncStatus = .failed
                backend.errorMessage = error.localizedDescription
                saveAndRefreshWidgets()
                refreshTimeReminders()
            }
        }
    }

    // MARK: - Onboarding

    /// Decides whether to skip onboarding for an authenticated user.
    /// Onboarding is signup-only — existing accounts that sign in (including on a
    /// new device with no UserDefaults state) should never see it.
    private func resolveOnboardingState() -> Bool {
        let key = onboardingKey
        if UserDefaults.standard.bool(forKey: key) { return true }
        if !backend.justRegistered {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return false
    }

    private func completeOnboarding(_ habitTitles: [String]) {
        // Dedupe across both the existing habit list and earlier entries in
        // this same batch — the SwiftData @Query doesn't re-fire inside the
        // loop, so a local seen-set is the only way to catch duplicates that
        // appear back-to-back in `habitTitles`.
        var seen = Set(habits.map { Habit.duplicateMatchKey($0.title) })
        for title in habitTitles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = Habit.duplicateMatchKey(trimmed)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let habit = Habit(title: trimmed, entryType: .habit, syncStatus: .pending)
            modelContext.insert(habit)
        }
        UserDefaults.standard.set(true, forKey: onboardingKey)
        withAnimation(.easeOut(duration: 0.3)) {
            hasCompletedOnboarding = true
        }
        saveAndRefreshWidgets()
        refreshTimeReminders()
        if !habitTitles.isEmpty { syncWithBackend() }
    }

    // MARK: - Helpers

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showCelebration = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) { showCelebration = false }
        }
    }

    private func refreshTimeReminders() {
        let habitEntries = habits.filter { $0.entryType == .habit }
        timeReminderManager.refreshReminders(
            for: habitEntries,
            todayKey: todayKey
        )

        let activeHabits = habitEntries.filter { !$0.isArchived }
        let hasIncompleteHabits = activeHabits.contains { !$0.completedDayKeys.contains(todayKey) }
        let freezes = backend.dashboard?.rewards.freezesAvailable ?? 0
        let isFrozen = backend.dashboard?.rewards.frozenDates.contains(todayKey) ?? false

        timeReminderManager.refreshStreakEndingReminder(
            currentStreak: metrics.currentPerfectStreak,
            hasIncompleteHabits: hasIncompleteHabits,
            freezesAvailable: freezes,
            isFrozenToday: isFrozen
        )
    }

    private func saveAndRefreshWidgets() {
        do {
            try modelContext.save()
        } catch {
            backend.errorMessage = error.localizedDescription
        }
        WidgetSnapshotWriter.shared.refresh()
    }
}

#Preview("Light") {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
        .preferredColorScheme(.dark)
}
