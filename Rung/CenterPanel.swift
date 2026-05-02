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

    @State private var aiGreeting: String?
    @State private var hasRequestedGreeting = false

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
        let habitNames = habits.map(\.title).joined(separator: ", ")

        if habits.isEmpty {
            return """
            Generate a single short friendly greeting (max 6 words) for a habit tracker app. \
            It's \(timeOfDay). The user has no habits yet. Be warm, casual, and encouraging. \
            Examples: "Good morning, ready to begin?", "Hey there, what's the plan?", "Evening! Let's set some goals". \
            Output only the greeting, nothing else.
            """
        }

        return """
        Generate a single short greeting (max 6 words) for a habit tracker app. \
        It's \(timeOfDay). The user has \(metrics.totalHabits) habits: \(habitNames). \
        Perfect streak: \(metrics.currentPerfectStreak) days. Be warm and motivating. \
        Output only the greeting, nothing else.
        """
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
