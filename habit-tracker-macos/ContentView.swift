import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @StateObject private var backend = HabitBackendStore()

    @State private var newHabitTitle = ""
    @State private var progressOpen = false
    @State private var calendarOpen = false
    @State private var settingsOpen = false
    @State private var showCelebration = false
    @State private var mentorNudge: String? = nil

    private static let nudgeMessages = [
        "Well done! 💪", "Keep it up!", "That's the way!", "Proud of you!",
        "One step closer!", "You're crushing it!", "Consistency wins!",
        "Nice work! 🎉", "That's a win!", "Stay the course!",
    ]

    private var todayKey: String { DateKey.key(for: Date()) }
    private var metrics: HabitMetrics { HabitMetrics.compute(for: habits, todayKey: todayKey) }

    private var showMentorCharacter: Bool {
        #if DEBUG
        return true
        #else
        return backend.dashboard?.match != nil
        #endif
    }

    private var showMenteeCharacter: Bool {
        #if DEBUG
        return true
        #else
        return (backend.dashboard?.mentorDashboard.activeMenteeCount ?? 0) > 0
        #endif
    }

    var body: some View {
        ContentViewScaffold(
            colorScheme: colorScheme,
            habits: habits,
            todayKey: todayKey,
            newHabitTitle: $newHabitTitle,
            metrics: metrics,
            backend: backend,
            progressOpen: $progressOpen,
            calendarOpen: $calendarOpen,
            settingsOpen: $settingsOpen,
            showCelebration: showCelebration,
            mentorNudge: $mentorNudge,
            showMentorCharacter: showMentorCharacter,
            showMenteeCharacter: showMenteeCharacter,
            onAddHabit: addHabit,
            onToggleHabit: toggleHabit,
            onDeleteHabit: deleteHabit,
            onSync: syncWithBackend,
            onFindMentor: assignMentor
        )
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

    private func addHabit() {
        let title = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        guard backend.isAuthenticated else {
            backend.errorMessage = "Sign in before adding habits."
            return
        }

        // Optimistic local insert with .pending status
        let localHabit = Habit(title: title, syncStatus: .pending)
        withAnimation { modelContext.insert(localHabit) }
        newHabitTitle = ""

        Task {
            do {
                let remoteHabit = try await backend.createHabit(title: title)
                localHabit.backendId  = remoteHabit.id
                localHabit.syncStatus = .synced
                localHabit.updatedAt  = Date()
                backend.statusMessage = "Habit synced"
                backend.errorMessage  = nil
                await backend.refreshDashboard()
            } catch {
                localHabit.syncStatus = .failed
                backend.errorMessage  = error.localizedDescription
            }
        }
    }

    // MARK: - Full sync (outbox flush → pull → reconcile)

    private func syncWithBackend() {
        guard backend.isAuthenticated else { return }

        Task {
            do {
                try await flushOutbox()
                let remote = try await backend.listHabits()
                applyReconcile(SyncEngine.reconcile(local: habits, remote: remote))
                backend.statusMessage = "Synced with localhost:8080"
                backend.errorMessage  = nil
                await backend.refreshDashboard()
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
                let remote = try await backend.createHabit(title: habit.title)
                habit.backendId  = remote.id
                // Upload any pre-existing checks for this habit
                for dayKey in habit.completedDayKeys {
                    try await backend.setCheck(habitID: remote.id, dateKey: dayKey, done: true)
                }
                habit.syncStatus = .synced
                habit.updatedAt  = Date()
            } catch {
                habit.syncStatus = .failed
                throw error
            }
        }

        // 2. Retry failed habits that already have a backendId (re-push all checks)
        for habit in SyncEngine.failedUploads(in: habits) {
            guard let bid = habit.backendId else { continue }
            do {
                for dayKey in habit.completedDayKeys {
                    try await backend.setCheck(habitID: bid, dateKey: dayKey, done: true)
                }
                habit.syncStatus = .synced
                habit.updatedAt  = Date()
            } catch {
                // Leave as .failed — the badge will invite the user to retry manually
            }
        }
    }

    /// Apply a `ReconcileResult` to SwiftData. Conflict policy: server-wins.
    private func applyReconcile(_ result: SyncEngine.ReconcileResult) {
        for (local, remote) in result.toUpdate {
            // Only overwrite if the local record is synced (not a pending local edit)
            guard local.syncStatus == .synced || local.syncStatus == .failed else { continue }
            local.title             = remote.title
            local.completedDayKeys  = remote.completedDayKeys
            local.syncStatus        = .synced
            local.updatedAt         = Date()
        }
        for remote in result.toInsert {
            modelContext.insert(Habit(
                title: remote.title,
                completedDayKeys: remote.completedDayKeys,
                backendId: remote.id,
                syncStatus: .synced
            ))
        }
        for habit in result.toDelete {
            modelContext.delete(habit)
        }
    }

    // MARK: - Toggle habit

    private func toggleHabit(_ habit: Habit) {
        var keys = habit.completedDayKeys
        let wasUnchecked = !keys.contains(todayKey)
        if let i = keys.firstIndex(of: todayKey) { keys.remove(at: i) } else { keys.append(todayKey) }

        withAnimation(.snappy(duration: 0.2)) {
            habit.completedDayKeys = keys.sorted()
            habit.updatedAt  = Date()
            habit.syncStatus = habit.backendId != nil ? .pending : habit.syncStatus
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

        guard let backendId = habit.backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.setCheck(habitID: backendId, dateKey: todayKey, done: wasUnchecked)
                habit.syncStatus = .synced
                await backend.refreshDashboard()
            } catch {
                habit.syncStatus = .failed
                backend.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Delete habit

    private func deleteHabit(_ habit: Habit) {
        let backendId = habit.backendId

        // Mark for deletion first; actual SwiftData removal happens after server confirms
        if backendId != nil && backend.isAuthenticated {
            habit.syncStatus = .deleted
        }

        withAnimation { modelContext.delete(habit) }

        guard let backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.deleteHabit(habitID: backendId)
                await backend.refreshDashboard()
            } catch {
                backend.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showCelebration = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) { showCelebration = false }
        }
    }

    private func assignMentor() {
        Task { await backend.assignMentor() }
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
