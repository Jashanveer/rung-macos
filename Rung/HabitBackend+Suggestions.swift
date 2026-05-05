import Foundation
#if canImport(EventKit)
import EventKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

extension HabitBackendStore {

    /// Refresh the cross-device daily suggestion payload.
    ///
    /// The flow on every call:
    /// 1. Compute a deterministic local payload from the inputs (events,
    ///    forecast, habits). Cheap — no network, no LLM.
    /// 2. Fetch the canonical payload from the backend (404 → nil).
    /// 3. Pick the winner: server payload wins when its `dataQuality`
    ///    is greater than or equal to ours; otherwise we win and we
    ///    upload our payload.
    /// 4. Publish the winner to `dailySuggestion`. UI re-renders.
    /// 5. If we won AND FoundationModels is available, kick off the
    ///    on-device LLM headline generation; when it lands we re-publish
    ///    + re-upload the payload with `aiHeadline` filled in.
    ///
    /// The whole thing is idempotent: re-entrant calls during a refresh
    /// are coalesced via `dailySuggestionRefreshTask`. Offline failures
    /// (no token, network error, server 5xx) are swallowed — the local
    /// payload still drives the UI through the existing fallback paths.
    @MainActor
    func refreshDailySuggestion(
        habits: [Habit],
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?,
        calendarsVisible: Int
    ) {
        // Coalesce: if a refresh is in flight, let it finish. The next
        // SwiftData / EventKit change will trigger a fresh call anyway.
        if dailySuggestionRefreshTask != nil { return }

        let local = DailySuggestionFactory.compute(
            habits: habits,
            todayKey: todayKey,
            events: events,
            forecast: forecast,
            aiHeadline: dailySuggestion?.aiHeadline,
            calendarsVisible: calendarsVisible,
            platform: DailySuggestionFactory.currentPlatform
        )

        // Publish locally right away so the UI doesn't stall waiting on
        // the network round-trip. The backend reconcile below either
        // confirms (no-op) or replaces with a richer remote payload.
        dailySuggestion = local

        guard isAuthenticated else {
            // No backend session — single-device or signed-out. Local
            // payload is the canonical one. Still kick off the LLM
            // headline so the user gets coached copy.
            generateAIHeadlineIfNeeded(
                habits: habits,
                todayKey: todayKey,
                events: events,
                forecast: forecast
            )
            return
        }

        dailySuggestionRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.dailySuggestionRefreshTask = nil } }

            let remote = try? await self.dailySuggestionRepository.get(dayKey: todayKey)
            await MainActor.run {
                let winner = Self.electDailySuggestion(local: local, remote: remote)
                if winner != self.dailySuggestion {
                    self.dailySuggestion = winner
                }
            }

            // Upload only when our local payload outranks whatever the
            // server has. Skips work for secondary devices that read a
            // richer payload than they could produce themselves.
            if Self.localShouldUpload(local: local, remote: remote) {
                _ = try? await self.dailySuggestionRepository.upsert(local)
            }

            // Whichever device just won the election is the right one
            // to spend an LLM inference on the headline — it'll get
            // baked into the next upload via `generateAIHeadlineIfNeeded`.
            await MainActor.run {
                self.generateAIHeadlineIfNeeded(
                    habits: habits,
                    todayKey: todayKey,
                    events: events,
                    forecast: forecast
                )
            }
        }
    }

    /// Pure election rule. Server payload wins ties on `dataQuality`
    /// because a network round-trip implies it was authoritative; our
    /// local copy only takes over when it has *strictly* more signal.
    /// `nonisolated` so unit tests can call it from any context — there
    /// is no shared state to protect.
    nonisolated static func electDailySuggestion(
        local: DailySuggestionPayload,
        remote: DailySuggestionPayload?
    ) -> DailySuggestionPayload {
        guard let remote else { return local }
        if remote.dayKey != local.dayKey { return local }
        if remote.dataQuality >= local.dataQuality { return remote }
        return local
    }

    /// Should this device upload its locally-computed payload?
    /// Yes when there's no remote yet, or when ours strictly beats it.
    nonisolated static func localShouldUpload(
        local: DailySuggestionPayload,
        remote: DailySuggestionPayload?
    ) -> Bool {
        guard let remote else { return true }
        if remote.dayKey != local.dayKey { return true }
        return local.dataQuality > remote.dataQuality
    }

    /// On-device LLM coaching line. Runs at most once per (day,
    /// metrics) bucket to avoid burning inferences on every redraw.
    /// When the headline lands we re-publish + re-upload so peer
    /// devices pick it up on their next refresh.
    @MainActor
    private func generateAIHeadlineIfNeeded(
        habits: [Habit],
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?
    ) {
        // Bail early if we already have a usable headline for today —
        // the existing payload's headline survives unless a higher-
        // quality device overwrote it.
        if let current = dailySuggestion,
           current.dayKey == todayKey,
           current.aiHeadline != nil { return }

        #if canImport(FoundationModels)
        Task { [weak self] in
            guard let self else { return }
            guard #available(macOS 26.0, iOS 26.0, *) else { return }
            do {
                let prompt = Self.buildHeadlinePrompt(
                    habits: habits,
                    todayKey: todayKey,
                    events: events,
                    forecast: forecast
                )
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let line = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return }
                await MainActor.run {
                    guard var current = self.dailySuggestion,
                          current.dayKey == todayKey else { return }
                    current.aiHeadline = line
                    self.dailySuggestion = current
                }
                if self.isAuthenticated,
                   let payload = await MainActor.run(body: { self.dailySuggestion }),
                   payload.dayKey == todayKey {
                    _ = try? await self.dailySuggestionRepository.upsert(payload)
                }
            } catch {
                // Silent: the deterministic chip + SmartGreeting fallback
                // already cover the empty-headline case.
            }
        }
        #endif
    }

    /// Same coaching prompt CenterPanel was building locally, lifted out
    /// so the suggestion coordinator can run it on whichever device won
    /// the election. Kept verbatim where possible — copy is the user's
    /// signal that the new flow matches the old behaviour.
    private static func buildHeadlinePrompt(
        habits: [Habit],
        todayKey: String,
        events: [CalendarEvent],
        forecast: EnergyForecast?
    ) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"

        let pendingHabits = habits.filter { habit in
            switch habit.entryType {
            case .habit: return !habit.completedDayKeys.contains(todayKey)
            case .task:  return !habit.isTaskCompleted
            }
        }
        if pendingHabits.isEmpty {
            return """
            Generate a single short friendly greeting (max 6 words) for a habit tracker app. \
            It's \(timeOfDay). The user has finished today's list. Be warm, casual, and encouraging. \
            Output only the greeting, nothing else.
            """
        }

        let pendingTitles = pendingHabits.map(\.title)
        let pendingPreview = pendingTitles.prefix(3).joined(separator: ", ")
        let nonAllDay = events.filter { !$0.isAllDay }
        let meetings = nonAllDay.count
        let meetingsLine = meetings > 0
            ? "\(meetings) meeting\(meetings == 1 ? "" : "s") today"
            : "calendar is open today"
        let sleepLine: String = {
            guard let forecast else { return "no sleep data" }
            let debt = forecast.sleepDebtHours
            if debt >= 1 {
                return String(format: "sleep debt: %.1fh — recovery matters today", debt)
            }
            if debt <= -1 {
                return "well rested"
            }
            return "sleep on track"
        }()

        return """
        You are a coach inside a habit-tracker app. Output a single short \
        next-action sentence (max 10 words) telling the user the one thing \
        to do next. Be specific to the data, not generic. No emojis, no \
        opening salutation, no exclamation marks.

        Time of day: \(timeOfDay).
        Pending today: \(pendingPreview)\(pendingTitles.count > 3 ? " and \(pendingTitles.count - 3) more" : "").
        Schedule: \(meetingsLine).
        Sleep: \(sleepLine).
        """
    }
}
