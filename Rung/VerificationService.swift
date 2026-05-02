import Foundation
import HealthKit

/// Runs HealthKit queries to confirm that a habit completion actually happened.
/// Called after `HabitBackendStore.setCheck(...)` succeeds — never blocks the
/// toggle flow, and never fails loudly. If authorization is denied or no
/// supporting sample exists, the completion is recorded as `.selfReport` so
/// the user still gets credit (just at the base point rate).
///
/// Actor-isolated so the HKHealthStore access is serialized — HealthKit
/// itself is thread-safe, but serializing here keeps query reasoning simple.
actor VerificationService {
    static let shared = VerificationService()

    private let store = HKHealthStore()

    /// All HealthKit sample types we need read access to. Passed to
    /// `requestAuthorization` in one batch so the user sees a single permission
    /// sheet at onboarding rather than one per habit.
    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .bodyMass, .dietaryWater, .numberOfAlcoholicBeverages
        ]
        for id in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }

        let categoryIdentifiers: [HKCategoryTypeIdentifier] = [
            .mindfulSession, .sleepAnalysis
        ]
        for id in categoryIdentifiers {
            if let type = HKCategoryType.categoryType(forIdentifier: id) {
                types.insert(type)
            }
        }

        return types
    }

    /// Requests read access to every HealthKit sample type verification uses.
    /// Safe to call repeatedly — HealthKit coalesces repeated authorization
    /// requests for types the user already answered. Returns silently on
    /// platforms where HealthKit is unavailable.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Verifies a completion and returns a `HabitCompletion` describing what
    /// tier was awarded. Never throws — any error (HK unavailable, auth
    /// denied, no matching sample, malformed `dayKey`) resolves to a
    /// `.selfReport` completion so the caller can persist it unconditionally.
    ///
    /// - Parameters:
    ///   - habitBackendId: server-side id; nil if habit hasn't synced yet
    ///   - habitLocalId: stable local id for the parent habit
    ///   - source: which HK signal to query
    ///   - tier: tier to award if the query succeeds (`.selfReport` is the
    ///     fallback if the query fails or turns up nothing)
    ///   - param: threshold / activity type — semantics per source
    ///   - dayKey: `"yyyy-MM-dd"` day to verify against
    func verify(
        habitBackendId: Int64?,
        habitLocalId: UUID,
        source: VerificationSource,
        tier: VerificationTier,
        param: Double?,
        dayKey: String
    ) async -> HabitCompletion {
        let fallback = HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: .selfReport,
            awardedTier: .selfReport
        )

        guard HKHealthStore.isHealthDataAvailable(),
              let bounds = Self.dayBounds(for: dayKey) else {
            return fallback
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: bounds.start, end: bounds.end
        )

        do {
            switch source {
            case .healthKitWorkout:
                return try await verifyWorkout(
                    predicate: predicate, targetTypeRaw: param.map { UInt($0) },
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitSteps:
                return try await verifyQuantityThreshold(
                    identifier: .stepCount, unit: .count(),
                    threshold: param ?? 0, predicate: predicate,
                    awardSource: .healthKitSteps,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitMindful:
                return try await verifyCategoryDuration(
                    identifier: .mindfulSession,
                    minMinutes: param ?? 0, predicate: predicate,
                    awardSource: .healthKitMindful,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitSleep:
                return try await verifySleep(
                    minHours: param ?? 0, predicate: predicate,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitBodyMass:
                return try await verifyAnySample(
                    identifier: .bodyMass, predicate: predicate,
                    awardSource: .healthKitBodyMass,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitHydration:
                return try await verifyQuantityThreshold(
                    identifier: .dietaryWater, unit: HKUnit.literUnit(with: .milli),
                    threshold: param ?? 0, predicate: predicate,
                    awardSource: .healthKitHydration,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .healthKitNoAlcohol:
                return try await verifyZeroAlcohol(
                    predicate: predicate,
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
            case .screenTimeSocial:
                #if os(iOS)
                return await verifyScreenTimeSocial(
                    habitBackendId: habitBackendId, habitLocalId: habitLocalId,
                    dayKey: dayKey, tier: tier, fallback: fallback
                )
                #else
                return fallback
                #endif
            case .selfReport:
                return fallback
            }
        } catch {
            return fallback
        }
    }

    // MARK: - Individual verifiers

    private func verifyWorkout(
        predicate: NSPredicate,
        targetTypeRaw: UInt?,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        let samples: [HKSample] = try await sampleQuery(
            type: HKObjectType.workoutType(), predicate: predicate
        )
        let match = samples.compactMap { $0 as? HKWorkout }.first { workout in
            guard let targetTypeRaw else { return true }
            return workout.workoutActivityType.rawValue == targetTypeRaw
        }
        guard let workout = match else { return fallback }
        let evidence = Self.workoutEvidence(workout)
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: .healthKitWorkout,
            awardedTier: tier,
            evidenceJSON: evidence
        )
    }

    private func verifyQuantityThreshold(
        identifier: HKQuantityTypeIdentifier, unit: HKUnit,
        threshold: Double, predicate: NSPredicate,
        awardSource: VerificationSource,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return fallback
        }
        let total = try await statisticsSum(type: type, predicate: predicate, unit: unit)
        guard total >= threshold else { return fallback }
        let evidence = Self.encode(["total": total, "threshold": threshold])
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: awardSource,
            awardedTier: tier,
            evidenceJSON: evidence
        )
    }

    private func verifyCategoryDuration(
        identifier: HKCategoryTypeIdentifier,
        minMinutes: Double, predicate: NSPredicate,
        awardSource: VerificationSource,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else {
            return fallback
        }
        let samples = try await sampleQuery(type: type, predicate: predicate)
        let totalMinutes = samples.reduce(0.0) { acc, sample in
            acc + sample.endDate.timeIntervalSince(sample.startDate) / 60
        }
        guard totalMinutes >= minMinutes else { return fallback }
        let evidence = Self.encode(["minutes": totalMinutes, "threshold": minMinutes])
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: awardSource,
            awardedTier: tier,
            evidenceJSON: evidence
        )
    }

    private func verifySleep(
        minHours: Double, predicate: NSPredicate,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return fallback
        }
        let samples = try await sampleQuery(type: type, predicate: predicate)
        // Sum any "asleep" bucket — HealthKit defines multiple (core, deep,
        // REM) plus the legacy `.asleep` on older platforms. Anything that
        // isn't `.inBed` or `.awake` counts.
        let sleepSeconds = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { sample in
                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                switch value {
                case .inBed, .awake, .none: return false
                default: return true
                }
            }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let hours = sleepSeconds / 3600
        guard hours >= minHours else { return fallback }
        let evidence = Self.encode(["hours": hours, "threshold": minHours])
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: .healthKitSleep,
            awardedTier: tier,
            evidenceJSON: evidence
        )
    }

    private func verifyAnySample(
        identifier: HKQuantityTypeIdentifier, predicate: NSPredicate,
        awardSource: VerificationSource,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return fallback
        }
        let samples = try await sampleQuery(type: type, predicate: predicate)
        guard !samples.isEmpty else { return fallback }
        let evidence = Self.encode(["sampleCount": samples.count])
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: awardSource,
            awardedTier: tier,
            evidenceJSON: evidence
        )
    }

    /// "No alcohol" is the inverse of the other verifiers — the *absence* of
    /// samples is what earns the tier. If HealthKit has zero alcoholic-beverage
    /// samples for the day, award. If any sample exists, fall back to
    /// self-report (we can't prove the negative without the user's cooperation).
    private func verifyZeroAlcohol(
        predicate: NSPredicate,
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async throws -> HabitCompletion {
        guard let type = HKQuantityType.quantityType(forIdentifier: .numberOfAlcoholicBeverages) else {
            return fallback
        }
        let total = try await statisticsSum(type: type, predicate: predicate, unit: .count())
        guard total == 0 else { return fallback }
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: .healthKitNoAlcohol,
            awardedTier: tier,
            evidenceJSON: Self.encode(["drinks": 0])
        )
    }

    #if os(iOS)
    /// Awards the canonical tier when ScreenTime monitoring is active and
    /// the user did not cross the daily threshold for `dayKey`. Anything
    /// else — monitoring off, no app selection, threshold exceeded — falls
    /// back to `.selfReport` because we can't honestly verify abstinence.
    /// Reading `ScreenTimeService` requires hopping to the main actor so
    /// the flag write/read pair stays serialized with the picker UI.
    private func verifyScreenTimeSocial(
        habitBackendId: Int64?, habitLocalId: UUID, dayKey: String,
        tier: VerificationTier, fallback: HabitCompletion
    ) async -> HabitCompletion {
        let (isMonitoring, overLimit) = await MainActor.run {
            (
                ScreenTimeService.shared.isMonitoring,
                ScreenTimeService.shared.wasOverLimit(on: dayKey)
            )
        }
        guard isMonitoring, !overLimit else { return fallback }
        return HabitCompletion(
            habitBackendId: habitBackendId,
            habitLocalId: habitLocalId,
            dayKey: dayKey,
            verifiedBySource: .screenTimeSocial,
            awardedTier: tier,
            evidenceJSON: Self.encode(["underLimit": true])
        )
    }
    #endif

    // MARK: - HealthKit bridging

    /// Wraps `HKSampleQuery` in async. Returns all samples matching `predicate`,
    /// ordered newest-first. Query limit is deliberately high (`HKObjectQueryNoLimit`)
    /// because we already scope by day via the predicate.
    private func sampleQuery(
        type: HKSampleType, predicate: NSPredicate
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Wraps `HKStatisticsQuery` in async, summing a quantity type over
    /// `predicate`. Returns 0 when no samples exist (rather than throwing),
    /// which is the correct answer for "did you hit your step threshold".
    private func statisticsSum(
        type: HKQuantityType, predicate: NSPredicate, unit: HKUnit
    ) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Helpers

    private static func dayBounds(for dayKey: String) -> (start: Date, end: Date)? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: dayKey) else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }

    private static func workoutEvidence(_ workout: HKWorkout) -> Data? {
        encode([
            "uuid": workout.uuid.uuidString,
            "activityType": workout.workoutActivityType.rawValue,
            "durationSeconds": workout.duration,
            "startDate": workout.startDate.timeIntervalSince1970
        ])
    }

    private static func encode(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }
}
