import FoundationModels
import SwiftData
import SwiftUI

struct CenterPanel: View {
    let habits: [Habit]
    let todayKey: String
    @Binding var newHabitTitle: String
    @Binding var newEntryType: HabitEntryType

    let metrics: HabitMetrics
    var clusters: [AccountabilityDashboard.HabitTimeCluster] = []
    let stampNamespace: Namespace.ID
    let stampStagingIds: Set<PersistentIdentifier>
    var enableStampMatchedGeometry: Bool = true
    /// Today is protected by a streak freeze. When true the list renders every
    /// habit in its frozen (icy-blue) state and does not hide completed ones.
    var isFrozenToday: Bool = false
    let onAddHabit: (HabitEntryType, Date?, CanonicalHabit?, Int?, TaskPriority?) -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void
    /// Backend store routed into AddHabitBar to enable the LLM
    /// frequency-parse fallback. Optional so previews / tests can omit it.
    var backendStore: HabitBackendStore? = nil

    /// Drives the subtle "X meetings today" pill that floats below the
    /// greeting. The pill replaces the older purple `CalendarInsightsBanner`
    /// — same data, far less visual weight.
    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var sleepService = SleepInsightsService.shared

    @State private var aiGreeting: String?
    @State private var hasRequestedGreeting = false

    /// Calendar-aware "best time today" suggestion. Recomputed each
    /// render using the live forecast + today's events; cheap because
    /// the algorithm is pure (no HK fetch). Hidden when there's no
    /// good slot left in the day.
    private var timeSuggestion: HabitTimeSuggestion.Suggestion? {
        guard !pendingHabits.isEmpty else { return nil }
        return HabitTimeSuggestion.suggest(
            events: calendarService.todaysEvents,
            forecast: sleepService.forecast
        )
    }

    private var pendingHabits: [Habit] {
        if isFrozenToday { return habits }
        let today = DateKey.date(from: todayKey)
        return habits.filter { habit in
            // Weekly-target habits disappear from today's list the moment
            // the user meets their commitment for the ISO week — they stay
            // gone until the week rolls over, then reappear automatically
            // because `weeklyTargetReached` resets on a new week.
            if habit.isFrequencyBased && habit.weeklyTargetReached(containing: today) {
                return stampStagingIds.contains(habit.persistentModelID)
            }
            let isDone: Bool = {
                switch habit.entryType {
                case .habit: return habit.completedDayKeys.contains(todayKey)
                case .task:  return habit.isTaskCompleted
                }
            }()
            return !isDone || stampStagingIds.contains(habit.persistentModelID)
        }
    }
    private var hasOverdueTask: Bool {
        habits.contains { $0.entryType == .task && $0.isOverdue() }
    }
    /// Live mirror of `Habit.hasDuplicate` against the current input so the
    /// AddHabitBar can warn the user *before* they hit Add.
    private var hasDuplicateEntry: Bool {
        Habit.hasDuplicate(title: newHabitTitle, entryType: newEntryType, in: habits)
    }
    private var isEmpty: Bool { habits.isEmpty }
    private var allDoneToday: Bool { !isFrozenToday && !habits.isEmpty && pendingHabits.isEmpty }
    private var isCompact: Bool { !isEmpty && !allDoneToday }

    var body: some View {
        VStack(spacing: isCompact ? 10 : 16) {
            if !isCompact {
                Spacer()
            }

            TodayHeader(greeting: displayGreeting, isCompact: isCompact)

            // The pill renders whenever today has at least one timed
            // event. We don't gate on `isAuthorized` — the demo seeder
            // (DEBUG only) bypasses EventKit, and real users without
            // permission have an empty `todaysEvents` list anyway, so
            // dropping the guard simplifies the condition without
            // surfacing the pill spuriously.
            if todaysMeetingCount > 0 {
                MeetingsPill(
                    count: todaysMeetingCount,
                    totalMinutes: calendarService.meetingMinutesToday
                )
                .transition(.opacity.combined(with: .offset(y: -4)))
            }

            AddHabitBar(
                newHabitTitle: $newHabitTitle,
                selectedType: $newEntryType,
                hasOverdueTask: hasOverdueTask,
                hasDuplicateEntry: hasDuplicateEntry,
                backendStore: backendStore,
                onAddHabit: onAddHabit
            )
                .frame(maxWidth: 520)

            if isEmpty {
                Text("Add your first task to get started")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                Spacer()
            } else if allDoneToday {
                VStack(spacing: 8) {
                    Text("All done for today")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Your list is complete for today.\nSee you tomorrow.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    if let suggestion = timeSuggestion {
                        SuggestedTimePill(suggestion: suggestion)
                            .frame(maxWidth: 520)
                            .padding(.bottom, 4)
                    }
                    HabitListSection(
                        habits: pendingHabits,
                        todayKey: todayKey,
                        onToggle: onToggleHabit,
                        onDelete: onDeleteHabit,
                        clusters: clusters,
                        stampNamespace: enableStampMatchedGeometry ? stampNamespace : nil,
                        isFrozenToday: isFrozenToday
                    )
                    .padding(.top, 4)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: 680)
            }
        }
        .padding(.top, isCompact ? 16 : 0)
        .padding(.bottom, 8)
        .frame(maxWidth: 860, maxHeight: .infinity)
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isEmpty)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: allDoneToday)
        .animation(.smooth(duration: 0.2), value: metrics.doneToday)
        .onAppear {
            guard !hasRequestedGreeting else { return }
            hasRequestedGreeting = true
            requestAIGreeting()
        }
        .task {
            #if DEBUG
            // Seed a representative "busy day" so the MeetingsPill can
            // be previewed on dev builds without Calendar permission.
            // No-op once real events are present.
            calendarService.loadDemoEventsIfEmpty()
            #endif
        }
    }

    private var displayGreeting: String {
        aiGreeting ?? SmartGreeting.generate(
            habits: habits,
            todayKey: todayKey,
            doneToday: metrics.doneToday,
            totalHabits: metrics.totalHabits,
            currentStreak: metrics.currentPerfectStreak
        )
    }

    private var todaysMeetingCount: Int {
        calendarService.todaysEvents.filter { !$0.isAllDay }.count
    }

    private func requestAIGreeting() {
        Task {
            guard #available(iOS 26.0, macOS 26.0, *) else { return }
            do {
                let session = LanguageModelSession()
                let prompt = buildGreetingPrompt()
                let response = try await session.respond(to: prompt)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.smooth(duration: 0.3)) {
                        aiGreeting = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                // Fallback to static greeting silently
            }
        }
    }

    private func buildGreetingPrompt() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"

        if habits.isEmpty {
            return """
            Generate a single short friendly greeting (max 6 words) for a habit tracker app. \
            It's \(timeOfDay). The user has no habits yet. Be warm, casual, and encouraging. \
            Examples: "Good morning, ready to begin?", "Hey there, what's the plan?", "Evening! Let's set some goals". \
            Output only the greeting, nothing else.
            """
        }

        // Coaching-mode prompt: synthesise what we know about today and ask
        // the model for ONE concrete next-action, not a generic platitude.
        // Signals we feed it:
        //   - Pending habits (which ones aren't done yet)
        //   - Streak status (only flag risk if streak is established AND
        //     habits remain, so we don't badger users early in the day)
        //   - Today's meeting load (lets the coach defer to free time)
        //   - Sleep debt (so we can recommend recovery / lower load on
        //     short-sleep days instead of pushing through)
        //   - Streak freezes available (the anti-burnout escape hatch)
        //   - Friend / mentor signal (who's also pushing today)
        //   - Time of day (urgency increases later in the day)
        let pending = pendingHabits.map(\.title)
        let pendingPreview = pending.prefix(3).joined(separator: ", ")
        let streakStatus: String = {
            guard metrics.currentPerfectStreak >= 3, !pending.isEmpty else {
                return "no immediate streak risk"
            }
            return "\(metrics.currentPerfectStreak)-day perfect streak at risk"
        }()
        let meetings = todaysMeetingCount
        let meetingsLine = meetings > 0
            ? "\(meetings) meeting\(meetings == 1 ? "" : "s") today"
            : "calendar is open today"

        // Sleep debt — surfaces only when meaningful (≥ 1h) so we don't
        // falsely flag rested users. Negative debt means "ahead", which
        // is also useful information.
        let sleepLine: String = {
            guard let forecast = SleepInsightsService.shared.forecast else {
                return "no sleep data"
            }
            let debt = forecast.sleepDebtHours
            if debt >= 1 {
                return String(format: "sleep debt: %.1fh — recovery matters today", debt)
            }
            if debt <= -1 {
                return "well rested"
            }
            return "sleep on track"
        }()

        // Streak freezes available — knowing this lets the coach
        // suggest "use a freeze" on a brutal day instead of guilting
        // the user into pushing through.
        let freezeLine: String = {
            let freezes = backendStore?.dashboard?.rewards.freezesAvailable ?? 0
            return freezes > 0
                ? "\(freezes) flexible-streak token\(freezes == 1 ? "" : "s") available"
                : "no streak tokens available"
        }()

        // Mentor / friend signal — if a mentor has been active this
        // session, the coach can reference them; otherwise stay silent.
        let mentorLine: String = {
            guard let dash = backendStore?.dashboard, let match = dash.match else {
                return "no mentor active"
            }
            return "mentor: \(match.mentor.displayName)"
        }()

        return """
        You are a coach inside a habit-tracker app. Output a single short \
        next-action sentence (max 10 words) telling the user the one thing \
        to do next. Be specific to the data, not generic. No emojis, no \
        opening salutation, no exclamation marks.

        Time of day: \(timeOfDay).
        Habits done today: \(metrics.doneToday) of \(metrics.totalHabits).
        Pending today: \(pendingPreview)\(pending.count > 3 ? " and \(pending.count - 3) more" : "").
        Streak: \(streakStatus).
        Schedule: \(meetingsLine).
        Sleep: \(sleepLine).
        Backup: \(freezeLine).
        Social: \(mentorLine).

        Reply with only the sentence — no quotes, no preamble.
        """
    }
}

// MARK: - Suggested Time Pill

/// Calendar-aware suggestion banner. Sits above the pending-habit list
/// so users see "do this around 10:30 AM — your peak focus window"
/// before they even pick a habit. Computed in `CenterPanel.timeSuggestion`
/// from today's calendar gaps + the user's energy curve; hidden when no
/// good slot is left in the day.
private struct SuggestedTimePill: View {
    let suggestion: HabitTimeSuggestion.Suggestion
    @Environment(\.colorScheme) private var colorScheme

    private var gold: Color { Color(red: 0.94, green: 0.74, blue: 0.24) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(gold)
            Text(suggestion.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(gold.opacity(colorScheme == .dark ? 0.14 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(gold.opacity(0.36), lineWidth: 0.5)
        )
        .accessibilityLabel(suggestion.label)
    }
}

// MARK: - Meetings Pill

/// Subtle "X meetings · Yh today" notification chip shown beneath the
/// dashboard greeting. Replaces the older purple `CalendarInsightsBanner`
/// so the meeting count is present but unobtrusive — no CTA, no
/// background card, just a tiny tinted capsule.
///
/// The capsule's tint encodes how full the day is so a glance is enough
/// to know whether to schedule extra habits today or take it easy:
/// - **Green** ( < 2h ) — light day, plenty of room.
/// - **Blue** ( 2–4h ) — moderate; mostly normal.
/// - **Orange** ( 4–6h ) — busy; consider deferring optional habits.
/// - **Red** ( ≥ 6h ) — back-to-back; protect any remaining focus block.
private struct MeetingsPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    let totalMinutes: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label). \(busynessLabel) day."))
    }

    private var label: String {
        let countLabel = count == 1 ? "1 meeting" : "\(count) meetings"
        guard totalMinutes >= 30 else {
            return "\(countLabel) today"
        }
        return "\(countLabel) · \(durationLabel) today"
    }

    /// "30m" / "1h" / "1h 15m" / "5h" — drops the minutes suffix when the
    /// total lands on a whole hour so a 4h block doesn't read "4h 0m".
    private var durationLabel: String {
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    /// Buckets in hours: < 2 light, 2–4 moderate, 4–6 busy, ≥ 6 packed.
    /// Boundaries are inclusive on the left so a flat 4-hour day is
    /// already "busy" rather than "moderate".
    private var tint: Color {
        let hours = Double(totalMinutes) / 60.0
        switch hours {
        case ..<2:  return .green
        case ..<4:  return .blue
        case ..<6:  return .orange
        default:    return .red
        }
    }

    private var busynessLabel: String {
        let hours = Double(totalMinutes) / 60.0
        switch hours {
        case ..<2:  return "Light"
        case ..<4:  return "Moderate"
        case ..<6:  return "Busy"
        default:    return "Packed"
        }
    }
}

// MARK: - Floating Habit Background
