import Testing
import Foundation
@testable import Forma

struct CanonicalHabitsTests {

    @Test func directAliasMatch() {
        #expect(CanonicalHabits.match(userTitle: "run")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "Running")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "MEDITATE")?.key == "meditate")
    }

    @Test func stopwordsAreStripped() {
        // "morning" / "evening" / "daily" should collapse to the core noun.
        #expect(CanonicalHabits.match(userTitle: "morning run")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "evening jog")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "daily meditation")?.key == "meditate")
    }

    @Test func tokenSetMatchesMultiWordAliases() {
        // "gym sesh" has "gym" as a known alias; extra words shouldn't block it.
        #expect(CanonicalHabits.match(userTitle: "gym sesh")?.key == "workout")
        #expect(CanonicalHabits.match(userTitle: "5k morning run")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "yoga flow")?.key == "yoga")
    }

    @Test func fuzzyMatchToleratesTypos() {
        // Single-character typo within Levenshtein ≤ 2 threshold.
        #expect(CanonicalHabits.match(userTitle: "runnin")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "meditaiton")?.key == "meditate")
    }

    @Test func nonsenseReturnsNil() {
        #expect(CanonicalHabits.match(userTitle: "asdkfjaldkfjsdf") == nil)
        #expect(CanonicalHabits.match(userTitle: "") == nil)
        #expect(CanonicalHabits.match(userTitle: "   ") == nil)
    }

    @Test func punctuationAndCasingNormalized() {
        #expect(CanonicalHabits.match(userTitle: "Run!!!")?.key == "run")
        #expect(CanonicalHabits.match(userTitle: "yoga, stretching")?.key == "yoga")
    }

    @Test func canonicalKeysAreStableAndUnique() {
        // If this test ever fails, someone renamed a canonical key in place —
        // which would strand the mapping on every device that persisted the
        // old key. Add a new key, don't mutate an existing one.
        let keys = CanonicalHabits.all.map(\.key)
        #expect(Set(keys).count == keys.count, "duplicate canonical keys")
        #expect(keys.contains("run"))
        #expect(keys.contains("workout"))
        #expect(keys.contains("meditate"))
    }

    @Test func levenshteinMatchesKnownDistances() {
        #expect(CanonicalHabits.levenshtein("kitten", "sitting") == 3)
        #expect(CanonicalHabits.levenshtein("book", "back") == 2)
        #expect(CanonicalHabits.levenshtein("", "hello") == 5)
        #expect(CanonicalHabits.levenshtein("same", "same") == 0)
    }
}

struct HabitMigrationTests {

    @Test func legacyInitDefaultsNewVerificationFields() {
        // Simulates a habit created by an older build that didn't know about
        // verification. The new fields must take their defaults without
        // forcing callers to pass them explicitly.
        let habit = Habit(
            title: "Run",
            entryType: .habit,
            createdAt: Date(),
            completedDayKeys: ["2026-04-20"]
        )
        #expect(habit.verificationTier == .selfReport)
        #expect(habit.verificationSource == nil)
        #expect(habit.verificationParam == nil)
        #expect(habit.canonicalKey == nil)
    }

    @Test func typedAccessorsRoundTripThroughRawStorage() {
        let habit = Habit(title: "Run")
        habit.verificationTier = .auto
        habit.verificationSource = .healthKitWorkout
        #expect(habit.verificationTierRaw == "auto")
        #expect(habit.verificationSourceRaw == "healthKitWorkout")
        #expect(habit.verificationTier == .auto)
        #expect(habit.verificationSource == .healthKitWorkout)
    }

    @Test func unknownRawValuesFallBackSafely() {
        // A build that persisted a verification tier we don't recognize
        // (future build wrote it) must degrade gracefully, not crash.
        let habit = Habit(title: "Run")
        habit.verificationTierRaw = "futurePlatinumTier"
        habit.verificationSourceRaw = "quantumVerifier"
        #expect(habit.verificationTier == .selfReport)
        #expect(habit.verificationSource == nil)
    }
}

/// The weekly-target feature. Exercises the rest-budget algorithm that
/// decides which days are "satisfied" for frequency-based habits like
/// "gym 5×/week", and the helpers that drive the list-hiding behavior.
struct WeeklyTargetTests {

    /// A day that falls inside the week containing one of the completion
    /// dates — used as the reference for `weekKeys`. We pick a Wednesday
    /// so the ISO week boundary is unambiguous.
    private static let wed = "2026-04-22"

    @Test func dailyHabitsIgnoreWeeklyTarget() {
        let habit = Habit(title: "Meditate", entryType: .habit, completedDayKeys: ["2026-04-20"])
        #expect(habit.isFrequencyBased == false)
        #expect(habit.isSatisfied(on: "2026-04-20"))
        #expect(habit.isSatisfied(on: "2026-04-21") == false)
    }

    @Test func fiveTimesPerWeekTargetReachedHidesRemainingDays() {
        // Gym 5×/week — user logs 5 workouts. Target reached means the
        // habit drops out of the list for the rest of the week.
        let habit = Habit(
            title: "Gym",
            entryType: .habit,
            completedDayKeys: [
                "2026-04-20", // Mon
                "2026-04-21", // Tue
                "2026-04-22", // Wed
                "2026-04-23", // Thu
                "2026-04-24"  // Fri
            ],
            weeklyTarget: 5
        )
        #expect(habit.isFrequencyBased)
        #expect(habit.weeklyTargetReached(containing: DateKey.date(from: Self.wed)))
        #expect(habit.completionsInWeek(containing: DateKey.date(from: Self.wed)) == 5)
    }

    @Test func restBudgetFillsMissedDaysChronologically() {
        // Gym 5×/week with only 1 visit (Tuesday) — from the user's
        // example: "3 perfect days: 1 gym + 2 rest; next 3 won't be
        // perfect." Mon and Wed are the first two rest days (within
        // the 7-5=2 budget); Thu–Sun are missed commitment.
        let habit = Habit(
            title: "Gym",
            entryType: .habit,
            completedDayKeys: ["2026-04-21"],
            weeklyTarget: 5
        )
        #expect(habit.isSatisfied(on: "2026-04-20")) // Mon — rest 1/2
        #expect(habit.isSatisfied(on: "2026-04-21")) // Tue — gym
        #expect(habit.isSatisfied(on: "2026-04-22")) // Wed — rest 2/2
        #expect(habit.isSatisfied(on: "2026-04-23") == false) // Thu — rest budget spent
        #expect(habit.isSatisfied(on: "2026-04-24") == false) // Fri — missed
        #expect(habit.isSatisfied(on: "2026-04-25") == false) // Sat — missed
        #expect(habit.isSatisfied(on: "2026-04-26") == false) // Sun — missed
    }

    @Test func weekKeysAreMondayStartSevenConsecutive() {
        // ISO weeks start Monday. Any reference day in the same week
        // should produce the same seven keys.
        let fromWed = Habit.weekKeys(containing: DateKey.date(from: "2026-04-22"))
        let fromSat = Habit.weekKeys(containing: DateKey.date(from: "2026-04-25"))
        #expect(fromWed.count == 7)
        #expect(fromWed == fromSat)
        #expect(fromWed.first == "2026-04-20")
        #expect(fromWed.last == "2026-04-26")
    }

    @Test func ensureLocalUUIDIsStableAcrossCalls() {
        // First call seeds the UUID; subsequent calls must return the
        // same one so HabitCompletion records don't orphan.
        let habit = Habit(title: "Run", localUUID: nil)
        let first = habit.ensureLocalUUID()
        let second = habit.ensureLocalUUID()
        #expect(first == second)
    }
}

/// Covers the silent-fallback contract: if HealthKit is unavailable, the
/// permission is denied, or the query turns up nothing, `verify` must
/// return a `.selfReport` completion rather than throwing. We can't stub
/// `HKHealthStore` without UI test infra, so we exercise the static
/// entry points that control the fallback pathway directly.
struct VerificationServiceFallbackTests {

    @Test func selfReportSourcePassesThrough() async {
        // `.selfReport` source returns the fallback completion without
        // touching HealthKit — safe to run in any test environment.
        let completion = await VerificationService.shared.verify(
            habitBackendId: 42,
            habitLocalId: UUID(),
            source: .selfReport,
            tier: .selfReport,
            param: nil,
            dayKey: "2026-04-24"
        )
        #expect(completion.verifiedBySource == .selfReport)
        #expect(completion.awardedTier == .selfReport)
        #expect(completion.dayKey == "2026-04-24")
        #expect(completion.habitBackendId == 42)
    }

    @Test func malformedDayKeyFallsBackToSelfReport() async {
        // Day-bounds parsing rejects anything that isn't `yyyy-MM-dd`;
        // the verify() contract turns that into self-report rather than
        // throwing so bad input never blocks a toggle.
        let completion = await VerificationService.shared.verify(
            habitBackendId: nil,
            habitLocalId: UUID(),
            source: .healthKitSteps,
            tier: .auto,
            param: 8000,
            dayKey: "not-a-date"
        )
        #expect(completion.verifiedBySource == .selfReport)
        #expect(completion.awardedTier == .selfReport)
    }
}
