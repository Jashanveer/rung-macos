import Foundation
import HealthKit

/// A canonical, verifiable habit with a stable identifier and fuzzy-match
/// aliases. Used to upgrade user-typed habits (e.g. "morning run", "gym sesh")
/// to a known verification source, so their completions can be checked against
/// HealthKit / Screen Time instead of the honor system.
///
/// This is a compile-time registry — it intentionally lives on the client so
/// habit creation feels instant, but the server owns the ground-truth tier
/// assignment once Phase 2 ships.
struct CanonicalHabit: Hashable, Identifiable {
    /// Stable key used to persist the mapping on `Habit.canonicalKey`.
    /// Never reuse a key for a different habit; clients in the wild may have
    /// it persisted in their local store.
    let key: String
    let displayName: String
    /// Lowercase match candidates. Keep each alias short (1-3 words) — the
    /// matcher already strips common adverbs ("morning", "daily", etc.).
    let aliases: [String]
    let tier: VerificationTier
    let source: VerificationSource
    /// Threshold or activity-type code — interpreted per `source`. See
    /// `Habit.verificationParam` for the semantics per source.
    let param: Double?
    /// Realistic upper bound on how long this habit takes, in minutes. A
    /// captured Focus-Mode duration above this is treated as spurious
    /// (e.g. user toggled "drink water" while a 25-min focus timer was
    /// running for something else) and dropped from the recorded check
    /// rather than skewing the median forever. `nil` means "no cap" —
    /// used for sleep, screen-time, no-alcohol, etc., where focus-mode
    /// duration doesn't make semantic sense in the first place.
    let maxDurationMinutes: Int?

    var id: String { key }
}

enum CanonicalHabits {
    /// The seeded set of 20 canonical habits. Order is roughly "most common"
    /// first but the matcher doesn't care about order.
    static let all: [CanonicalHabit] = [
        .init(key: "run",
              displayName: "Run",
              aliases: ["run", "running", "jog", "jogging", "morning run", "evening run", "5k", "10k"],
              tier: .auto,
              source: .healthKitWorkout,
              param: Double(HKWorkoutActivityType.running.rawValue),
              maxDurationMinutes: 120),

        .init(key: "workout",
              displayName: "Workout",
              aliases: ["workout", "work out", "gym", "lift", "lifting", "training", "weights", "strength"],
              tier: .auto,
              source: .healthKitWorkout,
              param: nil,
              maxDurationMinutes: 150),

        .init(key: "walk",
              displayName: "Walk",
              aliases: ["walk", "walking", "steps", "10k steps", "hike", "hiking"],
              tier: .auto,
              source: .healthKitSteps,
              param: 8000,
              maxDurationMinutes: 240),

        .init(key: "yoga",
              displayName: "Yoga",
              aliases: ["yoga", "stretch", "stretching", "mobility", "pilates", "flexibility"],
              tier: .auto,
              source: .healthKitWorkout,
              param: Double(HKWorkoutActivityType.yoga.rawValue),
              maxDurationMinutes: 90),

        .init(key: "cycle",
              displayName: "Cycle",
              aliases: ["cycle", "cycling", "bike", "biking", "ride", "spin"],
              tier: .auto,
              source: .healthKitWorkout,
              param: Double(HKWorkoutActivityType.cycling.rawValue),
              maxDurationMinutes: 240),

        .init(key: "swim",
              displayName: "Swim",
              aliases: ["swim", "swimming", "laps", "pool"],
              tier: .auto,
              source: .healthKitWorkout,
              param: Double(HKWorkoutActivityType.swimming.rawValue),
              maxDurationMinutes: 120),

        .init(key: "meditate",
              displayName: "Meditate",
              aliases: ["meditate", "meditation", "mindfulness", "mindful", "breathwork"],
              tier: .auto,
              source: .healthKitMindful,
              param: 5,
              maxDurationMinutes: 60),

        .init(key: "sleep",
              displayName: "Sleep 7+ hrs",
              aliases: ["sleep", "7 hours sleep", "8 hours sleep", "good sleep", "rest"],
              tier: .auto,
              source: .healthKitSleep,
              param: 7,
              maxDurationMinutes: nil),  // sleep isn't a focus-timer activity

        .init(key: "weighIn",
              displayName: "Weigh in",
              aliases: ["weigh", "weigh in", "weight", "scale"],
              tier: .auto,
              source: .healthKitBodyMass,
              param: nil,
              maxDurationMinutes: 5),

        .init(key: "water",
              displayName: "Drink water",
              aliases: ["water", "hydrate", "hydration", "drink water"],
              tier: .partial,
              source: .healthKitHydration,
              param: 2000,
              maxDurationMinutes: 5),

        .init(key: "noAlcohol",
              displayName: "No alcohol",
              aliases: ["no alcohol", "sober", "dry day", "no drinking", "alcohol free"],
              tier: .partial,
              source: .healthKitNoAlcohol,
              param: nil,
              maxDurationMinutes: nil),

        .init(key: "screenTime",
              displayName: "Limit social media",
              aliases: ["screen time", "no phone", "social media detox", "phone free", "no scrolling", "less instagram"],
              tier: .auto,
              source: .screenTimeSocial,
              param: 60,
              maxDurationMinutes: nil),

        .init(key: "read",
              displayName: "Read",
              aliases: ["read", "reading", "book", "read a book", "chapters"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 180),

        .init(key: "study",
              displayName: "Study",
              aliases: ["study", "learn", "duolingo", "language", "code", "coding", "practice", "anki"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 240),

        .init(key: "journal",
              displayName: "Journal",
              aliases: ["journal", "journaling", "diary", "write"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 30),

        .init(key: "gratitude",
              displayName: "Gratitude",
              aliases: ["gratitude", "grateful", "thankful", "three good things"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 15),

        .init(key: "floss",
              displayName: "Floss",
              aliases: ["floss", "flossing", "teeth", "dental"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 5),

        .init(key: "makeBed",
              displayName: "Make bed",
              aliases: ["make bed", "bed made", "tidy bed"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 5),

        .init(key: "eatHealthy",
              displayName: "Eat healthy",
              aliases: ["healthy eating", "diet", "nutrition", "track food", "calories"],
              tier: .partial,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 60),

        .init(key: "family",
              displayName: "Family time",
              aliases: ["family", "call mom", "call dad", "loved ones", "quality time"],
              tier: .selfReport,
              source: .selfReport,
              param: nil,
              maxDurationMinutes: 240),
    ]

    /// Default cap for habits that don't have a canonical match. Wide enough
    /// to cover a few back-to-back pomodoros (1×25 + 1×25 = 50, plus the
    /// 5-min capture window slack), but tight enough that an entire
    /// half-day session won't be silently attributed.
    static let defaultMaxDurationMinutes: Int = 90

    /// Returns the max duration (in seconds) considered plausible for a
    /// completion of `habit`. Used by the toggle path to discard a captured
    /// focus duration that's clearly larger than the activity itself —
    /// e.g. 25 minutes attributed to "drink water". Nil means no cap.
    static func plausibleMaxDurationSeconds(for canonicalKey: String?) -> Int? {
        guard let key = canonicalKey, let canonical = byKey[key] else {
            return defaultMaxDurationMinutes * 60
        }
        guard let cap = canonical.maxDurationMinutes else { return nil }
        return cap * 60
    }

    /// O(1) lookup by canonical key — used when a persisted `Habit.canonicalKey`
    /// needs to be resolved back to its verification metadata.
    static let byKey: [String: CanonicalHabit] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    }()

    /// Words that the user often prefixes to a habit title but that carry no
    /// matching signal. Stripped before alias comparison so "morning run"
    /// collapses to "run".
    private static let stopwords: Set<String> = [
        "morning", "evening", "night", "afternoon", "daily", "today",
        "a", "the", "my", "do", "go", "for", "some", "every"
    ]

    /// Returns the best canonical match for a user-typed habit title, or nil
    /// if nothing is close enough. Used at habit-creation time to offer a
    /// "Did you mean *Run*?" suggestion — never apply the match silently;
    /// verification tier is a user-visible commitment.
    ///
    /// Pipeline:
    ///   1. Lowercase + trim + strip punctuation
    ///   2. Drop stopwords
    ///   3. Direct alias hit (full phrase or token-set containment)
    ///   4. Fuzzy: Levenshtein ≤ 2 on any single token of length ≥ 4
    static func match(userTitle: String) -> CanonicalHabit? {
        let normalized = normalize(userTitle)
        guard !normalized.isEmpty else { return nil }
        let tokens = normalized.split(separator: " ").map(String.init)
            .filter { !stopwords.contains($0) }
        guard !tokens.isEmpty else { return nil }
        let phrase = tokens.joined(separator: " ")
        let tokenSet = Set(tokens)

        // Stage 1: exact / containment match on any alias — highest confidence.
        for canonical in all {
            for alias in canonical.aliases {
                if alias == phrase { return canonical }
                let aliasTokens = alias.split(separator: " ").map(String.init)
                // Token-set match: every alias token is present in the input.
                // Catches "gym sesh" → "gym", "5k morning run" → "run".
                if aliasTokens.allSatisfy({ tokenSet.contains($0) }) {
                    return canonical
                }
            }
        }

        // Stage 2: fuzzy match on single-token aliases. Tighten the distance
        // threshold as token length drops to avoid matching "run" to "sun".
        var best: (CanonicalHabit, Int)? = nil
        for canonical in all {
            for alias in canonical.aliases where !alias.contains(" ") {
                guard alias.count >= 4 else { continue }
                for token in tokens where token.count >= 4 {
                    let distance = levenshtein(token, alias)
                    if distance <= 2, best.map({ distance < $0.1 }) ?? true {
                        best = (canonical, distance)
                    }
                }
            }
        }
        return best?.0
    }

    /// Exposed for testing — the normalization the matcher applies before
    /// comparing. Strips punctuation, lowercases, collapses whitespace.
    static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) { return Character(scalar) }
            if CharacterSet.decimalDigits.contains(scalar) { return Character(scalar) }
            return " "
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    /// Classic iterative Levenshtein. O(m*n) time, O(min(m,n)) space via a
    /// two-row buffer. We only call this on short single-token strings, so
    /// the constant factor doesn't matter much.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = Array(repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,     // insertion
                    prev[j] + 1,         // deletion
                    prev[j - 1] + cost   // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }
}
