import Foundation

/// Per-habit reminder configuration. Replaces the older coarse
/// `Habit.reminderWindow` (morning / afternoon / evening) with explicit,
/// composable reminder rules. A single habit can have many reminders —
/// e.g. "remind at 7:00 weekdays AND when calendar shows a free 30-min
/// block AND when sleep insights say my energy peaks."
///
/// Wire-format mirrors the backend `habit_reminders` table introduced
/// in V18: id is the backend row id, nil for unsynced rows; payload
/// semantics depend on `kind`.
struct HabitReminder: Codable, Identifiable, Hashable {
    /// Backend id; nil for a reminder that hasn't synced yet.
    var id: Int64?
    /// Reminder type.
    var kind: Kind
    /// Free-form payload whose semantics depend on `kind`. Kept
    /// opaque so we can extend the kinds without a wire-format change.
    var payload: String?
    /// ISO-weekday bitmask: Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32,
    /// Sun=64. nil or 0 means "every day."
    var weekdayMask: Int?
    /// How long the user can snooze this reminder, in minutes. nil/0
    /// means snooze isn't offered.
    var snoozeMinutes: Int?
    /// Disabled reminders persist but don't fire — lets the user toggle
    /// off without losing their schedule.
    var enabled: Bool

    /// Wire-format raw values match the backend's `HabitReminderKind`
    /// enum (V18 Spring Boot service): UPPER_SNAKE_CASE strings. iOS
    /// keeps Swift-friendly case names internally and bridges via the
    /// rawValue mapping declared here.
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// One or more wall-clock times. `payload` is a comma-separated
        /// "HH:mm" list, e.g. `"08:00,14:00"`.
        case timeOfDay = "TIME_OF_DAY"
        /// Geofenced reminder. `payload` is an opaque identifier the
        /// client maps to a saved location (we don't store coordinates
        /// server-side — privacy + no reverse-geocode round-trip).
        case location = "LOCATION"
        /// Fires after a calendar event ends. `payload` is either an
        /// EventKit identifier or a category keyword like "meeting".
        case afterCalendarEvent = "AFTER_CALENDAR_EVENT"
        /// Fires when the user's energy curve hits a peak (or trough,
        /// per `payload`). Drives the "remind me when energy is high"
        /// product story — combines `EnergyForecast` + a notification.
        case energyPeak = "ENERGY_PEAK"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .timeOfDay:          return "At a time"
            case .location:           return "When I arrive"
            case .afterCalendarEvent: return "After a meeting"
            case .energyPeak:         return "When my energy peaks"
            }
        }

        var systemImage: String {
            switch self {
            case .timeOfDay:          return "clock.fill"
            case .location:           return "location.fill"
            case .afterCalendarEvent: return "calendar.badge.clock"
            case .energyPeak:         return "bolt.heart.fill"
            }
        }
    }

    static let allWeekdays: Int = (1 << 7) - 1  // Mon..Sun mask 0b1111111 = 127

    /// Human-readable summary used in row UI. Falls back to a generic
    /// label per kind when the payload doesn't parse into anything
    /// nicer; never crashes on malformed payloads.
    var summary: String {
        let prefix: String
        switch kind {
        case .timeOfDay:
            prefix = HabitReminder.formatTimes(payload) ?? "On a schedule"
        case .location:
            prefix = (payload?.isEmpty == false) ? (payload ?? "At a saved place") : "At a saved place"
        case .afterCalendarEvent:
            prefix = (payload?.isEmpty == false) ? "After \(payload!)" : "After a meeting"
        case .energyPeak:
            switch payload {
            case "high":  prefix = "When my energy is high"
            case "low":   prefix = "When my energy is low"
            default:      prefix = "When my energy peaks"
            }
        }
        let suffix = HabitReminder.formatWeekdays(weekdayMask)
        guard let suffix else { return prefix }
        return "\(prefix) · \(suffix)"
    }

    /// Two new-style reminders are user-equivalent if they describe the
    /// same trigger. Used to deduplicate when reconciling against the
    /// backend response after a write.
    func sameTriggerAs(_ other: HabitReminder) -> Bool {
        kind == other.kind
            && (payload ?? "") == (other.payload ?? "")
            && (weekdayMask ?? Self.allWeekdays) == (other.weekdayMask ?? Self.allWeekdays)
    }

    private static func formatTimes(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let pieces = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !pieces.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "h:mm a"
        let formatted = pieces.compactMap { input -> String? in
            guard let date = formatter.date(from: input) else { return nil }
            return outFormatter.string(from: date)
        }
        return formatted.isEmpty ? nil : formatted.joined(separator: ", ")
    }

    private static func formatWeekdays(_ mask: Int?) -> String? {
        guard let mask, mask != 0, mask != allWeekdays else { return nil }
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let active = names.enumerated().compactMap { index, label in
            (mask >> index) & 1 == 1 ? label : nil
        }
        guard !active.isEmpty else { return nil }
        // Recognise the two common compound buckets so the UI reads
        // naturally instead of "Mon, Tue, Wed, Thu, Fri".
        if active == ["Mon", "Tue", "Wed", "Thu", "Fri"] { return "Weekdays" }
        if active == ["Sat", "Sun"] { return "Weekends" }
        return active.joined(separator: ", ")
    }
}
