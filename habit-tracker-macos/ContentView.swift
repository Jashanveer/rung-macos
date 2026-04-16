import FoundationModels
import SwiftData
import SwiftUI

private enum CleanShotTheme {
    static let accent = Color(red: 0.18, green: 0.58, blue: 0.86)
    static let success = Color(red: 0.22, green: 0.68, blue: 0.36)
    static let warning = Color(red: 0.96, green: 0.61, blue: 0.18)
    static let gold = Color(red: 0.94, green: 0.74, blue: 0.24)
    static let violet = Color(red: 0.46, green: 0.48, blue: 0.84)

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.058, blue: 0.068)
            : Color(red: 0.955, green: 0.965, blue: 0.975)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.136, blue: 0.155).opacity(0.74)
            : Color.white.opacity(0.72)
    }

    static func elevatedSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.178, blue: 0.20).opacity(0.78)
            : Color.white.opacity(0.82)
    }

    static func controlFill(for colorScheme: ColorScheme, active: Bool = false) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(active ? 0.13 : 0.075)
            : Color.black.opacity(active ? 0.075 : 0.04)
    }

    static func stroke(for colorScheme: ColorScheme, active: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(active ? 0.20 : 0.105)
        }

        return Color.black.opacity(active ? 0.14 : 0.08)
    }

    static func shadow(for colorScheme: ColorScheme, strong: Bool = false) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(strong ? 0.42 : 0.22)
            : Color.black.opacity(strong ? 0.16 : 0.075)
    }
}

private enum UserLevel: String {
    case beginner = "Beginner"
    case rising = "Rising"
    case consistent = "Consistent"
    case elite = "Elite"
    case mentor = "Mentor"
    case masterMentor = "Master Mentor"

    var systemImage: String {
        switch self {
        case .beginner:
            return "leaf"
        case .rising:
            return "arrow.up.forward"
        case .consistent:
            return "checkmark.seal"
        case .elite:
            return "star"
        case .mentor:
            return "person.2"
        case .masterMentor:
            return "crown"
        }
    }

    var tint: Color {
        switch self {
        case .beginner:
            return .secondary
        case .rising:
            return CleanShotTheme.accent
        case .consistent:
            return CleanShotTheme.success
        case .elite:
            return CleanShotTheme.violet
        case .mentor:
            return CleanShotTheme.gold
        case .masterMentor:
            return CleanShotTheme.warning
        }
    }
}

private struct MentorCandidate: Identifiable {
    let id = UUID()
    let name: String
    let focus: String
    let timezone: String
    let language: String
    let consistency: Int
}

private struct FeedPost: Identifiable {
    let id = UUID()
    let author: String
    let message: String
    let meta: String
    let systemImage: String
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @StateObject private var backend = HabitBackendStore()

    @State private var newHabitTitle = ""
    @State private var progressOpen = false
    @State private var calendarOpen = false
    @State private var settingsOpen = false
    @State private var showCelebration = false
    #if DEBUG
    @State private var debugShowCharacter = true
    #endif

    private var todayKey: String { DateKey.key(for: Date()) }
    private var metrics: HabitMetrics { HabitMetrics.compute(for: habits, todayKey: todayKey) }

    private var showMentorCharacter: Bool {
        #if DEBUG
        if debugShowCharacter { return true }
        #endif
        return backend.dashboard?.match != nil
    }

    var body: some View {
        ZStack {
            MinimalBackground()
                .zIndex(-1)

            CenterPanel(
                habits: habits,
                todayKey: todayKey,
                newHabitTitle: $newHabitTitle,
                metrics: metrics,
                onAddHabit: addHabit,
                onToggleHabit: toggleHabit,
                onDeleteHabit: deleteHabit
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
                    StatsSidebar(metrics: metrics, dashboard: backend.dashboard)
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
                        onSync: syncWithBackend,
                        onAssignMentor: assignMentor
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
                        perfectDays: metrics.perfectDays,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                calendarOpen = false
                            }
                        }
                    )
                    .frame(maxWidth: 980)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                    )
                }
                .zIndex(4)
            }
        }
        .overlay(alignment: .leading) {
            if !settingsOpen {
                EdgePanelHandle(
                    systemImage: "person.2",
                    label: "Mentor",
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
            ConnectionStatusPill(backend: backend, onSync: syncWithBackend)
                .padding(.top, 12)
        }
        .overlay {
            if !backend.isAuthenticated {
                AuthGateView(backend: backend) {
                    syncWithBackend()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)
            }
        }
        .overlay(alignment: .bottom) {
            if showMentorCharacter {
                MentorCharacterView(backend: backend)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.smooth(duration: 0.2), value: colorScheme)
        .task {
            guard backend.isAuthenticated else { return }
            syncWithBackend()
        }
    }

    private func addHabit() {
        let title = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        guard backend.isAuthenticated else {
            backend.errorMessage = "Sign in before adding habits."
            return
        }

        backend.isSyncing = true
        Task {
            do {
                let remoteHabit = try await backend.createHabit(title: title)
                await MainActor.run {
                    withAnimation {
                        upsert(remoteHabit)
                        newHabitTitle = ""
                    }
                    backend.statusMessage = "Habit synced"
                    backend.errorMessage = nil
                    backend.isSyncing = false
                }
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                    backend.isSyncing = false
                }
            }
        }
    }

    private func syncWithBackend() {
        guard backend.isAuthenticated else { return }

        backend.isSyncing = true
        Task {
            do {
                try await uploadUnsyncedLocalHabits()
                let remoteHabits = try await backend.listHabits()
                await MainActor.run {
                    merge(remoteHabits)
                    backend.statusMessage = "Synced with localhost:8080"
                    backend.errorMessage = nil
                    backend.isSyncing = false
                }
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                    backend.isSyncing = false
                }
            }
        }
    }

    private func uploadUnsyncedLocalHabits() async throws {
        let unsynced = habits.filter { $0.backendId == nil }
        for habit in unsynced {
            let remoteHabit = try await backend.createHabit(title: habit.title)
            habit.backendId = remoteHabit.id

            for dayKey in habit.completedDayKeys {
                try await backend.setCheck(habitID: remoteHabit.id, dateKey: dayKey, done: true)
            }
        }
    }

    private func merge(_ remoteHabits: [BackendHabit]) {
        let remoteIDs = Set(remoteHabits.map(\.id))

        for remoteHabit in remoteHabits {
            upsert(remoteHabit)
        }

        for habit in habits {
            guard let backendId = habit.backendId, !remoteIDs.contains(backendId) else { continue }
            modelContext.delete(habit)
        }
    }

    private func upsert(_ remoteHabit: BackendHabit) {
        if let existing = habits.first(where: { $0.backendId == remoteHabit.id }) {
            existing.title = remoteHabit.title
            existing.completedDayKeys = remoteHabit.completedDayKeys
        } else {
            modelContext.insert(Habit(
                title: remoteHabit.title,
                completedDayKeys: remoteHabit.completedDayKeys,
                backendId: remoteHabit.id
            ))
        }
    }

    private func assignMentor() {
        Task {
            await backend.assignMentor()
        }
    }

    private func toggleHabit(_ habit: Habit) {
        var keys = habit.completedDayKeys
        let wasUnchecked = !keys.contains(todayKey)
        if let index = keys.firstIndex(of: todayKey) {
            keys.remove(at: index)
        } else {
            keys.append(todayKey)
        }

        withAnimation(.snappy(duration: 0.2)) {
            habit.completedDayKeys = keys.sorted()
        }

        if wasUnchecked && habits.count > 1 {
            let doneAfter = habits.filter { h in
                if h.id == habit.id {
                    return keys.contains(todayKey)
                }
                return h.completedDayKeys.contains(todayKey)
            }.count
            if doneAfter == habits.count {
                triggerCelebration()
            }
        }

        guard let backendId = habit.backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.setCheck(habitID: backendId, dateKey: todayKey, done: wasUnchecked)
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCelebration = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showCelebration = false
            }
        }
    }

    private func deleteHabit(_ habit: Habit) {
        let backendId = habit.backendId
        withAnimation {
            modelContext.delete(habit)
        }

        guard let backendId, backend.isAuthenticated else { return }
        Task {
            do {
                try await backend.deleteHabit(habitID: backendId)
                await backend.refreshDashboard()
            } catch {
                await MainActor.run {
                    backend.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct CenterPanel: View {
    let habits: [Habit]
    let todayKey: String
    @Binding var newHabitTitle: String

    let metrics: HabitMetrics
    let onAddHabit: () -> Void
    let onToggleHabit: (Habit) -> Void
    let onDeleteHabit: (Habit) -> Void

    @State private var aiGreeting: String?
    @State private var hasRequestedGreeting = false

    private var isEmpty: Bool { habits.isEmpty }

    var body: some View {
        VStack(spacing: isEmpty ? 16 : 10) {
            if isEmpty {
                Spacer()
            }

            TodayHeader(
                greeting: displayGreeting,
                isCompact: !isEmpty
            )

            AddHabitBar(newHabitTitle: $newHabitTitle, onAddHabit: onAddHabit)
                .frame(maxWidth: 520)

            if isEmpty {
                Text("Add your first habit to get started")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    HabitListSection(
                        habits: habits,
                        todayKey: todayKey,
                        onToggle: onToggleHabit,
                        onDelete: onDeleteHabit
                    )
                    .padding(.top, 4)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: 680)
            }
        }
        .padding(.top, isEmpty ? 0 : 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 860, maxHeight: .infinity)
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isEmpty)
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

private struct AuthGateView: View {
    @ObservedObject var backend: HabitBackendStore
    let onAuthenticated: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var validationMessage: String?

    var body: some View {
        ZStack {
            CleanShotTheme.canvas(for: colorScheme)
                .opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.laptopcomputer")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                        .frame(width: 58, height: 58)
                        .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), level: .control)

                    Text("Connect your habits")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Sign in to sync with the backend running on localhost:8080.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                VStack(spacing: 10) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .cleanShotSurface(shape: Capsule(), level: .control)
                        .onSubmit {
                            submit(mode: .login)
                        }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .cleanShotSurface(shape: Capsule(), level: .control)
                        .onSubmit {
                            submit(mode: .login)
                        }

                    if let message = validationMessage ?? backend.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button {
                            submit(mode: .login)
                        } label: {
                            HStack(spacing: 8) {
                                if backend.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text("Sign in")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .buttonStyle(PrimaryCapsuleButtonStyle())

                        Button {
                            submit(mode: .register)
                        } label: {
                            Text("Create account")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                        }
                        .buttonStyle(SecondaryCapsuleButtonStyle())
                    }
                    .disabled(backend.isSyncing)
                }
                .frame(width: 360)
            }
            .padding(28)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                level: .elevated,
                shadowRadius: 18
            )
        }
    }

    private enum AuthMode {
        case login
        case register
    }

    private func submit(mode: AuthMode) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        backend.errorMessage = nil

        guard trimmedEmail.contains("@") else {
            validationMessage = "Enter a valid email address."
            return
        }

        guard password.count >= 8 else {
            validationMessage = "Password must be at least 8 characters."
            return
        }

        Task {
            switch mode {
            case .login:
                await backend.signIn(email: trimmedEmail, password: password)
            case .register:
                await backend.register(email: trimmedEmail, password: password)
            }

            if backend.isAuthenticated {
                onAuthenticated()
            }
        }
    }
}

private struct ConnectionStatusPill: View {
    @ObservedObject var backend: HabitBackendStore
    let onSync: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: backend.isAuthenticated ? "server.rack" : "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(backend.errorMessage == nil ? CleanShotTheme.success : CleanShotTheme.warning)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if backend.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            } else if backend.isAuthenticated {
                Button(action: onSync) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .cleanShotSurface(shape: Capsule(), level: .control, isActive: isHovered)
        .onHover { isHovered = $0 }
    }

    private var statusText: String {
        if let errorMessage = backend.errorMessage {
            return errorMessage
        }

        if backend.isSyncing {
            return "Syncing..."
        }

        return backend.isAuthenticated ? (backend.statusMessage ?? "Connected to localhost:8080") : "Backend sign in required"
    }
}

private struct SettingsPanel: View {
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore
    let onSync: () -> Void
    let onAssignMentor: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                        .frame(width: 30, height: 30)
                        .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), level: .control)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accountability Hub")
                            .font(.headline)
                        Text("Support first, streaks second")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                BackendConnectionCard(backend: backend, onSync: onSync)

                LevelStatusCard(metrics: metrics, dashboard: backend.dashboard)

                MentorMatchCard(metrics: metrics, dashboard: backend.dashboard, onAssignMentor: onAssignMentor)

                MenteeDashboardCard(metrics: metrics, dashboard: backend.dashboard)

                MentorDashboardCard(metrics: metrics, dashboard: backend.dashboard)

                SocialFeedCard(posts: metrics.feedPosts, dashboard: backend.dashboard)

                RetentionPromptCard(metrics: metrics, dashboard: backend.dashboard)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .elevated,
            shadowRadius: 18
        )
    }
}

private struct BackendConnectionCard: View {
    @ObservedObject var backend: HabitBackendStore
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "server.rack", title: "Backend")

            SettingsRow(
                systemImage: backend.errorMessage == nil ? "checkmark.icloud" : "exclamationmark.triangle",
                title: "localhost:8080",
                value: backend.isAuthenticated ? "Connected" : "Signed out"
            )

            if let statusMessage = backend.statusMessage, backend.errorMessage == nil {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = backend.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                SoftActionButton(title: "Sync", systemImage: "arrow.clockwise", action: onSync)
                SoftActionButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", action: backend.signOut)
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }
}

private struct LevelStatusCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var levelName: String {
        dashboard?.level.name ?? metrics.level.rawValue
    }

    private var level: UserLevel {
        UserLevel(rawValue: levelName) ?? metrics.level
    }

    private var consistencyPercent: Int {
        dashboard?.level.weeklyConsistencyPercent ?? metrics.weeklyConsistencyPercent
    }

    private var note: String {
        dashboard?.level.note ?? metrics.levelNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(levelName, systemImage: level.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(level.tint)
                Spacer()
                Text("\(consistencyPercent)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: metrics.nextLevelProgress)
                .tint(level.tint)

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }
}

private struct MentorMatchCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?
    let onAssignMentor: () -> Void

    private var mentor: MentorCandidate { metrics.mentorCandidate }
    private var matchedMentor: AccountabilityDashboard.UserSummary? { dashboard?.match?.mentor }
    private var needsMentor: Bool { dashboard?.level.needsMentor ?? metrics.needsMentor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "point.3.connected.trianglepath.dotted", title: "Mentor matching")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: needsMentor ? "lifepreserver" : "checkmark.seal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(needsMentor ? CleanShotTheme.warning : CleanShotTheme.success)
                    .frame(width: 34, height: 34)
                    .cleanShotSurface(shape: Circle(), level: .control)

                VStack(alignment: .leading, spacing: 3) {
                    Text(matchedMentor == nil ? (needsMentor ? "Mentor suggested" : "On track") : "Mentor connected")
                        .font(.subheadline.weight(.semibold))
                    Text(matchCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 6) {
                MatchFactor(label: mentor.focus, systemImage: "target", tint: CleanShotTheme.accent)
                MatchFactor(label: mentor.timezone, systemImage: "clock", tint: CleanShotTheme.violet)
                MatchFactor(label: mentor.language, systemImage: "text.bubble", tint: CleanShotTheme.success)
                MatchFactor(label: "\(mentor.consistency)% consistency", systemImage: "chart.line.uptrend.xyaxis", tint: CleanShotTheme.gold)
            }

            if dashboard?.match == nil {
                SoftActionButton(title: "Find mentor", systemImage: "person.badge.plus", action: onAssignMentor)
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }

    private var matchCopy: String {
        if let matchedMentor {
            return "Matched with \(matchedMentor.displayName) for gentle accountability."
        }

        if needsMentor {
            return "Ask the backend to match you with a consistent user."
        }

        return "Keep this pace to unlock mentor eligibility."
    }
}

private struct MatchFactor: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}

private struct MenteeDashboardCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var mentorTip: String {
        dashboard?.menteeDashboard.mentorTip ?? metrics.mentorTip
    }

    private var score: Int {
        dashboard?.menteeDashboard.progressScore ?? metrics.accountabilityScore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "bubble.left.and.text.bubble.right", title: "Mentee dashboard")

            Text(mentorTip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SoftActionButton(title: "Check in", systemImage: "checkmark.message")
                SoftActionButton(title: "Ask for help", systemImage: "hand.raised")
            }

            SettingsRow(systemImage: "heart", title: "Progress score", value: "\(score)/100")
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }
}

private struct MentorDashboardCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "person.crop.circle.badge.checkmark", title: "Mentor dashboard")

            if let dashboard, !dashboard.mentorDashboard.mentees.isEmpty {
                VStack(spacing: 8) {
                    ForEach(dashboard.mentorDashboard.mentees.prefix(3)) { mentee in
                        MenteeRow(
                            name: mentee.displayName,
                            detail: "\(mentee.missedHabitsToday) missed today · \(mentee.weeklyConsistencyPercent)% week",
                            tint: mentee.missedHabitsToday > 0 ? CleanShotTheme.warning : CleanShotTheme.success
                        )
                    }
                }

                HStack(spacing: 8) {
                    SoftActionButton(title: "Nudge", systemImage: "bell")
                    SoftActionButton(title: "Encourage", systemImage: "sparkles")
                }
            } else if dashboard?.level.mentorEligible ?? metrics.mentorEligible {
                VStack(spacing: 8) {
                    MenteeRow(name: "Avery", detail: "Missed \(max(metrics.missedToday, 1)) habit today", tint: CleanShotTheme.warning)
                    MenteeRow(name: "Noor", detail: "Needs a small win", tint: CleanShotTheme.accent)
                }

                HStack(spacing: 8) {
                    SoftActionButton(title: "Nudge", systemImage: "bell")
                    SoftActionButton(title: "Encourage", systemImage: "sparkles")
                }
            } else {
                Text("Reach Consistent level after 7 days to help another user.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }
}

private struct SocialFeedCard: View {
    let posts: [FeedPost]
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "quote.bubble", title: "Social feed")

            ForEach(displayPosts) { post in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: post.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                        .frame(width: 26, height: 26)
                        .cleanShotSurface(shape: Circle(), level: .control)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author)
                            .font(.caption.weight(.semibold))
                        Text(post.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(post.meta)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }

    private var displayPosts: [FeedPost] {
        guard let remotePosts = dashboard?.feed, !remotePosts.isEmpty else {
            return posts
        }

        return remotePosts.prefix(3).map { post in
            FeedPost(
                author: post.author,
                message: post.message,
                meta: "Community update",
                systemImage: "quote.bubble"
            )
        }
    }
}

private struct RetentionPromptCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "bell.badge", title: "Helpful nudges")

            if let notifications = dashboard?.notifications, !notifications.isEmpty {
                ForEach(notifications.prefix(3)) { notification in
                    SettingsRow(systemImage: icon(for: notification.type), title: notification.title, value: "Ready")
                }
            } else {
                SettingsRow(systemImage: "person.wave.2", title: "Mentor checked in", value: "Ready")
                SettingsRow(systemImage: "crown", title: "Mentor rank", value: "\(metrics.daysUntilMentor) days")
                SettingsRow(systemImage: "hands.sparkles", title: "Guidance needed", value: metrics.mentorEligible ? "Open" : "Locked")
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }

    private func icon(for type: String) -> String {
        switch type {
        case "MENTOR_CHECK_IN":
            return "person.wave.2"
        case "MENTOR_PROGRESS":
            return "crown"
        case "GUIDANCE_REQUEST":
            return "hands.sparkles"
        default:
            return "bell"
        }
    }
}

private struct PanelTitle: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MenteeRow: View {
    let name: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 26, height: 26)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct SoftActionButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? CleanShotTheme.accent : .primary)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .onHover { isHovered = $0 }
    }
}

private struct SettingsRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }
}

private struct SettingsMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }
}

private struct EdgePanelHandle: View {
    enum DragDirection {
        case horizontal
        case vertical
    }

    let systemImage: String
    let label: String
    let edge: Edge
    let isActive: Bool
    let dragDirection: DragDirection
    let action: () -> Void

    @State private var isHovered = false

    private var dateLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var displayLabel: String {
        if case .bottom = edge, !isHovered {
            return dateLabel
        }

        return label
    }

    var body: some View {
        Button(action: action) {
            Group {
                switch edge {
                case .leading:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 74)
                case .trailing:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 74)
                case .bottom:
                    Label(displayLabel, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(width: 188, height: 34)
                        .overlay {
                            Label(dateLabel, systemImage: systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 16)
                                .hidden()
                        }
                default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(EdgeHandleButtonStyle(isActive: isActive))
        .accessibilityLabel(label)
        .animation(.smooth(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    switch dragDirection {
                    case .horizontal:
                        if abs(value.translation.width) > 24 {
                            action()
                        }
                    case .vertical:
                        if abs(value.translation.height) > 24 {
                            action()
                        }
                    }
                }
        )
    }
}

private struct CalendarSheet: View {
    let perfectDays: [String]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Perfect Days")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .cleanShotSurface(shape: Circle(), level: .control)
                }
                .buttonStyle(.plain)
            }

            YearPerfectCalendar(perfectDays: perfectDays)
        }
        .padding(18)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            level: .elevated,
            shadowRadius: 12
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.height > 50 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            onClose()
                        }
                    }
                }
        )
    }
}

private struct TodayHeader: View {
    let greeting: String
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 4 : 8) {
            Text(greeting)
                .font(.system(size: isCompact ? 22 : 30, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: 480)
        }
        .padding(.vertical, isCompact ? 6 : 12)
    }
}

private struct AddHabitBar: View {
    @Binding var newHabitTitle: String
    let onAddHabit: () -> Void

    @State private var isHovered = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Add a new habit...", text: $newHabitTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.leading, 16)
                .focused($fieldFocused)
                .onSubmit(onAddHabit)

            if !newHabitTitle.isEmpty {
                Button(action: onAddHabit) {
                    Text("Add")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(CleanShotTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.82, anchor: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, newHabitTitle.isEmpty ? 16 : 5)
        .frame(height: 46)
        .cleanShotSurface(
            shape: Capsule(),
            level: .control,
            isActive: fieldFocused || isHovered
        )
        .animation(.easeOut(duration: 0.15), value: newHabitTitle.isEmpty)
        .animation(.smooth(duration: 0.16), value: fieldFocused)
        .onHover { isHovered = $0 }
    }
}

private struct HabitListSection: View {
    let habits: [Habit]
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void

    private var doneCount: Int {
        habits.filter { $0.completedDayKeys.contains(todayKey) }.count
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's habits")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(doneCount)/\(habits.count) done")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 4)

            LazyVStack(spacing: 6) {
                ForEach(habits) { habit in
                    HabitCard(
                        habit: habit,
                        todayKey: todayKey,
                        onToggle: onToggle,
                        onDelete: onDelete
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MinimalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CleanShotTheme.canvas(for: colorScheme)
            .ignoresSafeArea()
    }
}

private struct StatsSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var level: Int { (dashboard?.rewards.xp ?? metrics.totalChecks) / 100 + 1 }
    private var xp: Int { (dashboard?.rewards.xp ?? metrics.totalChecks) % 100 }
    private var percent: Int { Int((metrics.progressToday * 100).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LevelHeroCard(metrics: metrics, dashboard: dashboard)

                // MARK: - Hero Streak Ring
                ZStack {
                    Circle()
                        .stroke(CleanShotTheme.controlFill(for: colorScheme), lineWidth: 10)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: metrics.progressToday)
                        .stroke(
                            CleanShotTheme.success,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: metrics.progressToday)

                    VStack(spacing: 2) {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("today")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                // MARK: - Streak Highlight
                HStack(spacing: 14) {
                    StreakPill(
                        icon: "flame.fill",
                        value: "\(metrics.currentPerfectStreak)",
                        unit: "day streak",
                        color: CleanShotTheme.warning
                    )
                    StreakPill(
                        icon: "trophy.fill",
                        value: "\(metrics.bestPerfectStreak)",
                        unit: "best",
                        color: CleanShotTheme.gold
                    )
                }

                // MARK: - Stats Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatCard(icon: "checklist", label: "Habits", value: "\(metrics.totalHabits)", tint: CleanShotTheme.accent)
                    StatCard(icon: "checkmark.circle.fill", label: "Done", value: "\(metrics.doneToday)", tint: CleanShotTheme.success)
                    StatCard(icon: "bitcoinsign.circle.fill", label: "Coins", value: "\(dashboard?.rewards.coins ?? metrics.coins)", tint: CleanShotTheme.gold)
                    StatCard(icon: "bolt.fill", label: "XP", value: "\(dashboard?.rewards.xp ?? metrics.xp)", tint: CleanShotTheme.violet)
                }

                // MARK: - Level & XP
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CleanShotTheme.controlFill(for: colorScheme, active: true))
                            Text("\(level)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(CleanShotTheme.accent)
                        }
                        .frame(width: 44, height: 44)
                        .cleanShotSurface(shape: Circle(), level: .control)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(level)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(xp)/100 XP to next level")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(CleanShotTheme.controlFill(for: colorScheme))
                                .overlay(
                                    Capsule()
                                        .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 0.5)
                                )

                            Capsule()
                                .fill(CleanShotTheme.accent)
                                .frame(width: max(geo.size.width * CGFloat(xp) / 100.0, 6))
                                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: xp)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(14)
                .cleanShotSurface(
                    shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    level: .control
                )

                WeeklyChallengeCard(metrics: metrics, dashboard: dashboard)

                // MARK: - Achievements
                VStack(alignment: .leading, spacing: 10) {
                    Text("Achievements")
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 4)

                    ForEach(metrics.medals) { medal in
                        AchievementRow(medal: medal)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .sidebarSurfaceStyle()
    }
}

private struct LevelHeroCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var levelName: String {
        dashboard?.level.name ?? metrics.level.rawValue
    }

    private var level: UserLevel {
        UserLevel(rawValue: levelName) ?? metrics.level
    }

    private var consistencyPercent: Int {
        dashboard?.level.weeklyConsistencyPercent ?? metrics.weeklyConsistencyPercent
    }

    private var note: String {
        dashboard?.level.note ?? metrics.levelNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: level.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(level.tint)
                    .frame(width: 42, height: 42)
                    .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), level: .control)

                VStack(alignment: .leading, spacing: 2) {
                    Text(levelName)
                        .font(.headline)
                    Text("\(consistencyPercent)% weekly consistency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: metrics.nextLevelProgress)
                .tint(level.tint)

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

private struct WeeklyChallengeCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelTitle(systemImage: "flag.checkered", title: "Weekly challenge")
                Spacer()
                Text("#\(dashboard?.weeklyChallenge.rank ?? metrics.challengeRank)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(CleanShotTheme.accent)
            }

            Text(dashboard?.weeklyChallenge.title ?? "Complete 5 focused days")
                .font(.subheadline.weight(.semibold))

            ProgressView(value: challengeProgress)
                .tint(CleanShotTheme.accent)

            HStack {
                ForEach(displayLeaders) { leader in
                    ChallengeLeader(
                        name: leader.displayName,
                        score: "\(leader.score)/\(dashboard?.weeklyChallenge.targetPerfectDays ?? 5)"
                    )
                }
            }
        }
        .padding(14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }

    private var challengeProgress: Double {
        guard let weeklyChallenge = dashboard?.weeklyChallenge, weeklyChallenge.targetPerfectDays > 0 else {
            return metrics.challengeProgress
        }

        return min(Double(weeklyChallenge.completedPerfectDays) / Double(weeklyChallenge.targetPerfectDays), 1)
    }

    private var displayLeaders: [AccountabilityDashboard.LeaderboardEntry] {
        if let leaderboard = dashboard?.weeklyChallenge.leaderboard, !leaderboard.isEmpty {
            return Array(leaderboard.prefix(3))
        }

        return [
            AccountabilityDashboard.LeaderboardEntry(displayName: "Maya", score: 5, currentUser: false),
            AccountabilityDashboard.LeaderboardEntry(displayName: "You", score: metrics.perfectDaysCount, currentUser: true),
            AccountabilityDashboard.LeaderboardEntry(displayName: "Leo", score: 3, currentUser: false)
        ]
    }
}

private struct ChallengeLeader: View {
    let name: String
    let score: String

    var body: some View {
        VStack(spacing: 3) {
            Text(name)
                .font(.caption2.weight(.semibold))
            Text(score)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 9, style: .continuous),
            level: .control
        )
    }
}

private struct StreakPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

private struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct HabitSidebar: View {
    let habits: [Habit]
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Habits")
                    .font(.title3.bold())
                Spacer()
                Text("\(habits.count) \(habits.count == 1 ? "habit" : "habits")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if habits.isEmpty {
                ContentUnavailableView(
                    "No habits yet",
                    systemImage: "checklist",
                    description: Text("Add a habit in the center panel to start tracking today.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(habits) { habit in
                            HabitCard(
                                habit: habit,
                                todayKey: todayKey,
                                onToggle: onToggle,
                                onDelete: onDelete
                            )
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .padding(18)
        .sidebarSurfaceStyle()
    }
}

private struct HabitCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void

    @State private var isHovered = false
    @State private var deleteHovered = false

    private var doneToday: Bool { habit.completedDayKeys.contains(todayKey) }
    private var currentStreak: Int { HabitMetrics.currentStreak(for: habit.completedDayKeys, endingAt: todayKey) }
    private var bestStreak: Int { HabitMetrics.bestStreak(for: habit.completedDayKeys) }
    private var recentDays: [DayInfo] { DateKey.recentDays(count: 7) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onToggle(habit)
                }
            } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(doneToday ? CleanShotTheme.success : .secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(doneToday)
                    .foregroundStyle(doneToday ? .secondary : .primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if currentStreak > 0 {
                        Label("\(currentStreak)d", systemImage: "flame.fill")
                            .foregroundStyle(CleanShotTheme.warning)
                    }
                    if bestStreak > 0 {
                        Label("\(bestStreak)d best", systemImage: "trophy.fill")
                            .foregroundStyle(CleanShotTheme.gold)
                    }
                    HStack(spacing: 3) {
                        ForEach(recentDays) { day in
                            Circle()
                                .fill(
                                    habit.completedDayKeys.contains(day.key)
                                        ? CleanShotTheme.success
                                        : CleanShotTheme.controlFill(for: colorScheme)
                                )
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
            }

            Spacer(minLength: 4)

            Button(role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    onDelete(habit)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(deleteHovered ? Color.red : Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(deleteHovered ? 0.08 : 0.04))
                    )
            }
            .buttonStyle(.plain)
            .onHover { deleteHovered = $0 }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 560, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .scaleEffect(isHovered ? 1.008 : 1)
        .animation(.smooth(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct YearPerfectCalendar: View {
    @Environment(\.colorScheme) private var colorScheme

    let perfectDays: [String]

    private let columns = [GridItem(.adaptive(minimum: 122), spacing: 18)]
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var perfectSet: Set<String> { Set(perfectDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(String(year)) Perfect Days")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 12) {
                    LegendDot(title: "Not perfect", color: CleanShotTheme.controlFill(for: colorScheme))
                    LegendDot(title: "Perfect", color: CleanShotTheme.success)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...12, id: \.self) { month in
                    MonthDots(month: month, year: year, perfectSet: perfectSet)
                }
            }
        }
        .padding(8)
    }
}

private struct MonthDots: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let perfectSet: Set<String>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var days: [DayInfo] {
        DateKey.days(inMonth: month, year: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(monthName)
                .font(.caption.weight(.bold))

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(days) { day in
                    Circle()
                        .fill(
                            perfectSet.contains(day.key)
                                ? CleanShotTheme.success
                                : CleanShotTheme.controlFill(for: colorScheme)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .help(day.key)
                }
            }
        }
    }

    private var monthName: String {
        Calendar.current.monthSymbols[month - 1].prefix(3).description
    }
}

private struct AchievementRow: View {
    let medal: Medal

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(medal.unlocked ? CleanShotTheme.success.opacity(0.14) : Color.secondary.opacity(0.10))
                Image(systemName: medal.unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(medal.unlocked ? CleanShotTheme.success : .secondary.opacity(0.5))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(medal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medal.unlocked ? .primary : .secondary)
                Text(medal.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            level: .control,
            isActive: medal.unlocked
        )
        .opacity(medal.unlocked ? 1.0 : 0.65)
    }
}

private struct LegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Confetti Celebration

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let xVelocity: CGFloat
    let yVelocity: CGFloat
    let shape: Int // 0 = circle, 1 = rectangle, 2 = triangle
}

private struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var elapsed: TimeInterval = 0
    @State private var startDate = Date()

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan, .mint, .indigo
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                Canvas { context, canvasSize in
                    for particle in particles {
                        let t = elapsed
                        let gravity: CGFloat = 420
                        let drag: CGFloat = 0.97

                        let px = particle.x + particle.xVelocity * t * drag
                        let py = particle.y + particle.yVelocity * t * drag + 0.5 * gravity * t * t
                        let angle = Angle.degrees(particle.rotation + t * 180)

                        guard px > -20, px < canvasSize.width + 20,
                              py < canvasSize.height + 40 else { continue }

                        context.opacity = max(1.0 - t * 0.4, 0)

                        switch particle.shape {
                        case 0:
                            let rect = CGRect(
                                x: px - particle.size / 2,
                                y: py - particle.size / 2,
                                width: particle.size,
                                height: particle.size
                            )
                            context.fill(
                                Circle().path(in: rect),
                                with: .color(particle.color)
                            )
                        case 1:
                            let transform = CGAffineTransform.identity
                                .translatedBy(x: px, y: py)
                                .rotated(by: angle.radians)
                            let rect = CGRect(
                                x: -particle.size * 0.6,
                                y: -particle.size * 0.3,
                                width: particle.size * 1.2,
                                height: particle.size * 0.6
                            )
                            let path = Rectangle().path(in: rect).applying(transform)
                            context.fill(path, with: .color(particle.color))
                        default:
                            var path = Path()
                            let s = particle.size
                            path.move(to: CGPoint(x: 0, y: -s / 2))
                            path.addLine(to: CGPoint(x: s / 2, y: s / 2))
                            path.addLine(to: CGPoint(x: -s / 2, y: s / 2))
                            path.closeSubpath()
                            let transform = CGAffineTransform.identity
                                .translatedBy(x: px, y: py)
                                .rotated(by: angle.radians)
                            context.fill(
                                path.applying(transform),
                                with: .color(particle.color)
                            )
                        }
                    }
                }
                .onChange(of: timeline.date) {
                    elapsed = timeline.date.timeIntervalSince(startDate)
                }
            }
            .onAppear {
                startDate = Date()
                spawnParticles(in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func spawnParticles(in size: CGSize) {
        let centerX = size.width / 2
        let topY = size.height * 0.15

        particles = (0..<80).map { _ in
            let angle = Double.random(in: -Double.pi * 0.85 ... -Double.pi * 0.15)
            let speed = CGFloat.random(in: 280...620)
            return ConfettiParticle(
                x: centerX + CGFloat.random(in: -60...60),
                y: topY + CGFloat.random(in: -20...20),
                size: CGFloat.random(in: 5...11),
                color: colors.randomElement() ?? .yellow,
                rotation: Double.random(in: 0...360),
                xVelocity: cos(angle) * speed,
                yVelocity: sin(angle) * speed,
                shape: Int.random(in: 0...2)
            )
        }
    }
}

private struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .padding(16)
            .cleanShotSurface(shape: shape, level: .base)
    }
}

private enum CleanShotSurfaceLevel {
    case base
    case elevated
    case control
}

private struct CleanShotSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let level: CleanShotSurfaceLevel
    let isActive: Bool
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(material, in: shape)
            .background(fill, in: shape)
            .overlay(
                shape
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: isActive), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: shadowColor, radius: appliedShadowRadius, y: appliedShadowRadius == 0 ? 0 : 6)
    }

    private var fill: Color {
        switch level {
        case .base:
            CleanShotTheme.surface(for: colorScheme)
        case .elevated:
            CleanShotTheme.elevatedSurface(for: colorScheme)
        case .control:
            CleanShotTheme.controlFill(for: colorScheme, active: isActive)
        }
    }

    private var material: Material {
        switch level {
        case .base:
            return .thinMaterial
        case .elevated:
            return .regularMaterial
        case .control:
            return .ultraThinMaterial
        }
    }

    private var appliedShadowRadius: CGFloat {
        switch level {
        case .base:
            return min(shadowRadius, 12)
        case .elevated:
            return min(shadowRadius, 18)
        case .control:
            return isActive ? 4 : 0
        }
    }

    private var shadowColor: Color {
        switch level {
        case .base:
            return CleanShotTheme.shadow(for: colorScheme)
        case .elevated:
            return CleanShotTheme.shadow(for: colorScheme, strong: true)
        case .control:
            return isActive ? CleanShotTheme.shadow(for: colorScheme) : .clear
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }

    func minimalPanel() -> some View {
        cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }

    func sidebarSurfaceStyle() -> some View {
        cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .elevated,
            shadowRadius: 12
        )
    }

    func cleanShotSurface<S: InsettableShape>(
        shape: S,
        level: CleanShotSurfaceLevel,
        isActive: Bool = false,
        shadowRadius: CGFloat = 10
    ) -> some View {
        modifier(
            CleanShotSurfaceModifier(
                shape: shape,
                level: level,
                isActive: isActive,
                shadowRadius: shadowRadius
            )
        )
    }
}

private struct PrimaryCircleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(CleanShotTheme.accent, in: Circle())
            .overlay(
                Circle()
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: true), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(CleanShotTheme.accent.opacity(configuration.isPressed ? 0.75 : 1.0), in: Capsule())
    }
}

private struct SecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? CleanShotTheme.accent : .primary)
            .background(CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct EdgeHandleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? CleanShotTheme.accent : .secondary)
            .background(
                CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed || isActive),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: isActive), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct HabitMetrics {
    let totalHabits: Int
    let totalChecks: Int
    let doneToday: Int
    let progressToday: Double
    let perfectDays: [String]
    let perfectDaysCount: Int
    let bestPerfectStreak: Int
    let currentPerfectStreak: Int
    let medals: [Medal]
    let level: UserLevel
    let xp: Int
    let coins: Int
    let weeklyConsistency: Double
    let weeklyConsistencyPercent: Int
    let nextLevelProgress: Double
    let mentorEligible: Bool
    let needsMentor: Bool
    let accountabilityScore: Int
    let missedToday: Int
    let mentorCandidate: MentorCandidate
    let mentorTip: String
    let feedPosts: [FeedPost]
    let challengeProgress: Double
    let challengeRank: Int
    let daysUntilMentor: Int
    let levelNote: String

    static func compute(for habits: [Habit], todayKey: String) -> HabitMetrics {
        let totalHabits = habits.count
        let totalChecks = habits.reduce(0) { $0 + Set($1.completedDayKeys).count }
        let doneToday = habits.filter { $0.completedDayKeys.contains(todayKey) }.count
        let progressToday = totalHabits > 0 ? Double(doneToday) / Double(totalHabits) : 0
        let perfectDays = perfectDayKeys(for: habits)
        let bestPerfectStreak = bestStreak(for: perfectDays)
        let currentAnchor = perfectDays.contains(todayKey) ? todayKey : DateKey.key(for: DateKey.addDays(DateKey.date(from: todayKey), -1))
        let currentPerfectStreak = currentStreak(for: perfectDays, endingAt: currentAnchor)
        let medals = achievementMedals(for: habits, perfectDays: perfectDays, totalChecks: totalChecks, bestPerfectStreak: bestPerfectStreak)
        let weeklyConsistency = weeklyConsistency(for: habits, todayKey: todayKey)
        let weeklyConsistencyPercent = Int((weeklyConsistency * 100).rounded())
        let historyDays = habitHistoryDays(for: habits, todayKey: todayKey)
        let hasSevenDayHistory = historyDays >= 7 || Set(habits.flatMap(\.completedDayKeys)).count >= 7
        let level = userLevel(
            totalChecks: totalChecks,
            weeklyConsistency: weeklyConsistency,
            bestPerfectStreak: bestPerfectStreak,
            hasSevenDayHistory: hasSevenDayHistory
        )
        let xp = totalChecks * 12 + perfectDays.count * 35 + bestPerfectStreak * 20
        let coins = totalChecks * 3 + perfectDays.count * 25
        let mentorEligible = hasSevenDayHistory && totalHabits > 0 && weeklyConsistency >= 0.82
        let needsMentor = hasSevenDayHistory && totalHabits > 0 && weeklyConsistency < 0.58
        let missedToday = max(totalHabits - doneToday, 0)
        let accountabilityScore = min(100, Int((weeklyConsistency * 70 + progressToday * 30).rounded()))
        let recentPerfectDays = recentPerfectDaysCount(perfectDays: perfectDays)
        let challengeProgress = min(Double(recentPerfectDays) / 5.0, 1.0)
        let challengeRank = max(1, 4 - min(recentPerfectDays, 3))
        let daysUntilMentor = mentorEligible ? 0 : max(0, 7 - historyDays)
        let nextLevelProgress = nextLevelProgress(for: level, weeklyConsistency: weeklyConsistency, totalChecks: totalChecks)
        let mentorCandidate = mentorCandidate(for: habits, needsMentor: needsMentor)
        let mentorTip = mentorTip(missedToday: missedToday, progressToday: progressToday, currentPerfectStreak: currentPerfectStreak)
        let feedPosts = feedPosts(currentPerfectStreak: currentPerfectStreak, weeklyConsistencyPercent: weeklyConsistencyPercent)
        let levelNote = levelNote(for: level, mentorEligible: mentorEligible, needsMentor: needsMentor, daysUntilMentor: daysUntilMentor)

        return HabitMetrics(
            totalHabits: totalHabits,
            totalChecks: totalChecks,
            doneToday: doneToday,
            progressToday: progressToday,
            perfectDays: perfectDays,
            perfectDaysCount: perfectDays.count,
            bestPerfectStreak: bestPerfectStreak,
            currentPerfectStreak: currentPerfectStreak,
            medals: medals,
            level: level,
            xp: xp,
            coins: coins,
            weeklyConsistency: weeklyConsistency,
            weeklyConsistencyPercent: weeklyConsistencyPercent,
            nextLevelProgress: nextLevelProgress,
            mentorEligible: mentorEligible,
            needsMentor: needsMentor,
            accountabilityScore: accountabilityScore,
            missedToday: missedToday,
            mentorCandidate: mentorCandidate,
            mentorTip: mentorTip,
            feedPosts: feedPosts,
            challengeProgress: challengeProgress,
            challengeRank: challengeRank,
            daysUntilMentor: daysUntilMentor,
            levelNote: levelNote
        )
    }

    private static func weeklyConsistency(for habits: [Habit], todayKey: String) -> Double {
        guard !habits.isEmpty else { return 0 }

        let recentKeys = DateKey.recentDays(count: 7, endingAt: DateKey.date(from: todayKey)).map(\.key)
        let completed = recentKeys.reduce(0) { total, key in
            total + habits.filter { $0.completedDayKeys.contains(key) }.count
        }
        return min(Double(completed) / Double(habits.count * recentKeys.count), 1)
    }

    private static func habitHistoryDays(for habits: [Habit], todayKey: String) -> Int {
        guard let firstDate = habits.map(\.createdAt).min() else { return 0 }

        let start = Calendar.current.startOfDay(for: firstDate)
        let end = Calendar.current.startOfDay(for: DateKey.date(from: todayKey))
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(days + 1, 0)
    }

    private static func userLevel(
        totalChecks: Int,
        weeklyConsistency: Double,
        bestPerfectStreak: Int,
        hasSevenDayHistory: Bool
    ) -> UserLevel {
        guard hasSevenDayHistory else { return totalChecks > 8 ? .rising : .beginner }
        if weeklyConsistency >= 0.92 && bestPerfectStreak >= 21 { return .masterMentor }
        if weeklyConsistency >= 0.82 && totalChecks >= 30 { return .mentor }
        if weeklyConsistency >= 0.78 { return .elite }
        if weeklyConsistency >= 0.62 { return .consistent }
        if weeklyConsistency >= 0.34 { return .rising }
        return .beginner
    }

    private static func nextLevelProgress(for level: UserLevel, weeklyConsistency: Double, totalChecks: Int) -> Double {
        switch level {
        case .beginner:
            return min(Double(totalChecks) / 10.0, 1)
        case .rising:
            return min(weeklyConsistency / 0.62, 1)
        case .consistent:
            return min(weeklyConsistency / 0.78, 1)
        case .elite:
            return min(weeklyConsistency / 0.82, 1)
        case .mentor:
            return min(weeklyConsistency / 0.92, 1)
        case .masterMentor:
            return 1
        }
    }

    private static func recentPerfectDaysCount(perfectDays: [String]) -> Int {
        let perfectSet = Set(perfectDays)
        return DateKey.recentDays(count: 7).filter { perfectSet.contains($0.key) }.count
    }

    private static func mentorCandidate(for habits: [Habit], needsMentor: Bool) -> MentorCandidate {
        let focus = habits.first?.title ?? "Daily consistency"
        return MentorCandidate(
            name: needsMentor ? "Maya" : "Leo",
            focus: focus,
            timezone: TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "),
            language: Locale.current.identifier.split(separator: "_").first.map { String($0).uppercased() } ?? "EN",
            consistency: needsMentor ? 91 : 86
        )
    }

    private static func mentorTip(missedToday: Int, progressToday: Double, currentPerfectStreak: Int) -> String {
        if missedToday > 0 {
            return "Pick the smallest remaining habit and send your mentor a check-in after it is done."
        }
        if progressToday == 1 {
            return "Today is complete. Share one sentence about what made it easier."
        }
        if currentPerfectStreak > 0 {
            return "Protect the streak with one low-friction habit before the day gets busy."
        }
        return "Start with one habit. Accountability works best when the next step is obvious."
    }

    private static func feedPosts(currentPerfectStreak: Int, weeklyConsistencyPercent: Int) -> [FeedPost] {
        [
            FeedPost(author: "Maya", message: "Finished a 7-day morning routine streak.", meta: "Community win", systemImage: "flame"),
            FeedPost(author: "Leo", message: "Sent three check-ins and helped Noor restart.", meta: "Mentor XP +18", systemImage: "person.2"),
            FeedPost(author: "You", message: currentPerfectStreak > 0 ? "\(currentPerfectStreak)-day streak is active." : "\(weeklyConsistencyPercent)% consistency this week.", meta: "Progress update", systemImage: "chart.line.uptrend.xyaxis")
        ]
    }

    private static func levelNote(for level: UserLevel, mentorEligible: Bool, needsMentor: Bool, daysUntilMentor: Int) -> String {
        if needsMentor {
            return "A mentor match is ready. The goal is support, not pressure."
        }
        if mentorEligible {
            return "You can mentor another user with gentle nudges and encouragement."
        }
        if daysUntilMentor > 0 {
            return "Keep tracking for \(daysUntilMentor) more \(daysUntilMentor == 1 ? "day" : "days") to unlock mentor review."
        }
        return "Current rank: \(level.rawValue). Build consistency before chasing intensity."
    }

    static func currentStreak(for keys: [String], endingAt endKey: String) -> Int {
        let dateKeys = Set(keys)
        var streak = 0
        var cursor = DateKey.date(from: endKey)

        while dateKeys.contains(DateKey.key(for: cursor)) {
            streak += 1
            cursor = DateKey.addDays(cursor, -1)
        }

        return streak
    }

    static func bestStreak(for keys: [String]) -> Int {
        let sorted = Array(Set(keys)).sorted()
        guard !sorted.isEmpty else { return 0 }

        var best = 1
        var current = 1

        for index in sorted.indices.dropFirst() {
            let previous = DateKey.date(from: sorted[index - 1])
            let currentDate = DateKey.date(from: sorted[index])
            if Calendar.current.dateComponents([.day], from: previous, to: currentDate).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
        }

        return best
    }

    private static func perfectDayKeys(for habits: [Habit]) -> [String] {
        guard !habits.isEmpty else { return [] }

        let allKeys = Set(habits.flatMap(\.completedDayKeys))
        return allKeys
            .filter { key in habits.allSatisfy { $0.completedDayKeys.contains(key) } }
            .sorted()
    }

    private static func achievementMedals(for habits: [Habit], perfectDays: [String], totalChecks: Int, bestPerfectStreak: Int) -> [Medal] {
        [
            Medal(id: "first-perfect", title: "First Perfect Day", unlocked: !perfectDays.isEmpty, dateKey: perfectDays.first),
            Medal(id: "streak-7", title: "Streak 7", unlocked: bestPerfectStreak >= 7, dateKey: milestoneDate(in: perfectDays, threshold: 7)),
            Medal(id: "streak-21", title: "Streak 21", unlocked: bestPerfectStreak >= 21, dateKey: milestoneDate(in: perfectDays, threshold: 21)),
            Medal(id: "streak-50", title: "Streak 50", unlocked: bestPerfectStreak >= 50, dateKey: milestoneDate(in: perfectDays, threshold: 50)),
            Medal(id: "checks-100", title: "100 Checks", unlocked: totalChecks >= 100, dateKey: checksMilestoneDate(for: habits, threshold: 100)),
            Medal(id: "checks-500", title: "500 Checks", unlocked: totalChecks >= 500, dateKey: checksMilestoneDate(for: habits, threshold: 500))
        ]
    }

    private static func milestoneDate(in keys: [String], threshold: Int) -> String? {
        guard threshold > 0 else { return nil }

        var current = 0
        for index in keys.indices {
            if index == keys.startIndex {
                current = 1
            } else {
                let previous = DateKey.date(from: keys[index - 1])
                let currentDate = DateKey.date(from: keys[index])
                current = Calendar.current.dateComponents([.day], from: previous, to: currentDate).day == 1 ? current + 1 : 1
            }

            if current >= threshold {
                return keys[index]
            }
        }

        return nil
    }

    private static func checksMilestoneDate(for habits: [Habit], threshold: Int) -> String? {
        var countsByDate: [String: Int] = [:]
        for habit in habits {
            for key in Set(habit.completedDayKeys) {
                countsByDate[key, default: 0] += 1
            }
        }

        var total = 0
        for key in countsByDate.keys.sorted() {
            total += countsByDate[key, default: 0]
            if total >= threshold {
                return key
            }
        }

        return nil
    }
}

private struct Medal: Identifiable {
    let id: String
    let title: String
    let unlocked: Bool
    let dateKey: String?

    var subtitle: String {
        guard unlocked else { return "Locked" }
        guard let dateKey else { return "Unlocked" }
        return "Unlocked on \(DateKey.date(from: dateKey).formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

private struct DayInfo: Identifiable {
    let key: String
    let shortLabel: String

    var id: String { key }
}

private enum SmartGreeting {
    static func generate(habits: [Habit], todayKey: String, doneToday: Int, totalHabits: Int, currentStreak: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"

        guard totalHabits > 0 else { return timeGreeting }

        let completedHabits = habits.filter { $0.completedDayKeys.contains(todayKey) }
        let remaining = totalHabits - doneToday

        if doneToday == totalHabits {
            let celebrations = [
                "All done! You crushed it today",
                "Perfect day! Nothing left to do",
                "Everything checked off. Well done!",
                "100% complete. Take a well-deserved break",
                "All habits done! You're on fire"
            ]
            if currentStreak > 1 {
                return "\(currentStreak)-day perfect streak! Keep going"
            }
            return celebrations[stableIndex(for: todayKey, count: celebrations.count)]
        }

        if doneToday > 0 {
            let lastDone = completedHabits.last
            if let title = lastDone?.title {
                let prompts = [
                    "\(title) done — \(remaining) more to go!",
                    "Nice, \(title) is checked off! What's next?",
                    "\(title) complete! \(remaining) \(remaining == 1 ? "habit" : "habits") left",
                    "Knocked out \(title)! Keep the momentum"
                ]
                return prompts[stableIndex(for: todayKey + title, count: prompts.count)]
            }
            return "\(doneToday) of \(totalHabits) done — keep going!"
        }

        if currentStreak > 0 {
            return "\(timeGreeting) — \(currentStreak)-day streak on the line!"
        }

        let motivations = [
            "\(timeGreeting) — \(remaining) \(remaining == 1 ? "habit" : "habits") waiting for you",
            "\(timeGreeting)! Ready to start today?",
            "\(timeGreeting) — let's make today count",
            "Fresh day, \(remaining) \(remaining == 1 ? "habit" : "habits") to tackle"
        ]
        return motivations[stableIndex(for: todayKey, count: motivations.count)]
    }

    private static func stableIndex(for seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(count))
    }
}

private enum DateKey {
    static func key(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Calendar.current.startOfDay(for: Date()) }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Calendar.current.startOfDay(for: Date())
    }

    static func addDays(_ date: Date, _ amount: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: amount, to: date) ?? date
    }

    static func recentDays(count: Int, endingAt endDate: Date = Date()) -> [DayInfo] {
        let end = Calendar.current.startOfDay(for: endDate)
        return (0..<count).map { index in
            let date = addDays(end, index - (count - 1))
            return DayInfo(
                key: key(for: date),
                shortLabel: String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
            )
        }
    }

    static func days(inMonth month: Int, year: Int) -> [DayInfo] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: date(from: String(format: "%04d-%02d-01", year, month))) else {
            return []
        }

        return range.compactMap { day in
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) else {
                return nil
            }
            return DayInfo(key: key(for: date), shortLabel: "")
        }
    }
}

#Preview("Light") {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
        .preferredColorScheme(.dark)
}
