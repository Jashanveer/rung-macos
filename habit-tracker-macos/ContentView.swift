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
        "Well done! 💪",
        "Keep it up!",
        "That's the way!",
        "Proud of you!",
        "One step closer!",
        "You're crushing it!",
        "Consistency wins!",
        "Nice work! 🎉",
        "That's a win!",
        "Stay the course!",
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
        // Register APNs device token with the backend when received from AppDelegate.
        .onReceive(NotificationCenter.default.publisher(for: .apnsTokenReceived)) { note in
            guard let token = note.object as? Data else { return }
            Task { await backend.registerDeviceToken(token) }
        }
        // Show in-app nudge banner when a remote notification arrives while the app is open.
        .onReceive(NotificationCenter.default.publisher(for: .apnsNudgeReceived)) { note in
            guard let message = note.object as? String else { return }
            mentorNudge = message
        }
    }

    private func addHabit() {
        let title = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        guard backend.isAuthenticated else {
            backend.errorMessage = "Sign in before adding habits."
            return
        }

        Task {
            do {
                let remoteHabit = try await backend.createHabit(title: title)
                await MainActor.run {
                    withAnimation {
                        upsert(remoteHabit)
                        newHabitTitle = ""
                    }
                    backend.statusMessage = "Habit synced"
                    backend.errorMessage = nil
                }
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func syncWithBackend() {
        guard backend.isAuthenticated else { return }

        Task {
            do {
                try await uploadUnsyncedLocalHabits()
                let remoteHabits = try await backend.listHabits()
                await MainActor.run {
                    merge(remoteHabits)
                    backend.statusMessage = "Synced with localhost:8080"
                    backend.errorMessage = nil
                }
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uploadUnsyncedLocalHabits() async throws {
        let unsynced = habits.filter { $0.backendId == nil }
        for habit in unsynced {
            let remoteHabit = try await backend.createHabit(title: habit.title)
            habit.backendId = remoteHabit.id

            for dayKey in habit.completedDayKeys {
                try await backend.setCheck(habitID: remoteHabit.id, dateKey: dayKey, done: true)
            }
        }
    }

    private func merge(_ remoteHabits: [BackendHabit]) {
        let remoteIDs = Set(remoteHabits.map(\.id))

        for remoteHabit in remoteHabits {
            upsert(remoteHabit)
        }

        for habit in habits {
            guard let backendId = habit.backendId, !remoteIDs.contains(backendId) else { continue }
            modelContext.delete(habit)
        }
    }

    private func upsert(_ remoteHabit: BackendHabit) {
        if let existing = habits.first(where: { $0.backendId == remoteHabit.id }) {
            existing.title = remoteHabit.title
            existing.completedDayKeys = remoteHabit.completedDayKeys
        } else {
            modelContext.insert(Habit(
                title: remoteHabit.title,
                completedDayKeys: remoteHabit.completedDayKeys,
                backendId: remoteHabit.id
            ))
        }
    }

    private func toggleHabit(_ habit: Habit) {
        var keys = habit.completedDayKeys
        let wasUnchecked = !keys.contains(todayKey)
        if let index = keys.firstIndex(of: todayKey) {
            keys.remove(at: index)
        } else {
            keys.append(todayKey)
        }

        withAnimation(.snappy(duration: 0.2)) {
            habit.completedDayKeys = keys.sorted()
        }

        if wasUnchecked && showMentorCharacter {
            mentorNudge = Self.nudgeMessages.randomElement()
        }

        if wasUnchecked && habits.count > 1 {
            let doneAfter = habits.filter { h in
                if h.id == habit.id {
                    return keys.contains(todayKey)
                }
                return h.completedDayKeys.contains(todayKey)
            }.count
            if doneAfter == habits.count {
                triggerCelebration()
            }
        }

        guard let backendId = habit.backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.setCheck(habitID: backendId, dateKey: todayKey, done: wasUnchecked)
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCelebration = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showCelebration = false
            }
        }
    }

    private func deleteHabit(_ habit: Habit) {
        let backendId = habit.backendId
        withAnimation {
            modelContext.delete(habit)
        }

        guard let backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.deleteHabit(habitID: backendId)
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func assignMentor() {
        Task {
            await backend.assignMentor()
        }
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
