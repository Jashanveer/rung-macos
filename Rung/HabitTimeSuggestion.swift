import Foundation

/// Picks a "best time today" slot for a new habit by combining the
/// user's actual calendar with their energy curve. The output is a
/// concrete clock-time hint — "Try 10:30 AM" — that the AddHabitBar
/// surfaces below the title field. Cheap to compute (no HK fetch),
/// safe to call on the main actor.
///
/// The algorithm in plain English:
/// 1. Build a list of free 30-minute slots between now and 9 PM,
///    skipping anything covered by a calendar event.
/// 2. Score each slot by how close it lands to the user's circadian
///    peak (closer = better) AND how late in the day it is (slight
///    nudge toward earlier slots so users don't push commitment to
///    the evening).
/// 3. Return the highest-scoring slot, or nil if today is too packed
///    or it's already past evening.
///
/// This is intentionally NOT a full scheduler — we don't reserve
/// the slot, don't notify, and don't persist. It's a one-line UI
/// hint. Reminders + scheduling live in `HabitReminder`.
enum HabitTimeSuggestion {

    /// Public entry point. Pass in today's calendar events (already
    /// filtered to today) and an `EnergyForecast` snapshot. Either
    /// can be empty / nil — the function degrades gracefully.
    /// Returns a suggestion or nil if no good slot exists.
    static func suggest(
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        now: Date = Date(),
        latestHourOfDay: Int = 21,
        slotDurationMinutes: Int = 30
    ) -> Suggestion? {
        let cal = Calendar.current
        let endOfWindow = cal.date(bySettingHour: latestHourOfDay, minute: 0, second: 0, of: now) ?? now
        guard endOfWindow > now else { return nil }

        // Bucket free slots in 30-min increments starting at the next
        // round half-hour after `now`.
        let slotStart = nextSlot(after: now, slotMinutes: slotDurationMinutes)
        guard slotStart < endOfWindow else { return nil }

        var slots: [Date] = []
        var t = slotStart
        let slotInterval = TimeInterval(slotDurationMinutes * 60)
        while t.addingTimeInterval(slotInterval) <= endOfWindow {
            if !overlaps(slot: t, duration: slotInterval, with: events) {
                slots.append(t)
            }
            t = t.addingTimeInterval(slotInterval)
        }
        guard !slots.isEmpty else { return nil }

        // Score each free slot. Higher score = better.
        // - Energy alignment: 1.0 - normalized distance to circadian peak
        //   (clamped at 6h away from peak so all slots get *some* signal).
        // - Earliness preference: gentle decay so a 10am slot beats a 6pm
        //   slot at equal energy.
        let peak = forecast?.circadianPeak
        let scored = slots.map { slot -> (Date, Double, Double) in
            let energyScore: Double = {
                guard let peak else { return 0.5 }
                let hours = abs(slot.timeIntervalSince(peak) / 3600)
                let clamped = min(hours, 6) / 6
                return 1.0 - clamped
            }()
            let hour = Double(cal.component(.hour, from: slot))
            // 0..1 with 9am=1.0, 9pm=0.5 — gentle linear decay.
            let earlinessScore = max(0, 1.0 - (hour - 9.0) / 24.0)
            return (slot, energyScore, earlinessScore)
        }

        // Combine: 70% energy, 30% earliness.
        let best = scored.max(by: { lhs, rhs in
            let lhsScore = 0.7 * lhs.1 + 0.3 * lhs.2
            let rhsScore = 0.7 * rhs.1 + 0.3 * rhs.2
            return lhsScore < rhsScore
        })
        guard let pick = best else { return nil }

        return Suggestion(
            time: pick.0,
            isEnergyPeak: pick.1 >= 0.85,
            forecast: forecast,
            scoreBreakdown: ScoreBreakdown(energy: pick.1, earliness: pick.2)
        )
    }

    private static func nextSlot(after now: Date, slotMinutes: Int) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard let hour = comps.hour, let minute = comps.minute else { return now }
        let bucketed = (minute / slotMinutes + 1) * slotMinutes
        var newComps = comps
        if bucketed >= 60 {
            newComps.hour = hour + 1
            newComps.minute = bucketed - 60
        } else {
            newComps.minute = bucketed
        }
        return cal.date(from: newComps) ?? now
    }

    private static func overlaps(slot: Date, duration: TimeInterval, with events: [CalendarEvent]) -> Bool {
        let slotEnd = slot.addingTimeInterval(duration)
        return events.contains { event in
            !event.isAllDay && event.startDate < slotEnd && event.endDate > slot
        }
    }

    struct Suggestion {
        let time: Date
        /// True when this slot is within ~30 minutes of the user's
        /// circadian peak. Drives a different UI label so the user
        /// sees *why* this time was picked.
        let isEnergyPeak: Bool
        let forecast: EnergyForecast?
        let scoreBreakdown: ScoreBreakdown

        /// User-facing label for the suggestion chip.
        /// Examples:
        ///   "Try 10:30 AM — your energy peaks then"
        ///   "Try 4:00 PM — first free slot"
        var label: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let timeStr = formatter.string(from: time)
            if isEnergyPeak, forecast?.chronotypeStable == true {
                return "Try \(timeStr) — your energy peaks then"
            }
            if isEnergyPeak {
                return "Try \(timeStr) — peak focus window"
            }
            return "Try \(timeStr) — first free slot"
        }
    }

    struct ScoreBreakdown: Equatable {
        let energy: Double
        let earliness: Double
    }
}
