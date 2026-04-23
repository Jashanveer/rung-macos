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
    let onAddHabit: (HabitEntryType, Date?) -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void

    @State private var aiGreeting: String?
    @State private var hasRequestedGreeting = false

    private var pendingHabits: [Habit] {
        habits.filter { habit in
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
    private var isEmpty: Bool { habits.isEmpty }
    private var allDoneToday: Bool { !habits.isEmpty && pendingHabits.isEmpty }
    private var isCompact: Bool { !isEmpty && !allDoneToday }

    var body: some View {
        VStack(spacing: isCompact ? 10 : 16) {
            if !isCompact {
                Spacer()
            }

            TodayHeader(greeting: displayGreeting, isCompact: isCompact)

            AddHabitBar(
                newHabitTitle: $newHabitTitle,
                selectedType: $newEntryType,
                hasOverdueTask: hasOverdueTask,
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
                        stampNamespace: stampNamespace
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

    private func requestAIGreeting() {
        Task {
            guard #available(macOS 26.0, *) else { return }
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

// MARK: - Floating Habit Background
