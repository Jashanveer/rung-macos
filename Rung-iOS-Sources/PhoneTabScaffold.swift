#if os(iOS)
import SwiftData
import SwiftUI
import UIKit

/// iPhone-specific root layout. Five tabs (Today / Calendar / Stats /
/// Friends / Account) replace the macOS edge-handle paradigm. The Energy
/// view lives inside the Calendar tab via a top-of-sheet toggle —
/// matching the macOS / iPad layout — so the bottom bar stays at five
/// even after Path B shipped.
struct PhoneTabScaffold: View {
    enum Tab: Hashable { case today, stats, friends, account, calendar }

    let colorScheme: ColorScheme
    let habits: [Habit]
    let todayKey: String
    @Binding var newHabitTitle: String
    @Binding var newEntryType: HabitEntryType
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore

    let showCelebration: Bool
    @Binding var mentorNudge: String?
    let showMentorCharacter: Bool
    let showMenteeCharacter: Bool

    let showOnboarding: Bool

    let stampNamespace: Namespace.ID
    let stampStagingIds: Set<PersistentIdentifier>

    let onAddHabit: (HabitEntryType, Date?, CanonicalHabit?, Int?, TaskPriority?) -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void
    let onSync: () -> Void
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void
    let onCompleteOnboarding: ([String]) -> Void

    @State private var selectedTab: Tab = .today
    @State private var habitCardFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var activeStampFlights: [PersistentIdentifier: PhoneStampFlight] = [:]

    private let phoneStampScale: CGFloat = 0.75
    private let phoneStampLimit = 48

    private var isRunningOnPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            todayTab
                .tabItem { Label("Today", systemImage: "checkmark.circle.fill") }
                .tag(Tab.today)

            calendarTab
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)

            statsTab
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                .tag(Tab.stats)

            friendsTab
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(Tab.friends)

            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Tab.account)
        }
        .tint(CleanShotTheme.accent)
        .onChange(of: selectedTab) { _, _ in Haptics.selection() }
        .overlay {
            if showCelebration {
                ConfettiOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(100)
            }
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
        .overlay {
            RungIntroView(backend: backend, onReady: onSync)
                .transition(.opacity)
                .zIndex(200)
        }
    }

    // MARK: - Today

    private var todayTab: some View {
        GeometryReader { geo in
            let rootFrame = geo.frame(in: .global)
            let rootSize = geo.size
            let isFrozenToday = backend.dashboard?.rewards.frozenDates.contains(todayKey) ?? false
            let completedBackgroundHabits = isFrozenToday
                ? []
                : habits.filter { habit in
                    guard !stampStagingIds.contains(habit.persistentModelID) else { return false }
                    // Weekly-target habits surface as stamps for the
                    // remainder of the week once their target is met —
                    // today-specific completion is not required.
                    if habit.isFrequencyBased {
                        return habit.weeklyTargetReached(containing: DateKey.date(from: todayKey))
                    }
                    return habit.completedDayKeys.contains(todayKey)
                }

            ZStack {
                MinimalBackground()
                    .ignoresSafeArea()

                DoneHabitPillsBackground(
                    habits: completedBackgroundHabits,
                    todayKey: todayKey,
                    stampNamespace: isRunningOnPhone ? nil : stampNamespace,
                    stampScaleMultiplier: isRunningOnPhone ? phoneStampScale : 1,
                    hiddenStampIds: isRunningOnPhone ? Set(activeStampFlights.keys) : [],
                    compactMaxStamps: isRunningOnPhone ? phoneStampLimit : 4
                )
                .allowsHitTesting(false)
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
                    enableStampMatchedGeometry: !isRunningOnPhone,
                    isFrozenToday: backend.dashboard?.rewards.frozenDates.contains(todayKey) ?? false,
                    onAddHabit: onAddHabit,
                    onToggleHabit: onToggleHabit,
                    onDeleteHabit: onDeleteHabit,
                    backendStore: backend
                )
                .padding(.horizontal, 4)
                .zIndex(1)

                if isRunningOnPhone {
                    ForEach(Array(activeStampFlights.values)) { flight in
                        PhoneStampFlightView(flight: flight, todayKey: todayKey)
                            .zIndex(2)
                    }
                }

                if showMentorCharacter && backend.isAuthenticated {
                    MentorCharacterView(backend: backend, nudge: $mentorNudge)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(true)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .ignoresSafeArea(.keyboard)
                        .zIndex(20)
                }

                if showMenteeCharacter && backend.isAuthenticated {
                    MenteeCharacterView(backend: backend)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .ignoresSafeArea(.keyboard)
                        .zIndex(19)
                }
            }
            .onPreferenceChange(HabitCardFramePreferenceKey.self) { frames in
                guard isRunningOnPhone else { return }
                habitCardFrames = frames.mapValues {
                    $0.offsetBy(dx: -rootFrame.minX, dy: -rootFrame.minY)
                }
            }
            .onChange(of: stampStagingIds) { oldValue, newValue in
                handleStampStagingChange(from: oldValue, to: newValue, rootSize: rootSize)
            }
        }
        .safeAreaInset(edge: .top) {
            phoneTopStatusBar
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .refreshable { onSync() }
    }

    private func handleStampStagingChange(
        from oldValue: Set<PersistentIdentifier>,
        to newValue: Set<PersistentIdentifier>,
        rootSize: CGSize
    ) {
        guard isRunningOnPhone else { return }

        let releasedIds = oldValue.subtracting(newValue)
        guard !releasedIds.isEmpty else { return }

        let completedHabits = habits.filter { $0.completedDayKeys.contains(todayKey) }
        for releasedId in releasedIds {
            guard let habit = habits.first(where: { $0.persistentModelID == releasedId }),
                  habit.completedDayKeys.contains(todayKey)
            else {
                activeStampFlights[releasedId] = nil
                continue
            }

            let sourceFrame = habitCardFrames[releasedId]
                ?? CGRect(x: rootSize.width * 0.10, y: rootSize.height * 0.42, width: rootSize.width * 0.80, height: 64)
            let destination = DoneHabitPillsBackground.flightDestination(
                for: habit,
                among: completedHabits,
                in: rootSize,
                stampScaleMultiplier: phoneStampScale,
                compactMaxStamps: phoneStampLimit
            )
            let fallbackAccent = habit.entryType == .habit ? CleanShotTheme.success : CleanShotTheme.accent
            let flight = PhoneStampFlight(
                id: releasedId,
                habit: habit,
                sourceFrame: sourceFrame,
                target: destination?.point ?? CGPoint(x: rootSize.width / 2, y: max(72, rootSize.height * 0.14)),
                accent: destination?.accent ?? fallbackAccent,
                stampScale: destination?.scale ?? phoneStampScale
            )

            activeStampFlights[releasedId] = flight
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 760_000_000)
                withAnimation(.easeOut(duration: 0.14)) {
                    activeStampFlights[releasedId] = nil
                }
            }
        }
    }

    @ViewBuilder
    private var phoneTopStatusBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ConnectionStatusIcon(backend: backend)
        }
    }

    // MARK: - Stats

    private var statsTab: some View {
        ZStack {
            MinimalBackground().ignoresSafeArea()

            StatsSidebar(
                metrics: metrics,
                dashboard: backend.dashboard,
                backend: backend,
                todayKey: todayKey
            )
            .padding(.horizontal, 16)
        }
        .refreshable { onSync() }
    }

    // MARK: - Friends

    private var friendsTab: some View {
        ZStack {
            MinimalBackground().ignoresSafeArea()

            SettingsPanel(
                mode: .friends,
                metrics: metrics,
                backend: backend,
                habits: habits.filter { $0.entryType == .habit },
                onSync: onSync,
                onReminderChange: onReminderChange
            )
            .padding(.horizontal, 16)
        }
        .refreshable { onSync() }
    }

    // MARK: - Account

    private var accountTab: some View {
        ZStack {
            MinimalBackground().ignoresSafeArea()

            SettingsPanel(
                mode: .account,
                metrics: metrics,
                backend: backend,
                habits: habits.filter { $0.entryType == .habit },
                onSync: onSync,
                onReminderChange: onReminderChange
            )
            .padding(.horizontal, 16)
        }
        .refreshable { onSync() }
    }

    // MARK: - Calendar

    private var calendarTab: some View {
        ZStack {
            MinimalBackground().ignoresSafeArea()

            CalendarSheet(habits: habits, onClose: {})
                .padding(.horizontal, 12)
                .padding(.top, 4)
        }
        .refreshable { onSync() }
    }
}

private struct PhoneStampFlight: Identifiable {
    let id: PersistentIdentifier
    let habit: Habit
    let sourceFrame: CGRect
    let target: CGPoint
    let accent: Color
    let stampScale: CGFloat
}

private struct PhoneStampFlightView: View {
    let flight: PhoneStampFlight
    let todayKey: String

    @State private var arrived = false

    private var sourceCenter: CGPoint {
        CGPoint(x: flight.sourceFrame.midX, y: flight.sourceFrame.midY)
    }

    var body: some View {
        ZStack {
            HabitCard(
                habit: flight.habit,
                todayKey: todayKey,
                onToggle: { _ in },
                onDelete: { _ in },
                stampNamespace: nil,
                reportsFrame: false
            )
            .frame(width: max(flight.sourceFrame.width, 120))
            .opacity(arrived ? 0 : 1)
            .scaleEffect(arrived ? 0.72 : 1)

            AmbientStamp(
                habit: flight.habit,
                todayKey: todayKey,
                accent: flight.accent,
                scale: flight.stampScale,
                stampNamespace: nil
            )
            .opacity(arrived ? 1 : 0)
            .scaleEffect(arrived ? 1 : 0.9)
        }
        .frame(
            width: max(flight.sourceFrame.width, 120),
            height: max(flight.sourceFrame.height, 92)
        )
        .position(arrived ? flight.target : sourceCenter)
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: arrived)
        .allowsHitTesting(false)
        .onAppear { arrived = true }
    }
}
#endif
