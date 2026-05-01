import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

/// Shared Live Activity schema for the "streak in progress" activity.
/// Lives in the main app so both the app (which starts / updates activities)
/// and the Widget Extension (which renders them) can import it.
#if os(iOS) && canImport(ActivityKit)
@available(iOS 16.1, *)
struct StreakActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var doneToday: Int
        public var totalToday: Int
        public var currentStreak: Int
        public var todayKey: String
        /// True when today is covered by a streak freeze — the Live Activity
        /// should surface a snowflake indicator so the user sees protection
        /// state without opening the app. Optional for back-compat decoding.
        public var isFrozen: Bool

        public init(doneToday: Int, totalToday: Int, currentStreak: Int, todayKey: String, isFrozen: Bool = false) {
            self.doneToday = doneToday
            self.totalToday = totalToday
            self.currentStreak = currentStreak
            self.todayKey = todayKey
            self.isFrozen = isFrozen
        }

        enum CodingKeys: String, CodingKey {
            case doneToday, totalToday, currentStreak, todayKey, isFrozen
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            doneToday = try c.decode(Int.self, forKey: .doneToday)
            totalToday = try c.decode(Int.self, forKey: .totalToday)
            currentStreak = try c.decode(Int.self, forKey: .currentStreak)
            todayKey = try c.decode(String.self, forKey: .todayKey)
            isFrozen = try c.decodeIfPresent(Bool.self, forKey: .isFrozen) ?? false
        }

        public var progress: Double {
            totalToday > 0 ? Double(doneToday) / Double(totalToday) : 0
        }
    }

    public var userName: String

    public init(userName: String) { self.userName = userName }
}
#endif
