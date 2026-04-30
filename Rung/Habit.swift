import Foundation
import SwiftData

/// Tracks whether a local habit record reflects the server state.
/// Stored as a String raw value so SwiftData can persist it directly.
enum SyncStatus: String, Codable {
    /// Local record matches the last known server state.
    case synced
    /// A local change (toggle, create, title edit) hasn't been uploaded yet.
    case pending
    /// The last upload attempt failed; the app will retry on the next sync.
    case failed
    /// Marked for server deletion but the DELETE hasn't been confirmed yet.
    case deleted
}

enum HabitEntryType: String, Codable, CaseIterable, Identifiable {
    case task
    case habit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task:
            return "Task"
        case .habit:
            return "Habit"
        }
    }

    var systemImage: String {
        switch self {
        case .task:
            return "checklist"
        case .habit:
            return "flame.fill"
        }
    }
}

/// Task priority — three buckets so users can quickly triage without
/// agonising over fine-grained ordering. Stored as a raw String so
/// SwiftData can persist it directly and a forward-compatible client
/// never crashes on an unknown future case.
enum TaskPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var systemImage: String {
        switch self {
        case .low:    return "arrow.down.circle.fill"
        case .medium: return "minus.circle.fill"
        case .high:   return "exclamationmark.circle.fill"
        }
    }

    /// Numeric weight used for sorting (higher first). Nil priority sorts
    /// after `.low` so unprioritised tasks fall to the bottom by default.
    var sortWeight: Int {
        switch self {
        case .low:    return 1
        case .medium: return 2
        case .high:   return 3
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortWeight < rhs.sortWeight
    }
}

/// How confidently a habit's completion can be verified against a trusted data source.
/// Drives point multipliers on the leaderboard so self-reported checks can't out-earn
/// checks backed by HealthKit or Screen Time evidence.
enum VerificationTier: String, Codable {
    /// HealthKit / DeviceActivity confirms the activity happened.
    case auto
    /// Some evidence available (hydration log, food diary) but not strictly provable.
    case partial
    /// Honor-system only — no automatic verification possible.
    case selfReport
}

/// Identifies which external signal to consult when verifying a completion.
/// `verificationParam` on the Habit holds the threshold/activity-type for the query
/// (steps count, sleep hours, workout activity type, etc.).
enum VerificationSource: String, Codable {
    case healthKitWorkout          // HKWorkout of a specific activity type
    case healthKitSteps            // HKQuantityTypeIdentifier.stepCount threshold
    case healthKitMindful          // HKCategoryTypeIdentifier.mindfulSession
    case healthKitSleep            // HKCategoryTypeIdentifier.sleepAnalysis
    case healthKitBodyMass         // HKQuantityTypeIdentifier.bodyMass entry today
    case healthKitHydration        // dietaryWater
    case healthKitNoAlcohol        // numberOfAlcoholicBeverages == 0
    case screenTimeSocial          // DeviceActivity social category cap (iOS only)
    case selfReport                // No automatic verification possible
}

@Model
final class Habit {
    var title: String
    @Attribute(originalName: "entryType")
    private var entryTypeRawValue: String?
    var createdAt: Date
    var completedDayKeys: [String]
    var backendId: Int64?
    /// Wall-clock time of the last local modification; used for conflict detection.
    var updatedAt: Date
    /// Outbox state — never `.synced` until the server confirms the write.
    var syncStatus: SyncStatus

    // MARK: - Pending check outbox
    // When the user toggles a habit and the upload hasn't been confirmed yet, these two
    // fields capture the exact operation. `flushOutbox` uses them to send the right
    // done/undone state rather than blindly re-pushing all completedDayKeys.
    // Both are nil when no pending check operation exists.

    /// The day key whose done-state is waiting to be uploaded to the server.
    var pendingCheckDayKey: String?
    /// The done value that should be sent for `pendingCheckDayKey`.
    var pendingCheckIsDone: Bool

    /// Raw value of `HabitReminderWindow`; nil means no time-window reminder.
    var reminderWindow: String?

    /// Optional due date for task-type entries. Nil for habits or undated tasks.
    var dueAt: Date?

    /// When true the habit is hidden from the dashboard and removed from sync.
    /// History is preserved locally so streaks remain intact.
    var isArchived: Bool

    /// True once the overdue penalty (freeze consumption or XP dock) has been
    /// applied for this task. Prevents double-penalising the same overdue task
    /// across sync cycles.
    var overduePenaltyApplied: Bool = false

    // MARK: - Verification (HealthKit / Screen Time)
    // New additive fields — all default, so existing SwiftData stores migrate
    // silently without a migration plan.

    /// Raw `VerificationTier`; defaults to `.selfReport` so legacy habits keep
    /// working unchanged and only earn base points until a canonical mapping
    /// is attached.
    var verificationTierRaw: String = VerificationTier.selfReport.rawValue

    /// Raw `VerificationSource`; nil means "no external signal — honor system".
    var verificationSourceRaw: String? = nil

    /// Threshold or type code for the verification query.
    /// Semantics depend on `verificationSource`:
    ///   - `.healthKitWorkout`: `HKWorkoutActivityType.rawValue` (nil matches any workout)
    ///   - `.healthKitSteps`: step threshold (e.g. 8000)
    ///   - `.healthKitMindful`: minimum minutes (e.g. 5)
    ///   - `.healthKitSleep`: minimum hours (e.g. 7)
    ///   - `.healthKitHydration`: minimum millilitres (e.g. 2000)
    ///   - `.screenTimeSocial`: maximum minutes allowed on social category
    var verificationParam: Double? = nil

    /// Stable id of the `CanonicalHabit` this habit maps to (e.g. `"run"`,
    /// `"workout"`). Nil means the user typed a custom title that didn't
    /// match any canonical alias.
    var canonicalKey: String? = nil

    /// Target number of completions per ISO week for frequency-based habits
    /// (e.g. "gym 5× per week"). `nil` — legacy daily behavior, one check
    /// per day. Once the target is met for the current week the habit is
    /// hidden from the main list and surfaces as a background stamp until
    /// the next ISO week begins. Tasks ignore this field.
    var weeklyTarget: Int? = nil

    /// Stable per-record UUID that `HabitCompletion.habitLocalId` references
    /// so evidence records can be reconciled back to their parent habit
    /// before the first sync round-trip assigns `backendId`. Optional so
    /// SwiftData's lightweight migration path can fill pre-Verification
    /// rows with nil — callers use `ensureLocalUUID()` to seed one on
    /// first use without racing migration.
    var localUUID: UUID? = nil

    /// Raw `TaskPriority`; nil means "not prioritised" (default). Optional
    /// so legacy SwiftData rows lightweight-migrate without a migration plan.
    /// Only meaningful for `entryType == .task`; habits ignore this field.
    var priorityRaw: String? = nil

    /// Backward-compatible entry kind accessor.
    /// Older stores may contain missing/invalid values; those fall back to `.habit`.
    var entryType: HabitEntryType {
        get {
            HabitEntryType(rawValue: entryTypeRawValue ?? "") ?? .habit
        }
        set {
            entryTypeRawValue = newValue.rawValue
        }
    }

    /// Two-tier canonical lookup for the verification getters below.
    /// Used to recover auto-verified rendering when the backend or sync
    /// pipeline somehow drops the verification fields.
    ///
    /// 1. Match by `canonicalKey` if set — preserves user intent precisely.
    /// 2. As a last resort, match the habit's title against the canonical
    ///    aliases exactly (case-insensitive). Conservative on purpose:
    ///    only EXACT alias matches qualify ("Run", "Morning Run", "Gym")
    ///    so natural-language titles like "I went for a run" don't
    ///    silently flip to auto-verified.
    private var effectiveCanonical: CanonicalHabit? {
        if let key = canonicalKey,
           let canonical = CanonicalHabits.all.first(where: { $0.key == key }) {
            return canonical
        }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return CanonicalHabits.all.first { canonical in
            canonical.aliases.contains(normalized)
        }
    }

    /// Typed accessor for `verificationTierRaw`. Unknown raw values fall back
    /// to `.selfReport` so a forward-compatible client never crashes on a
    /// tier introduced later. Falls back to `effectiveCanonical.tier` when
    /// the raw is the default `.selfReport` and a canonical match exists,
    /// so multi-device sync drops can't strip auto-verification.
    var verificationTier: VerificationTier {
        get {
            let raw = VerificationTier(rawValue: verificationTierRaw) ?? .selfReport
            if raw == .selfReport, let canonical = effectiveCanonical {
                return canonical.tier
            }
            return raw
        }
        set { verificationTierRaw = newValue.rawValue }
    }

    /// Typed accessor for `verificationSourceRaw`. Same `effectiveCanonical`
    /// fallback as `verificationTier`.
    var verificationSource: VerificationSource? {
        get {
            if let raw = verificationSourceRaw,
               let source = VerificationSource(rawValue: raw) {
                return source
            }
            return effectiveCanonical?.source
        }
        set { verificationSourceRaw = newValue?.rawValue }
    }

    /// Verification query parameter (workout activity type code, step
    /// threshold, etc.) with the same canonical fallback as
    /// `verificationSource`. iPhone's `AutoVerificationCoordinator` reads
    /// this — without the fallback, a habit synced from a peer device
    /// that lost `verificationParam` would auto-flag as HealthKit but
    /// the verifier would query "any workout" instead of (say) running.
    /// Returns the stored value when present so explicit user choices
    /// always win over the canonical default.
    var effectiveVerificationParam: Double? {
        if let p = verificationParam { return p }
        return effectiveCanonical?.param
    }

    /// Typed accessor for `priorityRaw`. Unknown raw values fall back to
    /// nil so a forward-compatible client never crashes on a priority
    /// introduced later. Setter writes nil for nil values so legacy rows
    /// stay legacy until the user actually picks a priority.
    var priority: TaskPriority? {
        get { priorityRaw.flatMap(TaskPriority.init(rawValue:)) }
        set { priorityRaw = newValue?.rawValue }
    }

    init(
        title: String,
        entryType: HabitEntryType = .habit,
        createdAt: Date = Date(),
        completedDayKeys: [String] = [],
        backendId: Int64? = nil,
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending,
        pendingCheckDayKey: String? = nil,
        pendingCheckIsDone: Bool = false,
        reminderWindow: String? = nil,
        dueAt: Date? = nil,
        isArchived: Bool = false,
        overduePenaltyApplied: Bool = false,
        verificationTier: VerificationTier = .selfReport,
        verificationSource: VerificationSource? = nil,
        verificationParam: Double? = nil,
        canonicalKey: String? = nil,
        weeklyTarget: Int? = nil,
        localUUID: UUID? = UUID(),
        priority: TaskPriority? = nil
    ) {
        self.title = title
        self.entryTypeRawValue = entryType.rawValue
        self.createdAt = createdAt
        self.completedDayKeys = completedDayKeys
        self.backendId = backendId
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
        self.pendingCheckDayKey = pendingCheckDayKey
        self.pendingCheckIsDone = pendingCheckIsDone
        self.reminderWindow = reminderWindow
        self.dueAt = dueAt
        self.isArchived = isArchived
        self.overduePenaltyApplied = overduePenaltyApplied
        self.verificationTierRaw = verificationTier.rawValue
        self.verificationSourceRaw = verificationSource?.rawValue
        self.verificationParam = verificationParam
        self.canonicalKey = canonicalKey
        self.weeklyTarget = weeklyTarget
        self.localUUID = localUUID
        self.priorityRaw = priority?.rawValue
    }

    // MARK: - Convenience

    /// Tasks stay completed once any day key is recorded; habits are per-day.
    var isTaskCompleted: Bool {
        entryType == .task && !completedDayKeys.isEmpty
    }

    /// Task is strictly past its due date (and not yet done). A task whose
    /// due date is *today* is still on time — the user has until end-of-day
    /// to finish it, so we don't block new task creation on it. Tasks with
    /// no due date are likewise never overdue. Habits ignore this entirely.
    func isOverdue(now: Date = Date()) -> Bool {
        guard entryType == .task, !isTaskCompleted, let due = dueAt else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        return dueDay < today
    }

    // MARK: - Weekly target & verification helpers

    /// True only for habits (not tasks) that the user has committed to as
    /// "N times per ISO week" rather than the default daily cadence.
    var isFrequencyBased: Bool {
        entryType == .habit && (weeklyTarget ?? 0) > 0
    }

    /// True when the habit has an external-signal verification source the
    /// app can poll (HealthKit, Screen Time). Auto-verified habits can't
    /// be manually toggled — `AutoVerificationCoordinator` watches the
    /// source and marks them done on its own. Users keep an escape hatch
    /// via long-press "Mark done manually" which records the completion
    /// at `.selfReport` tier, preserving the leaderboard cheating cost.
    var isAutoVerified: Bool {
        guard entryType == .habit, let source = verificationSource else { return false }
        return source != .selfReport
    }

    /// Returns this habit's stable local UUID, lazily seeding one the first
    /// time a pre-Verification record is touched. Must be called from a
    /// write-capable context (e.g. inside a SwiftData `ModelContext` that
    /// will later `save()`).
    @discardableResult
    func ensureLocalUUID() -> UUID {
        if let existing = localUUID { return existing }
        let fresh = UUID()
        localUUID = fresh
        return fresh
    }

    /// Count of completions inside the ISO week that contains `referenceDate`.
    /// Used by both the weekly-target gating (hide from list once met) and
    /// the rest-budget math in perfect-day scoring.
    func completionsInWeek(containing referenceDate: Date) -> Int {
        let keys = Self.weekKeys(containing: referenceDate)
        let completed = Set(completedDayKeys)
        return keys.reduce(0) { $0 + (completed.contains($1) ? 1 : 0) }
    }

    /// True once the user has logged at least `weeklyTarget` completions in
    /// the ISO week containing `referenceDate`. False for non-frequency
    /// habits, tasks, and habits with a nil or non-positive target.
    func weeklyTargetReached(containing referenceDate: Date) -> Bool {
        guard isFrequencyBased, let target = weeklyTarget else { return false }
        return completionsInWeek(containing: referenceDate) >= target
    }

    /// Whether this habit counts as "satisfied" on the calendar day keyed
    /// by `dayKey` for perfect-day scoring.
    ///
    /// Daily habits / tasks: satisfied iff the user actually completed
    /// them that day — existing behavior, unchanged.
    ///
    /// Weekly-target habits: satisfied if either (a) the user logged a
    /// completion on `dayKey`, OR (b) `dayKey` fits within the week's
    /// rest budget (`7 - weeklyTarget` non-completion days counted in
    /// chronological order). For a 5×/week target with one gym visit,
    /// the first 2 non-gym days of the week count as perfect rest; any
    /// additional non-gym day is a missed commitment and imperfect.
    func isSatisfied(on dayKey: String) -> Bool {
        let completed = completedDayKeys.contains(dayKey)
        guard isFrequencyBased, let target = weeklyTarget else {
            return completed
        }
        if completed { return true }

        let referenceDate = DateKey.date(from: dayKey)
        let weekDayKeys = Self.weekKeys(containing: referenceDate)
        let restBudget = max(0, 7 - target)
        let completedSet = Set(completedDayKeys)

        var restUsed = 0
        for key in weekDayKeys {
            if completedSet.contains(key) { continue }
            restUsed += 1
            if key == dayKey {
                return restUsed <= restBudget
            }
        }
        return false
    }

    /// All seven day keys for the ISO week containing `referenceDate`,
    /// Monday-first and in chronological order. Exposed at the type level
    /// so `HabitMetrics` and the UI filters share one notion of "the week".
    static func weekKeys(containing referenceDate: Date) -> [String] {
        let cal = isoWeekCalendar
        let start = cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? cal.startOfDay(for: referenceDate)
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start).map(DateKey.key(for:))
        }
    }

    /// ISO-8601 calendar (Monday-starts-week, min 4 days in first week) so
    /// client and backend weekly scoring agree on which days belong to
    /// which week across timezones.
    private static var isoWeekCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    // MARK: - Duplicate detection

    /// Normalized match key: trimmed + lower-cased so "Run ", "run", "RUN"
    /// all collide. Returning an empty string means "no real title to match".
    static func duplicateMatchKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when `candidate` would duplicate an entry of the same kind.
    /// Habits: any active habit with the same title blocks adding (they're
    /// permanent, so a second identical row is never wanted). Tasks: only
    /// blocks while a same-titled task is still pending — once completed the
    /// user can re-add it (e.g. recurring errands like "Pay rent").
    /// Archived entries are ignored so the user can start over on a habit
    /// they previously gave up on.
    static func hasDuplicate(title candidate: String,
                             entryType: HabitEntryType,
                             in habits: [Habit]) -> Bool {
        let key = duplicateMatchKey(candidate)
        guard !key.isEmpty else { return false }
        return habits.contains { existing in
            guard !existing.isArchived,
                  existing.entryType == entryType,
                  duplicateMatchKey(existing.title) == key else { return false }
            switch entryType {
            case .habit: return true
            case .task:  return !existing.isTaskCompleted
            }
        }
    }
}
