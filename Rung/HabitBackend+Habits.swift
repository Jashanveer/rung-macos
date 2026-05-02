import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - Reminders (per-habit rich reminder list)

    /// Loads every reminder for `habitID`. Errors propagate so callers
    /// can show a per-screen failure state. The legacy
    /// `Habit.reminderWindow` column is independent of these — they
    /// coexist until clients fully migrate.
    func listHabitReminders(habitID: Int64) async throws -> [HabitReminder] {
        try await habitRepository.listReminders(habitID: habitID)
    }

    /// Creates a new reminder, returns the persisted record.
    func createHabitReminder(habitID: Int64, reminder: HabitReminder) async throws -> HabitReminder {
        try await habitRepository.createReminder(habitID: habitID, reminder: reminder)
    }

    /// Updates an existing reminder. The `id` on `reminder` must match
    /// `reminderID`; the parameter is split out so the call site reads
    /// like the URL.
    func updateHabitReminder(habitID: Int64, reminderID: Int64, reminder: HabitReminder) async throws -> HabitReminder {
        try await habitRepository.updateReminder(habitID: habitID, reminderID: reminderID, reminder: reminder)
    }

    func deleteHabitReminder(habitID: Int64, reminderID: Int64) async throws {
        try await habitRepository.deleteReminder(habitID: habitID, reminderID: reminderID)
    }

    // MARK: - Habits (cache-aware)

    func listHabits() async throws -> [BackendHabit] {
        // Return cached value if still fresh
        if let cached = await responseCache.cachedHabits() {
            habitListRequestState = .success(cached)
            return cached
        }

        habitListRequestState = .loading; refreshSyncingState()
        do {
            let habits = try await habitRepository.listHabits()
            await syncSessionFromClient()
            await responseCache.cacheHabits(habits)
            habitListRequestState = .success(habits)
            errorMessage = nil
            refreshSyncingState()
            return habits
        } catch {
            handleAuthenticatedRequestError(error)
            habitListRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func listTasks() async throws -> [BackendHabit] {
        habitListRequestState = .loading; refreshSyncingState()
        do {
            let tasks = try await habitRepository.listTasks()
            await syncSessionFromClient()
            habitListRequestState = .success(tasks)
            errorMessage = nil
            refreshSyncingState()
            return tasks
        } catch {
            handleAuthenticatedRequestError(error)
            habitListRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    /// LLM frequency-parse fallback. Returns `nil` if the user isn't
    /// authenticated, the network call fails, or the LLM couldn't extract
    /// a cadence. Callers fall through to the user's untouched input on
    /// nil — never block the UX waiting for AI.
    func parseHabitFrequencyWithAI(text: String) async -> ParseFrequencyResult? {
        guard token != nil else { return nil }
        do {
            let result = try await habitRepository.parseHabitFrequency(text: text)
            return result.didMatch ? result : nil
        } catch {
            return nil
        }
    }

    /// Push the local sleep snapshot to the backend so other devices
    /// (notably macOS, where HK isn't available) can read what iOS
    /// computed. Fire-and-forget — failures don't bubble up to the UI.
    func uploadSleepSnapshot(_ snapshot: BackendSleepSnapshot) async {
        guard token != nil else { return }
        _ = try? await sleepSnapshotRepository.upload(snapshot)
    }

    /// Read the most recent server-side snapshot. Used by macOS to
    /// hydrate `SleepInsightsService` when local HK data isn't available.
    /// Returns nil on no-row, network failure, or unauthenticated state.
    func fetchSleepSnapshot() async -> BackendSleepSnapshot? {
        guard token != nil else { return nil }
        return try? await sleepSnapshotRepository.fetch()
    }

    func createHabit(
        title: String,
        reminderWindow: String? = nil,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) async throws -> BackendHabit {
        createHabitRequestState = .loading; refreshSyncingState()
        do {
            let habit = try await habitRepository.createHabit(
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
            await syncSessionFromClient()
            await responseCache.invalidateHabits()   // force re-fetch on next list
            createHabitRequestState = .success(habit)
            errorMessage = nil
            refreshSyncingState()
            return habit
        } catch {
            handleAuthenticatedRequestError(error)
            createHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func createTask(title: String) async throws -> BackendHabit {
        createHabitRequestState = .loading; refreshSyncingState()
        do {
            let task = try await habitRepository.createTask(title: title)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            createHabitRequestState = .success(task)
            errorMessage = nil
            refreshSyncingState()
            return task
        } catch {
            handleAuthenticatedRequestError(error)
            createHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func updateHabit(
        habitID: Int64,
        title: String,
        reminderWindow: String?,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) async throws -> BackendHabit {
        updateHabitRequestState = .loading; refreshSyncingState()
        do {
            let habit = try await habitRepository.updateHabit(
                habitID: habitID,
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            updateHabitRequestState = .success(habit)
            errorMessage = nil
            refreshSyncingState()
            return habit
        } catch {
            handleAuthenticatedRequestError(error)
            updateHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func updateTask(taskID: Int64, title: String) async throws -> BackendHabit {
        updateHabitRequestState = .loading; refreshSyncingState()
        do {
            let task = try await habitRepository.updateTask(taskID: taskID, title: title)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            updateHabitRequestState = .success(task)
            errorMessage = nil
            refreshSyncingState()
            return task
        } catch {
            handleAuthenticatedRequestError(error)
            updateHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func setCheck(
        habitID: Int64,
        dateKey: String,
        done: Bool,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        durationSeconds: Int? = nil
    ) async throws {
        checkUpdateRequestState = .loading; refreshSyncingState()
        do {
            _ = try await habitRepository.setCheck(
                habitID: habitID, dateKey: dateKey, done: done,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                durationSeconds: durationSeconds
            )
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            await responseCache.invalidateDashboard()
            checkUpdateRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            checkUpdateRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func setTaskCheck(
        taskID: Int64,
        dateKey: String,
        done: Bool,
        durationSeconds: Int? = nil
    ) async throws {
        checkUpdateRequestState = .loading; refreshSyncingState()
        do {
            _ = try await habitRepository.setTaskCheck(
                taskID: taskID, dateKey: dateKey, done: done,
                durationSeconds: durationSeconds
            )
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            await responseCache.invalidateDashboard()
            checkUpdateRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            checkUpdateRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

}
