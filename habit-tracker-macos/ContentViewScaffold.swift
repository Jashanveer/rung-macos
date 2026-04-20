import SwiftData
import SwiftUI

struct ContentViewScaffold: View {
    let colorScheme: ColorScheme
    let habits: [Habit]
    let todayKey: String
    @Binding var newHabitTitle: String
    @Binding var newEntryType: HabitEntryType
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore

    @Binding var progressOpen: Bool
    @Binding var calendarOpen: Bool
    @Binding var settingsOpen: Bool

    let showCelebration: Bool
    @Binding var mentorNudge: String?
    let showMentorCharacter: Bool
    let showMenteeCharacter: Bool
    let mentorMissedCount: Int

    let showOnboarding: Bool

    let stampNamespace: Namespace.ID
    let stampStagingIds: Set<PersistentIdentifier>

    let onAddHabit: (HabitEntryType, Date?) -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void
    let onSync: () -> Void
    let onFindMentor: () -> Void
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void
    let onCompleteOnboarding: ([String]) -> Void

    var body: some View {
        ZStack {
            MinimalBackground()
                .zIndex(-1)

            DoneHabitPillsBackground(
                habits: habits.filter {
                    $0.completedDayKeys.contains(todayKey)
                        && !stampStagingIds.contains($0.persistentModelID)
                },
                todayKey: todayKey,
                stampNamespace: stampNamespace
            )
            .zIndex(0)

            CenterPanel(
                habits: habits,
                todayKey: todayKey,
                newHabitTitle: $newHabitTitle,
                newEntryType: $newEntryType,
                metrics: metrics,
                clusters: backend.dashboard?.habitClusters ?? [],
                stampNamespace: stampNamespace,
                stampStagingIds: stampStagingIds,
                onAddHabit: onAddHabit,
                onToggleHabit: onToggleHabit,
                onDeleteHabit: onDeleteHabit
            )
            .frame(maxWidth: 860)
            .padding(.horizontal, 28)
            .padding(.vertical, 54)
            .offset(x: progressOpen ? -166 : settingsOpen ? 166 : 0)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: progressOpen)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: settingsOpen)
            .zIndex(1)

            if progressOpen {
                Color.black.opacity(colorScheme == .dark ? 0.08 : 0.025)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            progressOpen = false
                            settingsOpen = false
                        }
                    }

                HStack {
                    Spacer()
                    StatsSidebar(metrics: metrics, dashboard: backend.dashboard, backend: backend, todayKey: todayKey)
                        .frame(width: 330)
                        .padding(.trailing, 22)
                        .padding(.vertical, 22)
                        .transition(
                            .scale(scale: 0.96, anchor: .trailing)
                            .combined(with: .opacity)
                        )
                }
                .zIndex(3)
            }

            if settingsOpen {
                Color.black.opacity(colorScheme == .dark ? 0.06 : 0.02)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            settingsOpen = false
                        }
                    }

                HStack {
                    SettingsPanel(
                        metrics: metrics,
                        backend: backend,
                        habits: habits.filter { $0.entryType == .habit },
                        onSync: onSync,
                        onFindMentor: onFindMentor,
                        onReminderChange: onReminderChange
                    )
                    .frame(width: 330)
                    .padding(.leading, 22)
                    .padding(.vertical, 22)
                    .transition(.scale(scale: 0.96, anchor: .leading).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(5)
            }

            if calendarOpen {
                VStack {
                    Spacer()
                    CalendarSheet(
                        habits: habits,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                calendarOpen = false
                            }
                        }
                    )
                    .frame(maxWidth: 980)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(4)
            }
        }
        .overlay(alignment: .leading) {
            if !settingsOpen {
                EdgePanelHandle(
                    systemImage: "person.2.fill",
                    label: "Social",
                    edge: .leading,
                    isActive: settingsOpen,
                    dragDirection: .horizontal
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        settingsOpen.toggle()
                        progressOpen = false
                        calendarOpen = false
                    }
                }
                .padding(.leading, 8)
                .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            if !progressOpen {
                EdgePanelHandle(
                    systemImage: "chart.bar.xaxis",
                    label: "Progress",
                    edge: .trailing,
                    isActive: progressOpen,
                    dragDirection: .horizontal
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        progressOpen.toggle()
                        settingsOpen = false
                        calendarOpen = false
                    }
                }
                .padding(.trailing, 8)
                .transition(.scale(scale: 0.94, anchor: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if !calendarOpen {
                EdgePanelHandle(
                    systemImage: "calendar",
                    label: "Calendar",
                    edge: .bottom,
                    isActive: calendarOpen,
                    dragDirection: .vertical
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        calendarOpen.toggle()
                        settingsOpen = false
                        progressOpen = false
                    }
                }
                .padding(.bottom, 8)
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showCelebration {
                ConfettiOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .overlay(alignment: .top) {
            if backend.isAuthenticated, let dashboard = backend.dashboard {
                FriendsLeaderboardPill(dashboard: dashboard)
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            ConnectionStatusPill(backend: backend, onSync: onSync)
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .overlay {
            if showOnboarding {
                OnboardingView(onComplete: onCompleteOnboarding)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(190)
            }
        }
        .overlay {
            FormaIntroView(
                backend: backend,
                onReady: onSync
            )
            .transition(.opacity)
            .zIndex(200)
        }
        .overlay(alignment: .bottom) {
            if showMentorCharacter && backend.isAuthenticated {
                MentorCharacterView(backend: backend, nudge: $mentorNudge)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showMenteeCharacter && backend.isAuthenticated {
                MenteeCharacterView(backend: backend, mentorMissedCount: mentorMissedCount)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showMenteeCharacter && backend.isAuthenticated && mentorMissedCount > 0 {
                MentorAlertBanner(
                    missedCount: mentorMissedCount,
                    mentees: backend.dashboard?.mentorDashboard.mentees ?? [],
                    onNudge: { matchId in
                        Task { await backend.sendNudge(matchId: matchId) }
                    }
                )
                .padding(.leading, 20)
                .padding(.bottom, 148)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mentorMissedCount)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
