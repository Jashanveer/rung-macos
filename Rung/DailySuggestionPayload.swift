import Foundation
#if os(iOS)
import UIKit
#endif

/// A single day's worth of UI-facing suggestion data — the AI greeting,
/// today's meeting summary, and a per-habit "Try HH:MM" hint — packaged
/// for cross-device sync.
///
/// **Why this exists.** Each device computes the meeting summary, the
/// AI headline, and the per-habit time chip independently from EventKit
/// + the on-device LLM. EventKit visibility differs per device (a Mac
/// often only sees iCloud, while the iPhone sees iCloud + Google +
/// Exchange + local), and the LLM is non-deterministic, so the same
/// task ends up with different timings and different headline copy on
/// each device. That's the user-visible "my Mac says 21:00, my iPhone
/// says 19:00" bug.
///
/// The fix: backend stores the canonical payload for each (user, day).
/// Devices race to write it on first launch of the day; whichever
/// device has the richest calendar view (highest `dataQuality`) wins.
/// Subsequent devices read what's there instead of recomputing — they
/// only overwrite if their score is strictly higher.
///
/// **Mac-only (or iPhone-only) users**: there's no second device to
/// diverge against, so the local payload is also the canonical one.
/// The election rule is a no-op for them.
struct DailySuggestionPayload: Codable, Equatable {
    /// `yyyy-MM-dd` — the calendar day this payload describes.
    let dayKey: String
    /// AI-generated coaching headline (e.g. "Complete laundry before
    /// bed tonight"). nil while the on-device LLM hasn't responded
    /// yet, OR on devices where FoundationModels is unavailable
    /// (older OS). UI falls back to `SmartGreeting` when nil.
    var aiHeadline: String?
    /// Count of non-all-day events on this day. All-day items are
    /// excluded because they're typically birthdays / holidays, not
    /// meetings that crowd a habit.
    var meetingCount: Int
    /// Sum of non-all-day event durations, in minutes.
    var meetingMinutes: Int
    /// Per-habit "Try HH:MM — reason" hint. Only populated for habits
    /// that aren't already done today.
    var perHabit: [HabitSuggestion]
    /// Election score. Higher = richer calendar view. The accepting
    /// server (and a defensive client) only overwrite an existing
    /// payload when the incoming score is **strictly greater** than
    /// the stored one — that way a Mac that only sees iCloud doesn't
    /// downgrade an iPhone payload that fused four calendars.
    let dataQuality: Int
    /// Wall-clock timestamp when this payload was assembled. Used for
    /// staleness checks and tie-breakers.
    let generatedAt: Date
    /// Originating device platform identifier ("ios" / "ipados" /
    /// "macos"). Aids debugging "why does my Mac payload look weird"
    /// — a glance at the dashboard tells you who wrote it.
    let generatedBy: String
}

struct HabitSuggestion: Codable, Equatable {
    /// Backend identifier when the habit has synced. nil for local-only
    /// habits that haven't been pushed yet — the UI falls back to title
    /// matching in that case so a brand-new habit still gets a chip.
    let habitId: Int64?
    /// Free-text title at the time the payload was written. Used as the
    /// fallback identifier when `habitId` is nil and as a sanity check
    /// when the local title has since been edited.
    let habitTitle: String
    /// Wall-clock pick (within the day) for the suggested slot.
    let time: Date
    /// Pre-rendered chip label ("Try 5:30 PM — your peak after meetings").
    /// We send the rendered string instead of recomputing per device so
    /// every reader sees the same copy — the LLM reason in particular
    /// can vary run-to-run, and we want the canonical one.
    let label: String
    /// True when the picked slot lands inside the user's modeled
    /// circadian peak. Drives the "your energy peaks then" copy.
    let isEnergyPeak: Bool
    /// Optional richer reason from the on-device LLM. Persisted so
    /// secondary devices (without the LLM, or with a different LLM
    /// run) display the same reasoning.
    let aiReason: String?
}

/// Pure factory for assembling a `DailySuggestionPayload` from local
/// inputs. Stateless and synchronous — no network, no actor hops, no
/// LLM. The on-device LLM headline is layered in by the coordinator
/// after the deterministic data has already been published.
enum DailySuggestionFactory {
    static func compute(
        habits: [Habit],
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        aiHeadline: String? = nil,
        calendarsVisible: Int,
        platform: String,
        now: Date = Date()
    ) -> DailySuggestionPayload {
        let nonAllDay = events.filter { !$0.isAllDay }
        let meetingCount = nonAllDay.count
        let meetingMinutes = nonAllDay.reduce(0) { acc, event in
            acc + max(0, Int(event.duration / 60))
        }

        let perHabit: [HabitSuggestion] = habits.compactMap { habit in
            // Skip already-completed entries — the chip would be wasted.
            let isDone: Bool = {
                switch habit.entryType {
                case .habit: return habit.completedDayKeys.contains(todayKey)
                case .task:  return habit.isTaskCompleted
                }
            }()
            guard !isDone else { return nil }

            let shape = HabitTimeSuggestion.TaskShape.classify(
                canonicalKey: habit.canonicalKey,
                title: habit.title
            )
            guard let suggestion = HabitTimeSuggestion.suggest(
                events: nonAllDay,
                forecast: forecast,
                now: now,
                shape: shape
            ) else { return nil }

            return HabitSuggestion(
                habitId: habit.backendId,
                habitTitle: habit.title,
                time: suggestion.time,
                label: suggestion.label,
                isEnergyPeak: suggestion.isEnergyPeak,
                aiReason: suggestion.aiReason
            )
        }

        // Score formula: every visible calendar account is worth a
        // hundred event-points so a device with three calendars and
        // zero events still outranks one with one calendar and ten
        // events. The point is "richer source" not "busier day".
        let dataQuality = max(0, calendarsVisible) * 100 + meetingCount

        return DailySuggestionPayload(
            dayKey: todayKey,
            aiHeadline: aiHeadline,
            meetingCount: meetingCount,
            meetingMinutes: meetingMinutes,
            perHabit: perHabit,
            dataQuality: dataQuality,
            generatedAt: now,
            generatedBy: platform
        )
    }

    /// Default platform tag used when the coordinator doesn't override.
    /// Kept here so unit tests can pin it deterministically.
    static var currentPlatform: String {
        #if os(macOS)
        return "macos"
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { return "ipados" }
        return "ios"
        #else
        return "unknown"
        #endif
    }
}
