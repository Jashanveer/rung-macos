import SwiftData
import SwiftUI

struct ContentViewScaffold: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var focusController = FocusController.shared

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

    let showOnboarding: Bool

    let stampNamespace: Namespace.ID

    /// Drives the genie-style morph between each edge pill and its
    /// corresponding panel. Each pill/panel pair shares an id under this
    /// namespace; matchedGeometryEffect interpolates the pill's frame to
    /// the panel's frame on open and back on close.
    @Namespace private var panelMorph
    let stampStagingIds: Set<PersistentIdentifier>

    let onAddHabit: (HabitEntryType, Date?, CanonicalHabit?, Int?, TaskPriority?) -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void
    let onSync: () -> Void
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void
    let onCompleteOnboarding: ([String]) -> Void

    var body: some View {
        ZStack {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                phoneScaffold
            } else {
                padOrMacScaffold
            }
            #else
            padOrMacScaffold
            #endif

            if focusController.isImmersivePresented {
                FocusModeView(controller: focusController)
                    .zIndex(500)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: focusController.isImmersivePresented)
    }

    // MARK: - iPhone (compact) — TabView wireframe

    @ViewBuilder
    private var phoneScaffold: some View {
        PhoneTabScaffold(
            colorScheme: colorScheme,
            habits: habits,
            todayKey: todayKey,
            newHabitTitle: $newHabitTitle,
            newEntryType: $newEntryType,
            metrics: metrics,
            backend: backend,
            showCelebration: showCelebration,
            mentorNudge: $mentorNudge,
            showMentorCharacter: showMentorCharacter,
            showMenteeCharacter: showMenteeCharacter,
            showOnboarding: showOnboarding,
            stampNamespace: stampNamespace,
            stampStagingIds: stampStagingIds,
            onAddHabit: onAddHabit,
            onToggleHabit: onToggleHabit,
            onDeleteHabit: onDeleteHabit,
            onSync: onSync,
            onReminderChange: onReminderChange,
            onCompleteOnboarding: onCompleteOnboarding
        )
    }

    // MARK: - iPad & macOS — preserved edge-handle layout

    @ViewBuilder
    private var padOrMacScaffold: some View {
        ZStack {
            MinimalBackground()
                #if os(iOS)
                .ignoresSafeArea()
                #endif
                .zIndex(-1)

            DoneHabitPillsBackground(
                habits: (backend.dashboard?.rewards.frozenDates.contains(todayKey) ?? false)
                    ? []
                    : habits.filter { habit in
                        guard !stampStagingIds.contains(habit.persistentModelID) else { return false }
                        // Weekly-target habits surface as stamps for the
                        // remainder of the week once their target is met,
                        // regardless of whether today itself was a gym day.
                        if habit.isFrequencyBased {
                            return habit.weeklyTargetReached(containing: DateKey.date(from: todayKey))
                        }
                        return habit.completedDayKeys.contains(todayKey)
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
                isFrozenToday: backend.dashboard?.rewards.frozenDates.contains(todayKey) ?? false,
                onAddHabit: onAddHabit,
                onToggleHabit: onToggleHabit,
                onDeleteHabit: onDeleteHabit,
                backendStore: backend
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
                    StatsSidebar(
                        metrics: metrics,
                        dashboard: backend.dashboard,
                        backend: backend,
                        todayKey: todayKey,
                        onClose: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                progressOpen = false
                            }
                        }
                    )
                    .frame(width: 330)
                    .padding(.trailing, 22)
                    .padding(.vertical, 22)
                    .matchedGeometryEffect(id: "panel-progress", in: panelMorph)
                    .transition(.opacity)
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
                        onReminderChange: onReminderChange,
                        onClose: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                settingsOpen = false
                            }
                        }
                    )
                    .frame(width: 330)
                    .padding(.leading, 22)
                    .padding(.vertical, 22)
                    .matchedGeometryEffect(id: "panel-settings", in: panelMorph)
                    .transition(.opacity)
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
                .matchedGeometryEffect(id: "panel-settings", in: panelMorph)
                .transition(.opacity)
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
                .matchedGeometryEffect(id: "panel-progress", in: panelMorph)
                .transition(.opacity)
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
            ConnectionStatusIcon(backend: backend)
                .padding(.top, 16)
                .padding(.trailing, 20)
        }
        .overlay {
            // Profile setup wins over normal onboarding — a fresh Apple
            // sign-up needs a username + avatar before anything else.
            if backend.requiresProfileSetup {
                AppleProfileSetupView(
                    backend: backend,
                    prefilledDisplayName: backend.pendingAppleFullName
                ) {}
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(195)
            } else if showOnboarding {
                OnboardingView(onComplete: onCompleteOnboarding)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(190)
            }
        }
        // Walking characters — pinned to the bottom of the scaffold on both
        // iPad and macOS. Width is capped on iPad so the character walks
        // within a band aligned to the center panel rather than wandering
        // across the full ~1200pt window. `.ignoresSafeArea(.keyboard)`
        // keeps them on-screen when a text field brings up the keyboard.
        // Applied *before* the RungIntroView overlay so the intro sits on
        // top of them during cold-launch (the mentor must not peek out from
        // behind the loading screen).
        .overlay(alignment: .bottom) {
            if showMentorCharacter && backend.isAuthenticated {
                MentorCharacterView(backend: backend, nudge: $mentorNudge)
                    #if os(iOS)
                    .frame(maxWidth: 720)
                    .ignoresSafeArea(.keyboard)
                    #endif
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showMenteeCharacter && backend.isAuthenticated {
                MenteeCharacterView(backend: backend)
                    #if os(iOS)
                    .frame(maxWidth: 720)
                    .ignoresSafeArea(.keyboard)
                    #endif
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            RungIntroView(
                backend: backend,
                onReady: onSync
            )
            .transition(.opacity)
            .zIndex(200)
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}
