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
/// Single instance, MainActor-isolated. Two configuration entry points:
///
///   1. `bootstrap(container:)` — called from the App's init with the
///      shared `ModelContainer`. Registers the long-running HKObserver
///      queries AND enables HealthKit background delivery so the OS
///      can wake the app when new samples arrive even if Rung is
///      fully closed. Backend is unset here.
///
///   2. `configure(backend:modelContext:)` — called from `ContentView`
///      once the user is authenticated. Adds the backend reference so
///      auto-checks fire `setCheck` over the wire, and re-binds the
///      model context to the live one used by the UI.
///
/// Scans run on:
///   - app appear / sync completion (explicit `scan(habits:)` calls)
///   - HKObserverQuery wakeups (foreground OR background launch)
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
    /// Fallback path to the model store when the OS background-launches
    /// the app for an HK observer wake-up before any UI hands us a live
    /// `modelContext`. Held strongly because the App struct (which owns
    /// the container) outlives this singleton in practice anyway.
    private var container: ModelContainer?
    private var isObserving = false

    private init() {}

    /// First-thing setup called from the App struct's init with the shared
    /// `ModelContainer`. Registers long-running HKObserver queries and
    /// enables HealthKit's background-delivery channel so the OS wakes
    /// the app process whenever a relevant sample arrives — even if the
    /// app is fully closed when the user's watch logs a workout.
    /// Idempotent: subsequent calls are no-ops once observing.
    func bootstrap(container: ModelContainer) {
        self.container = container
        if !isObserving {
            startObservers()
            isObserving = true
        }
    }

    /// Wires the live backend store + UI's model context once the user
    /// is signed in. Idempotent: safe to call on every appear. Will also
    /// kick off observer registration if `bootstrap` somehow didn't run
    /// first (e.g. legacy launch path).
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
        let writeContext = activeContext()
        writeContext?.insert(completion)
        try? writeContext?.save()

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
                try? activeContext()?.save()
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
        let param = habit.effectiveVerificationParam
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
        let writeContext = activeContext()
        writeContext?.insert(completion)
        try? writeContext?.save()

        // No backend yet (background-launch path before the user has
        // logged in, or pre-auth state). The local write is enough; the
        // next `flushOutbox` pass will replay the new dayKey to the
        // server because syncStatus is `.pending`.
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
                try? activeContext()?.save()
            } catch {
                habit.syncStatus = .failed
            }
        }
    }

    /// Registers a long-running `HKObserverQuery` for every sample type
    /// any verifiable canonical habit could query against AND turns on
    /// HealthKit background delivery so the OS wakes the app whenever
    /// new data lands — even if Rung was fully closed at the time.
    ///
    /// Background delivery has zero entitlement cost beyond the regular
    /// HealthKit grant the user already gave at onboarding. The trade-off
    /// is some battery — the app gets relaunched into the background for
    /// each batch of new samples — but Apple throttles this aggressively
    /// so impact is minimal.
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
                    // CRITICAL: must call within ~30s or HK throttles future
                    // wake-ups for this observer. The scan is cheap so we're
                    // well inside the window.
                    completionHandler()
                }
            }
            store.execute(query)
            hkObservers.append(query)

            // Ask HealthKit to relaunch the app whenever new data arrives.
            // `.immediate` is the most aggressive cadence; HK still batches
            // and throttles in practice. We surface failures to the log so
            // misconfigurations (denied auth, low-power-mode quirks,
            // missing entitlement) are visible during debugging instead of
            // silently shipping an app that looks wired but isn't.
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                if let error = error {
                    print("[AutoVerify] Background delivery failed for \(type.identifier): \(error.localizedDescription)")
                } else if !success {
                    print("[AutoVerify] Background delivery returned success=false for \(type.identifier)")
                }
            }
        }
    }

    /// Re-fetches the active habits from SwiftData and reruns scan.
    /// Called from the HKObserverQuery wake handler — we don't have the
    /// caller's habit list at that point, so we go straight to the model
    /// context. The fetch is cheap (a handful of rows).
    private func scanFromObserver() async {
        guard let ctx = activeContext() else { return }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { !$0.isArchived }
        )
        let habits = (try? ctx.fetch(descriptor)) ?? []
        await scan(habits: habits)
    }

    /// Picks the live model context if the UI has one, otherwise falls
    /// back to the bootstrapped container's main context. Background
    /// launches go through the latter path because no view has appeared
    /// to hand us its `@Environment(\.modelContext)` yet.
    private func activeContext() -> ModelContext? {
        if let live = modelContext { return live }
        return container?.mainContext
    }
}
