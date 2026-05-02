import Foundation

/// Watch-side data model.
///
/// The Watch never instantiates SwiftData. The single source of truth is
/// `WatchSnapshot` (in `RungShared/WatchSnapshot.swift`), which both targets
/// compile against. The phone publishes a fresh snapshot whenever its local
/// `[Habit]` changes, and `WatchSession` decodes it into the `@Published`
/// property the SwiftUI views observe.
///
/// This file exists as a documented landing pad for future Watch-only
/// derived view models — a place to host things like a sorted leaderboard
/// or a calendar-month projection if the per-tab views grow too dense.
/// For now everything is computed inline in the view structs.
///
/// Cross-reference:
/// - `RungShared/WatchSnapshot.swift` — Codable transport
/// - `RungWatch/Connectivity/WatchSession.swift` — WCSession plumbing
/// - `Rung/WatchConnectivityService.swift` (iOS) — phone-side broadcaster
enum WatchDataModel {
    /// Canonical-emoji mapping mirrored from `CanonicalHabits` in the iOS app
    /// so the watch can fall back to a sensible icon if the snapshot ever
    /// arrives without an emoji set. Keep in sync with the `displayName`s in
    /// the iOS-side `CanonicalHabits.all`.
    static let emojiByCanonicalKey: [String: String] = [
        "run":         "\u{1F3C3}",   // 🏃
        "workout":     "\u{1F3CB}",   // 🏋️
        "walk":        "\u{1F6B6}",   // 🚶
        "yoga":        "\u{1F9D8}",   // 🧘
        "cycle":       "\u{1F6B4}",   // 🚴
        "swim":        "\u{1F3CA}",   // 🏊
        "meditate":    "\u{1F9D8}",   // 🧘
        "sleep":       "\u{1F319}",   // 🌙
        "weighIn":     "\u{2696}\u{FE0F}",  // ⚖️
        "water":       "\u{1F4A7}",   // 💧
        "noAlcohol":   "\u{1F6AB}",   // 🚫
        "screenTime":  "\u{1F4F1}",   // 📱
        "read":        "\u{1F4DA}",   // 📚
        "study":       "\u{270F}\u{FE0F}",  // ✏️
        "journal":     "\u{1F4DD}",   // 📝
        "gratitude":   "\u{1F64F}",   // 🙏
        "floss":       "\u{1F9B7}",   // 🦷
        "makeBed":     "\u{1F6CF}\u{FE0F}",   // 🛏
        "eatHealthy":  "\u{1F957}",   // 🥗
        "family":      "\u{1F46A}",   // 👪
    ]

    /// Best-effort fallback emoji when the iPhone didn't supply one. Returns
    /// "•" so a missing icon is visually distinct from a real glyph.
    static func emoji(for canonicalKey: String?) -> String {
        guard let key = canonicalKey, let emoji = emojiByCanonicalKey[key] else {
            return "\u{2022}"   // •
        }
        return emoji
    }
}
