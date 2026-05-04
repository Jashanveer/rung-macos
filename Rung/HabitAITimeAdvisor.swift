import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM advisor that generates per-habit time suggestions
/// richer than the deterministic heuristic. macOS 26+ / iOS 26+ only —
/// runs Apple's `LanguageModelSession` against a structured prompt that
/// includes today's calendar, the energy curve, and the habit's shape,
/// then returns a one-line "Try 5:30 PM — your peak after meetings" tip.
///
/// Falls back silently to the heuristic on older OSes (the existing
/// `HabitTimeSuggestion.suggest` already produces a valid result; the
/// AI advisor's role is to *upgrade* its label and time when possible).
///
/// Costs: each inference is ~1–2 s on Apple silicon. We cache per
/// (habit, day, calendar fingerprint, forecast fingerprint) so the call
/// runs at most once per material change in any of those inputs.
@MainActor
final class HabitAITimeAdvisor: ObservableObject {
    static let shared = HabitAITimeAdvisor()

    /// Per-habit cached suggestion, keyed by `cacheKey`. Surfaced to
    /// SwiftUI views so they can re-render when fresh inferences land.
    @Published private(set) var suggestionsByKey: [String: HabitTimeSuggestion.Suggestion] = [:]

    /// In-flight task per habit so concurrent SwiftUI re-renders don't
    /// fire the same prompt twice. Cancelled when the inputs change.
    private var inflight: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Returns the cached AI suggestion if any, or nil. Use alongside
    /// the deterministic `HabitTimeSuggestion.Suggestion` so the chip
    /// always has *something* to render — the AI version takes over
    /// once the inference resolves.
    func cachedSuggestion(forKey key: String) -> HabitTimeSuggestion.Suggestion? {
        suggestionsByKey[key]
    }

    /// Build a cache key from material inputs — habit, today's date,
    /// calendar event signature, and forecast signature. Stable across
    /// SwiftUI rerenders that don't change anything.
    func cacheKey(
        habit: Habit,
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?
    ) -> String {
        let eventsSig = events
            .filter { !$0.isAllDay }
            .map { "\($0.id):\(Int($0.startDate.timeIntervalSinceReferenceDate)):\(Int($0.endDate.timeIntervalSinceReferenceDate))" }
            .sorted()
            .joined(separator: "|")
        let forecastSig: String = {
            guard let f = forecast else { return "no-fc" }
            let wakeMin = Int(f.wakeTime.timeIntervalSinceReferenceDate / 60)
            let peakMin = Int(f.circadianPeak.timeIntervalSinceReferenceDate / 60)
            return "wake:\(wakeMin)|peak:\(peakMin)|debt:\(Int(f.sleepDebtHours * 10))"
        }()
        let habitId = habit.localUUID?.uuidString ?? habit.title
        return "\(habitId)|\(todayKey)|\(eventsSig)|\(forecastSig)"
    }

    /// Kick off an AI suggestion for `habit`. Idempotent — repeated
    /// calls with the same inputs reuse the cached result.
    func ensureSuggestion(
        for habit: Habit,
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?
    ) {
        let key = cacheKey(habit: habit, todayKey: todayKey, events: events, forecast: forecast)
        if suggestionsByKey[key] != nil { return }
        if inflight[key] != nil { return }
        guard isLLMAvailable else { return }

        inflight[key] = Task { [weak self, habit, events, forecast] in
            await self?.runInference(
                habit: habit,
                todayKey: todayKey,
                events: events,
                forecast: forecast,
                cacheKey: key
            )
        }
    }

    private var isLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    private func runInference(
        habit: Habit,
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        cacheKey: String
    ) async {
        defer { inflight[cacheKey] = nil }
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else { return }

        // First compute the deterministic suggestion as a strong baseline
        // — when the LLM produces nothing parseable, we fall back to it
        // and the chip still renders something useful.
        let shape = HabitTimeSuggestion.TaskShape.classify(
            canonicalKey: habit.canonicalKey,
            title: habit.title
        )
        let baseline = HabitTimeSuggestion.suggest(
            events: events,
            forecast: forecast,
            shape: shape
        )

        let prompt = buildPrompt(
            habit: habit,
            shape: shape,
            events: events,
            forecast: forecast
        )

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = parseResponse(raw, shape: shape, baseline: baseline) {
                suggestionsByKey[cacheKey] = parsed
            } else if let baseline {
                // Couldn't parse — keep the deterministic baseline so the
                // chip stays useful instead of going blank.
                suggestionsByKey[cacheKey] = baseline
            }
        } catch {
            if let baseline {
                suggestionsByKey[cacheKey] = baseline
            }
        }
        #endif
    }

    private func buildPrompt(
        habit: Habit,
        shape: HabitTimeSuggestion.TaskShape,
        events: [CalendarEvent],
        forecast: EnergyForecast?
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let meetingLines = events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { "- \(formatter.string(from: $0.startDate))–\(formatter.string(from: $0.endDate)): \($0.title)" }
            .joined(separator: "\n")

        let energyLine: String = {
            guard let f = forecast else {
                return "No sleep data yet — assume an average chronotype."
            }
            let now = Date()
            let nowEnergy = Int(f.energy(at: now).rounded())
            let peakStr = formatter.string(from: f.circadianPeak)
            let dlmoStr = formatter.string(from: f.predictedDLMO)
            return "Energy now: \(nowEnergy)/100. Acrophase ~\(peakStr). Melatonin onset ~\(dlmoStr)."
        }()

        let shapeLine: String = {
            switch shape {
            case .peak:     return "needs the user's PEAK alertness (deep work / hard exercise)"
            case .dip:      return "is a CHORE — fits the post-lunch dip (12 PM–4 PM)"
            case .windDown: return "is CALMING — fits the wind-down window before bed"
            case .flexible: return "is FLEXIBLE — fits any moderate-energy slot"
            }
        }()

        return """
        You are scheduling one task on the user's calendar today. Pick the BEST 30-minute time today and explain why in 6–10 words.

        Task: "\(habit.title)" — \(shapeLine).

        Today's meetings:
        \(meetingLines.isEmpty ? "(no meetings)" : meetingLines)

        \(energyLine)

        Rules:
        - Pick a 30-minute slot that does NOT overlap any meeting.
        - For PEAK tasks, prefer slots near the acrophase. Avoid the post-lunch dip.
        - For DIP tasks, prefer 12 PM–4 PM. Never pick before 11 AM or after 5 PM.
        - For WIND-DOWN tasks, prefer 7 PM–10 PM.
        - If today is too packed, pick a small gap and acknowledge it ("only free slot").

        Output EXACTLY this format on ONE line, nothing else:
        TIME: H:MM AM/PM | REASON: <6–10 words>

        Example: TIME: 5:30 PM | REASON: peak after meetings clear, sharpest window
        """
    }

    private func parseResponse(
        _ raw: String,
        shape: HabitTimeSuggestion.TaskShape,
        baseline: HabitTimeSuggestion.Suggestion?
    ) -> HabitTimeSuggestion.Suggestion? {
        // Expected: "TIME: 5:30 PM | REASON: peak after meetings clear"
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }

        let timePart = parts[0].trimmingCharacters(in: .whitespaces)
        let reasonPart = parts[1].trimmingCharacters(in: .whitespaces)

        guard let timeColon = timePart.range(of: "TIME:", options: .caseInsensitive),
              let reasonColon = reasonPart.range(of: "REASON:", options: .caseInsensitive) else {
            return nil
        }

        let timeString = String(timePart[timeColon.upperBound...]).trimmingCharacters(in: .whitespaces)
        let reasonString = String(reasonPart[reasonColon.upperBound...]).trimmingCharacters(in: .whitespaces)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let parsedTime = formatter.date(from: timeString) else { return nil }

        // Project the parsed clock time onto today.
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let parsedComps = cal.dateComponents([.hour, .minute], from: parsedTime)
        guard let resolvedTime = cal.date(
            bySettingHour: parsedComps.hour ?? 12,
            minute: parsedComps.minute ?? 0,
            second: 0,
            of: todayStart
        ) else { return nil }

        // If the LLM's reason is empty / single-token, fall back to the
        // heuristic's label. We never want a chip with no explanation.
        let cleanedReason = reasonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedReason.split(separator: " ").count >= 2 else { return nil }

        return HabitTimeSuggestion.Suggestion(
            time: resolvedTime,
            isEnergyPeak: shape.isPeak,
            forecast: baseline?.forecast,
            scoreBreakdown: baseline?.scoreBreakdown ?? HabitTimeSuggestion.ScoreBreakdown(energy: 1, earliness: 0),
            shape: shape,
            aiReason: cleanedReason
        )
    }

    /// Drop the cache. Called by SettingsPanel when the user signs out
    /// or clears local data so a re-signed-in account doesn't see ghost
    /// suggestions from the prior user.
    func clearAll() {
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        suggestionsByKey.removeAll()
    }
}
