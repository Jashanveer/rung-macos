import Foundation
import HealthKit
import SwiftData

/// Watches HealthKit (and Screen Time on iOS) for evidence of the user
/// actually doing their verifiable habits, and auto-marks them done when
/// the evidence shows up. Eliminates the manual-toggle cheat path: users
/// with a verifiable habit literally cannot tap-to-check it themselves.
///
/// The escape hatch for honest users whose evidence didn't make it into
/// HealthKit (ran without their watch, gym app didn't sync, etc.) is the
/// long-press "Mark done manually" option in `HabitCard`'s context menu.
/// Manual overrides record the completion at `.selfReport` tier so the
/// leaderboard's anti-cheat cost is preserved.
///
/// Single instance, MainActor-isolated. Configure once from the root view
/// with the active `HabitBackendStore` + `ModelContext`, then drive scans
/// from:
///   - app appear / sync completion (explicit `scan(habits:)` calls)
///   - HKObserverQuery wakeups while the app is foregrounded
///   - scenePhase transitions to `.active`
@MainActor
final class AutoVerificationCoordinator {
    static let shared = AutoVerificationCoordinator()

    private let store = HKHealthStore()
    /// Long-running HealthKit observer queries. Held so they don't get
    /// torn down by ARC; never inspected directly.
    private var hkObservers: [HKQuery] = []
    private weak var backend: HabitBackendStore?
    private weak var modelContext: ModelContext?
    private var isObserving = false

    private init() {}

    /// Wires up the coordinator with the running backend store + model
    /// context, and starts the HealthKit observer queries on first call.
    /// Idempotent: subsequent calls just refresh the references — observers
    /// are kept active across the app's lifetime so a foreground app
    /// reacts to new HK samples within seconds.
    func configure(backend: HabitBackendStore, modelContext: ModelContext) {
        self.backend = backend
        self.modelContext = modelContext
        if !isObserving {
            startObservers()
            isObserving = true
        }
    }

    /// Scans every auto-verified habit in `habits` and tries to auto-check
    /// it for the appropriate day. HealthKit habits look at today (samples
    /// can land any time on the day); Screen Time habits look at yesterday
    /// because today's threshold isn't decided until end-of-day.
    func scan(habits: [Habit]) async {
        let today = DateKey.key(for: Date())
        let yesterday = DateKey.key(for: DateKey.addDays(Date(), -1))
        for habit in habits where habit.isAutoVerified {
            guard let source = habit.verificationSource else { continue }
            let dayKey: String
            switch source {
            case .screenTimeSocial: dayKey = yesterday
            default: dayKey = today
            }
            guard !habit.completedDayKeys.contains(dayKey) else { continue }
            await tryAutoCheck(habit: habit, dayKey: dayKey)
        }
    }

    /// Honest-user escape hatch — marks a verifiable habit done despite
    /// HealthKit not having the evidence (ran without the watch, etc.).
    /// Always records at `.selfReport` tier so the user pays the
    /// tier-weighted leaderboard cost; gaming the manual override doesn't
    /// give them the same score as actually doing the activity.
    func manualOverride(habit: Habit, dayKey: String) async {
        guard !habit.completedDayKeys.contains(dayKey) else { return }
        let backendId = habit.backendId
        let localId = habit.ensureLocalUUID()
        habit.completedDayKeys.append(dayKey)
        habit.updatedAt = Date()
        habit.syncStatus = .pending

        let completion = HabitCompletion(
            habitBackendId: backendId,
            habitLocalId: localId,
            dayKey: dayKey,
            verifiedBySource: .selfReport,
            awardedTier: .selfReport
        )
        modelContext?.insert(completion)
        try? modelContext?.save()

        guard let bid = backendId, let store = backend, store.isAuthenticated else { return }
        Task {
            do {
                try await store.setCheck(
                    habitID: bid,
                    dateKey: dayKey,
                    done: true,
                    verificationTier: VerificationTier.selfReport.rawValue,
                    verificationSource: VerificationSource.selfReport.rawValue
                )
                habit.syncStatus = .synced
                try? modelContext?.save()
            } catch {
                habit.syncStatus = .failed
            }
        }
    }

    // MARK: - Internal

    private func tryAutoCheck(habit: Habit, dayKey: String) async {
        guard let source = habit.verificationSource else { return }
        let backendId = habit.backendId
        let tier = habit.verificationTier
        let param = habit.verificationParam
        let localId = habit.ensureLocalUUID()

        let completion = await VerificationService.shared.verify(
            habitBackendId: backendId,
            habitLocalId: localId,
            source: source,
            tier: tier,
            param: param,
            dayKey: dayKey
        )
        // `verify` returns `.selfReport` whenever the underlying query
        // came up empty (no sample, auth denied, threshold not met). Only
        // a non-selfReport source means we have real evidence — that's
        // the only case where we auto-check.
        guard completion.verifiedBySource != .selfReport else { return }

        habit.completedDayKeys.append(dayKey)
        habit.updatedAt = Date()
        habit.syncStatus = .pending
        modelContext?.insert(completion)
        try? modelContext?.save()

        guard let bid = backendId, let store = backend, store.isAuthenticated else { return }
        Task {
            do {
                try await store.setCheck(
                    habitID: bid,
                    dateKey: dayKey,
                    done: true,
                    verificationTier: tier.rawValue,
                    verificationSource: source.rawValue
                )
                habit.syncStatus = .synced
                try? modelContext?.save()
            } catch {
                habit.syncStatus = .failed
            }
        }
    }

    /// Registers a long-running `HKObserverQuery` for every sample type
    /// any verifiable canonical habit could query against. The observer
    /// fires on the main actor whenever a relevant sample is added — we
    /// rescan all habits at that point so a workout logged in the Fitness
    /// app shows up as a check within seconds while the user is in Forma.
    private func startObservers() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        var types: [HKSampleType] = [HKObjectType.workoutType()]
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .stepCount, .bodyMass, .dietaryWater, .numberOfAlcoholicBeverages
        ]
        for id in quantityIDs {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.append(t) }
        }
        let categoryIDs: [HKCategoryTypeIdentifier] = [.mindfulSession, .sleepAnalysis]
        for id in categoryIDs {
            if let t = HKCategoryType.categoryType(forIdentifier: id) { types.append(t) }
        }

        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
                guard let self else { completionHandler(); return }
                Task { @MainActor in
                    await self.scanFromObserver()
                    completionHandler()
                }
            }
            store.execute(query)
            hkObservers.append(query)
        }
    }

    /// Re-fetches the active habits from SwiftData and reruns scan.
    /// Called from the HKObserverQuery wake handler — we don't have the
    /// caller's habit list at that point, so we go straight to the model
    /// context. The fetch is cheap (a handful of rows).
    private func scanFromObserver() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { !$0.isArchived }
        )
        let habits = (try? ctx.fetch(descriptor)) ?? []
        await scan(habits: habits)
    }
}
