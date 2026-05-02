import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - Verification

    /// Runs HealthKit (or other external-signal) verification for a freshly
    /// toggled-done habit and persists the resulting `HabitCompletion` record.
    ///
    /// Intentionally separate from `setCheck` so the server round-trip and the
    /// verification round-trip run independently — neither blocks the other,
    /// and a HealthKit auth denial never prevents a check from syncing.
    ///
    /// Callers should fire this fire-and-forget from their toggle path
    /// (usually inside the same Task that runs `setCheck`), only when `done`
    /// is transitioning false→true. Replays from the sync outbox should skip
    /// this — verification already ran the first time the user toggled.
    func verifyCompletion(habit: Habit, dayKey: String, modelContext: ModelContext) async {
        guard let source = habit.verificationSource, source != .selfReport else { return }
        // Snapshot primitives off the @Model before crossing into the
        // VerificationService actor so we don't pass a non-Sendable Habit
        // across the boundary.
        let backendId = habit.backendId
        let tier = habit.verificationTier
        let param = habit.verificationParam
        // Seed a stable UUID on the habit the first time we verify it so
        // evidence records can be reconciled to this habit before its
        // backendId exists. On subsequent calls we return the same UUID.
        let localId = habit.ensureLocalUUID()

        let completion = await VerificationService.shared.verify(
            habitBackendId: backendId,
            habitLocalId: localId,
            source: source,
            tier: tier,
            param: param,
            dayKey: dayKey
        )

        modelContext.insert(completion)
        try? modelContext.save()
    }

    func deleteHabit(habitID: Int64) async throws {
        deleteHabitRequestState = .loading; refreshSyncingState()
        do {
            try await habitRepository.deleteHabit(habitID: habitID)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            deleteHabitRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            deleteHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func deleteTask(taskID: Int64) async throws {
        deleteHabitRequestState = .loading; refreshSyncingState()
        do {
            try await habitRepository.deleteTask(taskID: taskID)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            deleteHabitRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            deleteHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

}
