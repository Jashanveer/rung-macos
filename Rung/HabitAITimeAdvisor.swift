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

    /// Returns the cached AI suggestion if any, or nil. The cached entry
    /// is dropped (and nil returned) when its time has slipped into the
    /// past — a chip saying "Try 10 AM" at 3 PM is stale clutter, so we
    /// force the caller to fall back to the deterministic baseline,
    /// which always lands after `now` via `nextSlot`.
    func cachedSuggestion(forKey key: String) -> HabitTimeSuggestion.Suggestion? {
        guard let cached = suggestionsByKey[key] else { return nil }
        if cached.time <= Date() {
            suggestionsByKey[key] = nil
            return nil
        }
        return cached
    }

    /// Build a cache key from material inputs — habit, today's date,
    /// calendar event signature, forecast signature, and a 30-minute
    /// bucket of `now` so the LLM result re-runs at most twice per hour
    /// instead of being frozen at the first inference of the day.
    /// Without the time bucket a 9 AM inference sticks until midnight,
    /// which is how "Try 10 AM" survives until 3 PM.
    func cacheKey(
        habit: Habit,
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        now: Date = Date()
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
        let bucket = Int(now.timeIntervalSinceReferenceDate / (30 * 60))
        return "\(habitId)|\(todayKey)|\(eventsSig)|\(forecastSig)|t:\(bucket)"
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

        let now = Date()
        let nowStr = formatter.string(from: now)
        let energyLine: String = {
            guard let f = forecast else {
                return "No sleep data yet — assume an average chronotype."
            }
            let nowEnergy = Int(f.energy(at: now).rounded())
            let peakStr = formatter.string(from: f.circadianPeak)
            let dlmoStr = formatter.string(from: f.predictedDLMO)
            return "Energy now: \(nowEnergy)/100. Acrophase ~\(peakStr). Melatonin onset ~\(dlmoStr)."
        }()

        let shapeLine: String = {
            switch shape {
            case .mentalPeak:   return "is a MENTAL task (deep work, learning, writing, code) — best in the morning cortisol-driven cognitive peak (~9 AM–12 PM)"
            case .physicalPeak: return "is PHYSICAL exercise (running, gym, sport) — best in the late-afternoon body-temperature acrophase (~3 PM–6 PM)"
            case .dip:          return "is a CHORE — fits the post-lunch dip (12 PM–4 PM)"
            case .windDown:     return "is CALMING — fits the wind-down window before bed"
            case .flexible:     return "is FLEXIBLE — fits any moderate-energy slot"
            }
        }()

        let kindGuidance: String
        if shape == .flexible {
            kindGuidance = "Local heuristics couldn't classify this title — YOU must decide its KIND. Pick MENTAL_PEAK / PHYSICAL_PEAK / DIP / WIND_DOWN / FLEXIBLE based on the title and what the activity is."
        } else {
            kindGuidance = "Local heuristics already classified this — keep the same KIND in your output unless the title clearly contradicts it."
        }

        return """
        You are scheduling one task on the user's calendar today. Pick the BEST 30-minute time AFTER the current time, classify the task's kind, and explain why in 6–10 words.

        Current time: \(nowStr).

        Task: "\(habit.title)" — \(shapeLine).

        Today's meetings:
        \(meetingLines.isEmpty ? "(no meetings)" : meetingLines)

        \(energyLine)

        \(kindGuidance)

        Kinds:
        - MENTAL_PEAK = cognitive deep work — coding, writing, learning, study, hard meetings.
        - PHYSICAL_PEAK = exercise / sport — running, gym, HIIT, lifting, cycling, climbing, dance, yoga done as workout.
        - DIP = low-effort chores — laundry, dishes, errands, admin email.
        - WIND_DOWN = calming pre-bed — reading, journal, gratitude, stretch, prayer, family chat.
        - FLEXIBLE = no strong preference — hydration, vitamins, social.

        Rules:
        - The TIME you pick MUST be later than the current time. Never suggest a time that has already passed today.
        - Pick a 30-minute slot that does NOT overlap any meeting.
        - For MENTAL_PEAK, prefer 9 AM–12 PM (cortisol-driven cognitive peak). Avoid the post-lunch dip.
        - For PHYSICAL_PEAK (exercise / running / gym / sport), prefer 3 PM–6 PM when body temperature, lung function, and reaction time peak. Morning 6 AM–8 AM is an acceptable fallback if the afternoon is fully booked.
        - For DIP, prefer 12 PM–4 PM. Never pick before 11 AM or after 5 PM.
        - For WIND_DOWN, prefer 7 PM–10 PM.
        - If the rest of today is too packed or the ideal window has already passed, pick the next available future slot today (or early tomorrow morning if nothing fits today) and acknowledge it ("only free slot left").

        Output EXACTLY this format on ONE line, nothing else:
        TIME: H:MM AM/PM | KIND: <ONE OF MENTAL_PEAK/PHYSICAL_PEAK/DIP/WIND_DOWN/FLEXIBLE> | REASON: <6–10 words>

        Example: TIME: 5:30 PM | KIND: PHYSICAL_PEAK | REASON: body-temp peak, sharpest physical window
        """
    }

    private func parseResponse(
        _ raw: String,
        shape: HabitTimeSuggestion.TaskShape,
        baseline: HabitTimeSuggestion.Suggestion?
    ) -> HabitTimeSuggestion.Suggestion? {
        // Expected: "TIME: 5:30 PM | KIND: PHYSICAL_PEAK | REASON: peak after meetings"
        // Tolerates the older "TIME | REASON" format (no KIND) by falling
        // back to the local-classified shape when KIND is missing.
        let parts = raw.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }

        var timePart = ""
        var kindPart: String?
        var reasonPart = ""
        for part in parts {
            if let r = part.range(of: "TIME:", options: .caseInsensitive), r.lowerBound == part.startIndex {
                timePart = String(part[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let r = part.range(of: "KIND:", options: .caseInsensitive), r.lowerBound == part.startIndex {
                kindPart = String(part[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let r = part.range(of: "REASON:", options: .caseInsensitive), r.lowerBound == part.startIndex {
                reasonPart = String(part[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !timePart.isEmpty, !reasonPart.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let parsedTime = formatter.date(from: timePart) else { return nil }
        let reasonString = reasonPart

        // Project the parsed clock time onto today.
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let parsedComps = cal.dateComponents([.hour, .minute], from: parsedTime)
        guard let resolvedTime = cal.date(
            bySettingHour: parsedComps.hour ?? 12,
            minute: parsedComps.minute ?? 0,
            second: 0,
            of: todayStart
        ) else { return nil }

        // Refuse times that have already passed today — the chip would
        // read "Try 10 AM" at 3 PM, which is exactly the bug we're
        // fixing. The caller falls back to the deterministic baseline,
        // whose `nextSlot` guarantees a future-of-now suggestion.
        guard resolvedTime > now else { return nil }

        // If the LLM's reason is empty / single-token, fall back to the
        // heuristic's label. We never want a chip with no explanation.
        let cleanedReason = reasonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedReason.split(separator: " ").count >= 2 else { return nil }

        // Resolve the final shape: the LLM gets the last word ONLY when
        // local heuristics couldn't decide (.flexible). When local was
        // specific we keep its decision — the LLM is allowed to disagree
        // about the time but not about whether "run" is mental or
        // physical, since drift on classification has compounding effects.
        let resolvedShape: HabitTimeSuggestion.TaskShape = {
            guard shape == .flexible, let kind = kindPart else { return shape }
            return Self.parseKind(kind) ?? shape
        }()

        return HabitTimeSuggestion.Suggestion(
            time: resolvedTime,
            isEnergyPeak: resolvedShape.isPeak,
            forecast: baseline?.forecast,
            scoreBreakdown: baseline?.scoreBreakdown ?? HabitTimeSuggestion.ScoreBreakdown(energy: 1, earliness: 0),
            shape: resolvedShape,
            aiReason: cleanedReason
        )
    }

    /// Map a KIND token from the LLM response back to a `TaskShape`.
    /// Tolerant of casing and punctuation since the LLM occasionally
    /// returns lowercase / hyphenated variants.
    private static func parseKind(_ raw: String) -> HabitTimeSuggestion.TaskShape? {
        let normalized = raw
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "MENTAL_PEAK", "MENTAL", "COGNITIVE":     return .mentalPeak
        case "PHYSICAL_PEAK", "PHYSICAL", "EXERCISE":  return .physicalPeak
        case "DIP", "CHORE":                           return .dip
        case "WIND_DOWN", "WINDDOWN", "CALM":          return .windDown
        case "FLEXIBLE":                               return .flexible
        default:                                       return nil
        }
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
