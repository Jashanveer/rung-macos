import Foundation
import SwiftData

/// Per-completion evidence record. One of these is written every time a user
/// toggles a habit done; its presence alongside `Habit.completedDayKeys` is
/// what lets the leaderboard distinguish HealthKit-verified checks from
/// honor-system ones.
///
/// Design notes:
/// - `Habit.completedDayKeys: [String]` remains the source of truth for
///   "is this habit done today". This record sits *alongside* it and carries
///   only the verification metadata, never the toggle state itself.
/// - We store the backend id and a local UUID both, so verification records
///   created while offline (before a backend id exists) can be reconciled
///   once the parent `Habit` is synced.
/// - Raw strings back the enums so SwiftData can persist them directly and
///   the schema is forward-compatible with new verification sources.
@Model
final class HabitCompletion {
    /// Matches `Habit.backendId`. Nil while the parent habit hasn't been
    /// synced to the server yet — `habitLocalId` is the stable fallback.
    var habitBackendId: Int64?

    /// Stable local identifier for the parent habit. Mirrors the SwiftData
    /// `persistentModelID` at creation time so we can reconnect a completion
    /// to its habit even before the first sync round-trip.
    var habitLocalId: UUID

    /// `"yyyy-MM-dd"` day key this completion covers. Matches the format used
    /// in `Habit.completedDayKeys` so records can be joined by (habit, dayKey).
    var dayKey: String

    /// Raw `VerificationSource` of the signal that corroborated the check,
    /// or `selfReport` when no signal was available / permission was denied.
    var verifiedBySourceRaw: String

    /// Raw `VerificationTier` awarded. Captured at the moment of award so
    /// historical records stay accurate even if the canonical habit's tier
    /// is later downgraded or upgraded.
    var awardedTierRaw: String

    /// Opaque JSON blob of supporting evidence — HKSample UUIDs, workout
    /// duration/distance, step count reached, sleep hours, etc. Shape varies
    /// per `verifiedBySource`; decoders live next to each verification query.
    /// Not used for server-side validation yet (Phase 2).
    var evidenceJSON: Data?

    /// When the verification attempt finished (not the activity itself).
    var createdAt: Date

    /// Seconds the user spent completing the habit, when the client knows
    /// it. Currently populated only by Focus Mode sessions that ended with
    /// the user toggling the same task done. Nil for plain manual toggles.
    var durationSeconds: Int?

    init(
        habitBackendId: Int64? = nil,
        habitLocalId: UUID,
        dayKey: String,
        verifiedBySource: VerificationSource = .selfReport,
        awardedTier: VerificationTier = .selfReport,
        evidenceJSON: Data? = nil,
        createdAt: Date = Date(),
        durationSeconds: Int? = nil
    ) {
        self.habitBackendId = habitBackendId
        self.habitLocalId = habitLocalId
        self.dayKey = dayKey
        self.verifiedBySourceRaw = verifiedBySource.rawValue
        self.awardedTierRaw = awardedTier.rawValue
        self.evidenceJSON = evidenceJSON
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }

    /// Typed accessor for `verifiedBySourceRaw`; unknown raw values fall back
    /// to `.selfReport` so a forward-compatible client doesn't crash on a
    /// source introduced by a newer build.
    var verifiedBySource: VerificationSource {
        get { VerificationSource(rawValue: verifiedBySourceRaw) ?? .selfReport }
        set { verifiedBySourceRaw = newValue.rawValue }
    }

    /// Typed accessor for `awardedTierRaw`.
    var awardedTier: VerificationTier {
        get { VerificationTier(rawValue: awardedTierRaw) ?? .selfReport }
        set { awardedTierRaw = newValue.rawValue }
    }
}
