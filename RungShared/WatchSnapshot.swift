import Foundation

/// Snapshot the iPhone broadcasts to the Apple Watch over WatchConnectivity.
/// The Watch runs no SwiftData store of its own — iPhone is the source of truth,
/// and this struct is the entire surface area.
///
/// Compiled into BOTH the iOS Rung target and the watchOS RungWatch target.
/// Keep it Foundation-only — no SwiftData, no SwiftUI, no platform imports.
struct WatchSnapshot: Codable, Equatable {

    // MARK: Habits

    enum HabitKind: String, Codable {
        case manual           // user toggles by hand → tap row → drill in & crown logs +1
        case healthKit        // auto-checked from HealthKit → read-only ♥ row
    }

    struct WatchHabit: Codable, Equatable, Identifiable {
        let id: String                 // localUUID stringified, or backendId, fallback to title hash
        let title: String
        let emoji: String              // canonical icon mapping; "•" fallback
        let kind: HabitKind
        let progress: Double           // 0...1 — how much of today's target the user has met
        let unitsLogged: Int           // for manual habits with a count target (e.g. 6 of 8 cups)
        let unitsTarget: Int           // 0 means "binary" — just done/not-done
        let unitsLabel: String         // e.g. "CUPS", "MIN", "PAGES" — uppercase short word
        let isCompleted: Bool          // derived: progress >= 1 OR completedDayKeys contains today
        let sourceLabel: String        // for HealthKit rows: "APPLE HEALTH"; manual: ""
        let canonicalKey: String?      // optional — drives drill-in detail behaviour
    }

    // MARK: Metrics

    struct Metrics: Codable, Equatable {
        let doneToday: Int
        let totalToday: Int
        let currentStreak: Int
        let bestStreak: Int
        let level: Int                 // numeric level for the Watch's circular badge
        let levelName: String          // e.g. "Consistent"
        let xp: Int
        let xpForNextLevel: Int        // 0 means "max" — render full bar
        let nextLevelProgress: Double  // 0...1, what fraction of the next level the user has earned
        let leaderboardRank: Int       // 0 means "unranked"
        let freezesAvailable: Int
    }

    // MARK: Leaderboard

    struct WatchLeaderboardEntry: Codable, Equatable, Identifiable {
        var id: String { "\(rank)-\(displayName)-\(score)-\(isCurrentUser)" }
        let rank: Int
        let displayName: String
        let score: Int
        let isCurrentUser: Bool
    }

    // MARK: Account

    struct AccountInfo: Codable, Equatable {
        let displayName: String
        let handle: String             // already includes the leading "@"
        let avatarInitial: String      // first letter of displayName, uppercased
        let healthKitOn: Bool
        let notificationsOn: Bool
    }

    // MARK: Top-level

    let generatedAt: Date
    let todayKey: String               // "yyyy-MM-dd"
    let weekdayShort: String           // "WED" / "THU" / etc — the iPhone formats once
    let timeOfDay: String              // "9:41" — iPhone formats so the Watch doesn't recompute
    let pendingHabits: [WatchHabit]    // includes everything the user could check today
    let completedHabits: [WatchHabit]  // already-done, used for opacity/strikethrough
    let metrics: Metrics
    let leaderboard: [WatchLeaderboardEntry]
    let calendarHeatmap: [String: Double]   // yyyy-MM-dd → 0...1 completion intensity
    let calendarMonthLabel: String          // "APR" / "MAY" — top-right of the calendar tab
    let account: AccountInfo

    // MARK: Empty / placeholder

    /// A placeholder snapshot the Watch can render before the iPhone has
    /// pushed real data. Keeps the layout from collapsing and helps designers
    /// preview the UI in Xcode without a live phone.
    static func placeholder() -> WatchSnapshot {
        let today = WatchDayKey.dayKey(for: Date())
        return WatchSnapshot(
            generatedAt: Date(),
            todayKey: today,
            weekdayShort: "WED",
            timeOfDay: "9:41",
            pendingHabits: [
                .init(id: "1", title: "Drink water", emoji: "💧", kind: .manual,
                      progress: 0.75, unitsLogged: 6, unitsTarget: 8,
                      unitsLabel: "CUPS", isCompleted: false, sourceLabel: "",
                      canonicalKey: "water"),
                .init(id: "2", title: "Move 30 min", emoji: "🏃", kind: .healthKit,
                      progress: 1.0, unitsLogged: 42, unitsTarget: 30,
                      unitsLabel: "MIN", isCompleted: false, sourceLabel: "APPLE HEALTH",
                      canonicalKey: "run"),
                .init(id: "4", title: "Read 20m", emoji: "📚", kind: .manual,
                      progress: 0.0, unitsLogged: 0, unitsTarget: 0,
                      unitsLabel: "", isCompleted: false, sourceLabel: "",
                      canonicalKey: "read"),
            ],
            completedHabits: [
                .init(id: "3", title: "Sleep 7h", emoji: "🌙", kind: .healthKit,
                      progress: 1.0, unitsLogged: 8, unitsTarget: 7,
                      unitsLabel: "HR", isCompleted: true, sourceLabel: "APPLE HEALTH",
                      canonicalKey: "sleep"),
            ],
            metrics: .init(
                doneToday: 4, totalToday: 7,
                currentStreak: 12, bestStreak: 23,
                level: 7, levelName: "Consistent", xp: 4120, xpForNextLevel: 6000,
                nextLevelProgress: 0.62, leaderboardRank: 2, freezesAvailable: 3
            ),
            leaderboard: [
                .init(rank: 1, displayName: "Aanya", score: 4280, isCurrentUser: false),
                .init(rank: 2, displayName: "You",   score: 4120, isCurrentUser: true),
                .init(rank: 3, displayName: "Rohan", score: 3960, isCurrentUser: false),
                .init(rank: 4, displayName: "Kai",   score: 3450, isCurrentUser: false),
                .init(rank: 5, displayName: "Mira",  score: 3210, isCurrentUser: false),
            ],
            calendarHeatmap: Self.placeholderHeatmap(todayKey: today),
            calendarMonthLabel: Self.monthLabel(for: Date()),
            account: .init(
                displayName: "Jashan",
                handle: "@jashan",
                avatarInitial: "J",
                healthKitOn: true,
                notificationsOn: true
            )
        )
    }

    private static func placeholderHeatmap(todayKey: String) -> [String: Double] {
        // Build a simple gradient over the past month so the calendar tab has
        // realistic-looking data even without the phone connected.
        var out: [String: Double] = [:]
        let calendar = Calendar.current
        guard let today = WatchDayKey.date(from: todayKey) else { return out }
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start else { return out }
        let dayCount = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let key = WatchDayKey.dayKey(for: date)
            // Most days near 1.0; salt with a deterministic fluctuation.
            let intensity = 0.55 + 0.45 * Double((offset * 7 + 3) % 9) / 9.0
            out[key] = min(1.0, intensity)
        }
        return out
    }

    private static func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLL"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Lightweight day-key formatter

/// Tiny day-key helper used by both ends so the Watch can compute the placeholder
/// without dragging the iPhone's `DateKey` enum across the connectivity boundary.
/// Named `WatchDayKey` (not `ISO8601DateFormatter`) to avoid shadowing the
/// Foundation type the rest of the app uses.
enum WatchDayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }
}

// MARK: - Watch → iPhone messages

/// The small command vocabulary the Watch sends back to the iPhone.
/// Encoded as a `[String: Any]` payload over `WCSession.sendMessage`.
enum WatchMessageKey {
    static let action      = "action"
    static let habitId     = "habitId"
    static let delta       = "delta"
}

enum WatchMessageAction {
    static let logHabit    = "logHabit"      // increment a manual habit's count by `delta`
    static let toggleHabit = "toggleHabit"   // flip a binary manual habit done/not-done
    static let requestSnapshot = "requestSnapshot"  // Watch asks for a fresh push
}
