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
        /// Pre-formatted AI/heuristic time suggestion the iPhone computed.
        /// Mirrors the chip the user sees on iOS/iPadOS/macOS so the
        /// watch experience is consistent — "Try 1:30 PM — afternoon
        /// dip, fine for chores". Optional so older snapshots keep
        /// decoding cleanly.
        let suggestionLabel: String?

        // Legacy initializer signature kept stable so older test fixtures
        // and preview helpers don't break when the new `suggestionLabel`
        // arg is added — defaulted to nil.
        init(
            id: String,
            title: String,
            emoji: String,
            kind: HabitKind,
            progress: Double,
            unitsLogged: Int,
            unitsTarget: Int,
            unitsLabel: String,
            isCompleted: Bool,
            sourceLabel: String,
            canonicalKey: String?,
            suggestionLabel: String? = nil
        ) {
            self.id = id
            self.title = title
            self.emoji = emoji
            self.kind = kind
            self.progress = progress
            self.unitsLogged = unitsLogged
            self.unitsTarget = unitsTarget
            self.unitsLabel = unitsLabel
            self.isCompleted = isCompleted
            self.sourceLabel = sourceLabel
            self.canonicalKey = canonicalKey
            self.suggestionLabel = suggestionLabel
        }

        // Codable: declare the keys explicitly so a missing
        // `suggestionLabel` decodes to nil instead of a JSON error when
        // an older iOS build pushes a snapshot.
        enum CodingKeys: String, CodingKey {
            case id, title, emoji, kind, progress
            case unitsLogged, unitsTarget, unitsLabel
            case isCompleted, sourceLabel, canonicalKey, suggestionLabel
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.title = try c.decode(String.self, forKey: .title)
            self.emoji = try c.decode(String.self, forKey: .emoji)
            self.kind = try c.decode(HabitKind.self, forKey: .kind)
            self.progress = try c.decode(Double.self, forKey: .progress)
            self.unitsLogged = try c.decode(Int.self, forKey: .unitsLogged)
            self.unitsTarget = try c.decode(Int.self, forKey: .unitsTarget)
            self.unitsLabel = try c.decode(String.self, forKey: .unitsLabel)
            self.isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
            self.sourceLabel = try c.decode(String.self, forKey: .sourceLabel)
            self.canonicalKey = try c.decodeIfPresent(String.self, forKey: .canonicalKey)
            self.suggestionLabel = try c.decodeIfPresent(String.self, forKey: .suggestionLabel)
        }
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

    // MARK: Mentor messages

    /// One row in the mentor recent-conversations tab. Origin marks who sent
    /// the message — `mentor` text is rendered left-aligned with a coloured
    /// avatar dot, `me` text is right-aligned with a brand gradient dot.
    struct WatchMentorMessage: Codable, Equatable, Identifiable {
        enum Origin: String, Codable { case mentor, me }

        var id: String { messageId }
        let messageId: String          // backend uuid or local cuid
        let origin: Origin
        let senderName: String         // "Aanya" / "You" — used for the leading initial
        let preview: String            // 1-line message body, already truncated by phone
        let relativeTime: String       // "2m" / "1h" / "yest" — phone formats once
        let isUnread: Bool             // mentor-origin only; drives the gold accent
    }

    // MARK: Top-level

    let generatedAt: Date
    let todayKey: String               // "yyyy-MM-dd"
    let weekdayShort: String           // "WED" / "THU" / etc — the iPhone formats once
    let timeOfDay: String              // "9:41" — iPhone formats so the Watch doesn't recompute
    var pendingHabits: [WatchHabit]    // includes everything the user could check today
    var completedHabits: [WatchHabit]  // already-done, used for opacity/strikethrough
    var metrics: Metrics
    let leaderboard: [WatchLeaderboardEntry]
    let calendarHeatmap: [String: Double]   // yyyy-MM-dd → 0...1 completion intensity
    let calendarMonthLabel: String          // "APR" / "MAY" — top-right of the calendar tab
    let account: AccountInfo
    /// Optional so the iPhone can keep broadcasting the legacy snapshot shape
    /// during rollout; the watch falls back to an empty list in that case.
    let mentorMessages: [WatchMentorMessage]?

    // MARK: Empty / placeholder

    /// A neutral, EMPTY snapshot. Used as the initial value of the Watch's
    /// observable state so the SwiftUI views have something to render before
    /// the iPhone connects, and as the SwiftUI #Preview source.
    ///
    /// **No fake content.** Real users would otherwise see invented friends,
    /// mentor messages, and habits during the connection window — exactly
    /// the impression we want to avoid. The root view checks
    /// `WatchSession.hasReceivedRealData` and shows a "connecting" state
    /// until the first real snapshot arrives, so this empty payload should
    /// never reach the user's screen in practice.
    static func empty() -> WatchSnapshot {
        WatchSnapshot(
            generatedAt: Date(),
            todayKey: WatchDayKey.dayKey(for: Date()),
            weekdayShort: WatchDayKey.weekdayShort(for: Date()),
            timeOfDay: WatchDayKey.timeOfDay(for: Date()),
            pendingHabits: [],
            completedHabits: [],
            metrics: .init(
                doneToday: 0, totalToday: 0,
                currentStreak: 0, bestStreak: 0,
                level: 1, levelName: "", xp: 0, xpForNextLevel: 0,
                nextLevelProgress: 0, leaderboardRank: 0, freezesAvailable: 0
            ),
            leaderboard: [],
            calendarHeatmap: [:],
            calendarMonthLabel: WatchDayKey.monthLabel(for: Date()),
            account: .init(
                displayName: "",
                handle: "",
                avatarInitial: "",
                healthKitOn: false,
                notificationsOn: false
            ),
            mentorMessages: nil
        )
    }

    /// Sample snapshot for SwiftUI #Preview blocks ONLY. Keeps the design
    /// inspectable in Xcode without leaking dummy values into shipped builds.
    /// Wrapped in `#if DEBUG` so the linker can't accidentally pull this into
    /// a release build.
    #if DEBUG
    static func previewSample() -> WatchSnapshot {
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
                doneToday: 1, totalToday: 3,
                currentStreak: 12, bestStreak: 23,
                level: 7, levelName: "Consistent", xp: 4120, xpForNextLevel: 6000,
                nextLevelProgress: 0.62, leaderboardRank: 2, freezesAvailable: 3
            ),
            leaderboard: [
                .init(rank: 1, displayName: "Aanya", score: 4280, isCurrentUser: false),
                .init(rank: 2, displayName: "You",   score: 4120, isCurrentUser: true),
                .init(rank: 3, displayName: "Rohan", score: 3960, isCurrentUser: false),
            ],
            calendarHeatmap: [:],
            calendarMonthLabel: WatchDayKey.monthLabel(for: Date()),
            account: .init(
                displayName: "Jashan",
                handle: "@jashan",
                avatarInitial: "J",
                healthKitOn: true,
                notificationsOn: true
            ),
            mentorMessages: [
                .init(messageId: "m1", origin: .mentor, senderName: "Aanya",
                      preview: "Proud of the streak. Keep it up tomorrow morning.",
                      relativeTime: "12m", isUnread: true)
            ]
        )
    }
    #endif
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

    /// "WED" / "THU" — caps so the watch never has to format on render.
    static func weekdayShort(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    /// "9:41" — locale-respecting short-style time.
    static func timeOfDay(for date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// "APR" / "MAY" — three-letter month label.
    static func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLL"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Watch → iPhone messages

/// The small command vocabulary the Watch sends back to the iPhone.
/// Encoded as a `[String: Any]` payload over `WCSession.sendMessage`.
enum WatchMessageKey {
    static let action      = "action"
    static let habitId     = "habitId"
    static let delta       = "delta"
    static let title       = "title"     // payload for createHabit
}

enum WatchMessageAction {
    static let logHabit    = "logHabit"      // increment a manual habit's count by `delta`
    static let toggleHabit = "toggleHabit"   // flip a binary manual habit done/not-done
    static let requestSnapshot = "requestSnapshot"  // Watch asks for a fresh push
    static let createHabit = "createHabit"   // dictation/Scribble entry → "title" arg → iPhone inserts SwiftData row
}
