import Foundation
import Combine
import HealthKit

/// Owns the live `HKWorkoutSession` + `HKLiveWorkoutBuilder` lifecycle for
/// watch-led workouts. The user taps "Start workout" on a cardio habit row,
/// the watch begins a session here, and the iPhone-side
/// `AutoVerificationCoordinator` picks up the saved workout the next time
/// `HKObserverQuery` fires (or the user foregrounds the app).
///
/// Why watch-led matters: the iPhone-tap-then-toggle path the rest of Rung
/// uses captures *intent* but not duration, heart rate, or active-energy
/// samples. A watch-initiated workout writes a real `HKWorkout` with all of
/// that, so the habit becomes auto-verified the moment the user ends the
/// session — no honor-system fallback, no separate gym app.
@MainActor
final class WatchWorkoutController: NSObject, ObservableObject {

    static let shared = WatchWorkoutController()

    /// Backed by `HKHealthStore`. Created lazily so the watch process
    /// doesn't pay the bring-up cost until the user actually opens the
    /// workout flow.
    private let healthStore = HKHealthStore()

    /// Live session — nil when no workout is active.
    private var session: HKWorkoutSession?
    /// Companion builder — collects samples while the session runs.
    private var builder: HKLiveWorkoutBuilder?

    /// Fires on each builder update so SwiftUI views can refresh elapsed
    /// time, heart-rate, and active-energy readouts. Published as a date
    /// so the view can re-derive elapsed seconds on every tick.
    @Published private(set) var lastUpdate: Date = Date()
    /// Latest heart rate (bpm) sample. Nil until the first reading lands.
    @Published private(set) var heartRateBPM: Double?
    /// Active energy burned so far (kcal). 0 until the first sample.
    @Published private(set) var activeEnergyKCal: Double = 0
    /// `nil` when no workout is running. When set, drives the view's
    /// timer label and the "End" button availability.
    @Published private(set) var startedAt: Date?
    /// `true` while we're waiting for the system to confirm the session
    /// ended and the workout was saved.
    @Published private(set) var isFinishing: Bool = false

    /// Last error surfaced to the UI. Cleared the next time a session
    /// starts. Nil when nothing went wrong.
    @Published private(set) var lastError: String?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start a workout for `habitCanonicalKey` ("workout", "run", "cycle",
    /// "swim", "yoga"). Requests HK authorisation if needed; bails with
    /// `lastError` populated if the user denied or the device doesn't
    /// support workouts. The shared controller serialises sessions —
    /// calling start while one is live is a no-op.
    func start(canonicalKey: String) async {
        guard session == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "Health data isn't available on this device."
            return
        }

        let activityType = Self.activityType(for: canonicalKey)
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            lastError = "Health authorisation failed: \(error.localizedDescription)"
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = (canonicalKey == "swim") ? .unknown : .outdoor

        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            newSession.delegate = self
            newBuilder.delegate = self

            let now = Date()
            newSession.startActivity(with: now)
            try await newBuilder.beginCollection(at: now)

            self.session = newSession
            self.builder = newBuilder
            self.startedAt = now
            self.lastUpdate = now
            self.heartRateBPM = nil
            self.activeEnergyKCal = 0
            self.lastError = nil
            self.isFinishing = false
        } catch {
            lastError = "Couldn't start workout: \(error.localizedDescription)"
            session = nil
            builder = nil
            startedAt = nil
        }
    }

    /// End the live session, persist the resulting `HKWorkout` to the
    /// store, and reset published state. Idempotent — calling end without
    /// an active session is a no-op.
    func end() {
        guard let session, let builder else { return }
        isFinishing = true
        let endedAt = Date()
        session.end()
        builder.endCollection(withEnd: endedAt) { [weak self] _, _ in
            builder.finishWorkout { _, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = "Couldn't save workout: \(error.localizedDescription)"
                    }
                    self.session = nil
                    self.builder = nil
                    self.startedAt = nil
                    self.isFinishing = false
                }
            }
        }
    }

    /// Cancel without saving — used if the user backs out before a real
    /// workout begins. Discards collected samples and resets state.
    func cancel() {
        guard let session = session, let builder = builder else { return }
        session.end()
        builder.discardWorkout()
        self.session = nil
        self.builder = nil
        self.startedAt = nil
        self.isFinishing = false
    }

    // MARK: - Mapping

    /// Map a Rung canonical key to the closest `HKWorkoutActivityType`.
    /// Anything we don't understand falls back to `.other`, which still
    /// produces a saved workout — auto-verification will accept it as
    /// generic exercise rather than dropping the credit.
    static func activityType(for canonicalKey: String) -> HKWorkoutActivityType {
        switch canonicalKey {
        case "run":     return .running
        case "walk":    return .walking
        case "workout": return .traditionalStrengthTraining
        case "cycle":   return .cycling
        case "swim":    return .swimming
        case "yoga":    return .yoga
        default:        return .other
        }
    }

    /// Static check the row UI uses to decide whether to show "Start
    /// workout" instead of the crown-counter. Anything mapping to a
    /// non-`.other` activity counts.
    static func supports(canonicalKey: String?) -> Bool {
        guard let canonicalKey else { return false }
        switch canonicalKey {
        case "run", "walk", "workout", "cycle", "swim", "yoga":
            return true
        default:
            return false
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // No-op for now — state transitions are reflected via the
        // builder's onCollect callback. Hook here later if we want a
        // "paused" UI state without re-querying the session.
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.lastError = "Workout session error: \(error.localizedDescription)"
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor [weak self] in
            self?.lastUpdate = Date()
        }
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let stats = workoutBuilder.statistics(for: quantityType)
            switch quantityType {
            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = stats?.mostRecentQuantity()?.doubleValue(for: unit)
                Task { @MainActor [weak self] in
                    if let bpm { self?.heartRateBPM = bpm }
                    self?.lastUpdate = Date()
                }
            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                Task { @MainActor [weak self] in
                    self?.activeEnergyKCal = kcal
                    self?.lastUpdate = Date()
                }
            default:
                break
            }
        }
    }
}
