import FoundationModels
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    @State private var newHabitTitle = ""
    @State private var progressOpen = false
    @State private var calendarOpen = false
    @State private var pointerLocation = UnitPoint(x: 0.68, y: 0.28)

    private var todayKey: String { DateKey.key(for: Date()) }
    private var metrics: HabitMetrics { HabitMetrics.compute(for: habits, todayKey: todayKey) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LiveGradientBackground(pointerLocation: pointerLocation)
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
                .offset(x: progressOpen ? -170 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: progressOpen)
                .zIndex(1)

                if progressOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                progressOpen = false
                            }
                        }

                    HStack {
                        Spacer()
                        StatsSidebar(metrics: metrics)
                            .frame(width: 330)
                            .padding(.trailing, 22)
                            .padding(.vertical, 22)
                            .transition(
                                .scale(scale: 0.01, anchor: .trailing)
                                .combined(with: .opacity)
                            )
                    }
                    .zIndex(3)
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
                            .scale(scale: 0.01, anchor: .bottom)
                            .combined(with: .opacity)
                        )
                    }
                    .zIndex(4)
                }

            }
            .onContinuousHover { phase in
                guard case let .active(location) = phase else { return }

                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                withAnimation(.smooth(duration: 0.35)) {
                    pointerLocation = UnitPoint(
                        x: min(max(location.x / width, 0), 1),
                        y: min(max(location.y / height, 0), 1)
                    )
                }
            }
        }
        .overlay(alignment: .trailing) {
            EdgePanelHandle(
                systemImage: "chart.bar.xaxis",
                label: "Progress",
                edge: .trailing,
                isActive: progressOpen,
                dragDirection: .horizontal
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    progressOpen.toggle()
                    if progressOpen {
                        calendarOpen = false
                    }
                }
            }
            .padding(.trailing, 8)
        }
        .overlay(alignment: .bottom) {
            EdgePanelHandle(
                systemImage: "calendar",
                label: "Calendar",
                edge: .bottom,
                isActive: calendarOpen,
                dragDirection: .vertical
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    calendarOpen.toggle()
                    if calendarOpen {
                        progressOpen = false
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func addHabit() {
        let title = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        withAnimation {
            modelContext.insert(Habit(title: title))
            newHabitTitle = ""
        }
    }

    private func toggleHabit(_ habit: Habit) {
        var keys = habit.completedDayKeys
        if let index = keys.firstIndex(of: todayKey) {
            keys.remove(at: index)
        } else {
            keys.append(todayKey)
        }

        withAnimation(.snappy(duration: 0.2)) {
            habit.completedDayKeys = keys.sorted()
        }
    }

    private func deleteHabit(_ habit: Habit) {
        withAnimation {
            modelContext.delete(habit)
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

    private var percent: Int { Int((metrics.progressToday * 100).rounded()) }
    private var isEmpty: Bool { habits.isEmpty }

    var body: some View {
        VStack(spacing: isEmpty ? 16 : 10) {
            if isEmpty {
                Spacer()
            }

            TodayHeader(
                greeting: displayGreeting,
                metrics: metrics,
                percent: percent,
                isCompact: !isEmpty
            )

            AddHabitBar(newHabitTitle: $newHabitTitle, onAddHabit: onAddHabit)
                .frame(maxWidth: 520)

            if isEmpty {
                Text("✨ Add your first habit to get started")
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
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isEmpty)
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

    var body: some View {
        Button(action: action) {
            Group {
                switch edge {
                case .trailing:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 74)
                case .bottom:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(EdgeHandleButtonStyle(isActive: isActive))
        .accessibilityLabel(label)
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
                Text("🔥 Perfect days")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }

            YearPerfectCalendar(perfectDays: perfectDays)
        }
        .padding(18)
        .liquidGlassBackground(
            shape: RoundedRectangle(cornerRadius: 30, style: .continuous),
            fillOpacity: 0.035,
            strokeOpacity: 0.26,
            shadowRadius: 24
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
    let metrics: HabitMetrics
    let percent: Int
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 4 : 8) {
            Text(greeting)
                .font(.system(size: isCompact ? 22 : 30, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: 480)

            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            if metrics.totalHabits > 0 {
                HStack(spacing: 6) {
                    ProgressView(value: metrics.progressToday)
                        .tint(.green)
                        .frame(width: 80)
                    Text("\(percent)%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, isCompact ? 6 : 12)
    }
}

private struct AddHabitBar: View {
    @Binding var newHabitTitle: String
    let onAddHabit: () -> Void

    @State private var isFocused = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)

            TextField("Add a new habit...", text: $newHabitTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.leading, 8)
                .padding(.vertical, 10)
                .focused($fieldFocused)
                .onSubmit(onAddHabit)

            if !newHabitTitle.isEmpty {
                Button(action: onAddHabit) {
                    Text("Add")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .padding(.trailing, 6)
            }
        }
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(fieldFocused ? 0.3 : 0.12), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.06), radius: fieldFocused ? 12 : 6, y: 3)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newHabitTitle.isEmpty)
        .onChange(of: fieldFocused) { isFocused = fieldFocused }
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
                Text("📋 Today's habits")
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

private struct LiveGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let pointerLocation: UnitPoint

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let pointer = CGPoint(
                    x: pointerLocation.x * size.width,
                    y: pointerLocation.y * size.height
                )

                ZStack {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [baseColor, Color(red: 0.06, green: 0.07, blue: 0.09)]
                            : [Color(red: 0.98, green: 0.99, blue: 1.00), Color(red: 0.93, green: 0.97, blue: 1.00)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    gradientOrb(
                        color: Color(red: 0.20, green: 0.52, blue: 1.00),
                        size: size.width * 0.56,
                        position: animatedPoint(
                            base: CGPoint(x: pointer.x, y: pointer.y),
                            radius: 54,
                            speed: 0.55,
                            phase: time
                        )
                    )

                    gradientOrb(
                        color: Color(red: 0.30, green: 0.80, blue: 0.68),
                        size: size.width * 0.50,
                        position: animatedPoint(
                            base: CGPoint(x: size.width * 0.30, y: size.height * 0.22),
                            radius: 70,
                            speed: 0.35,
                            phase: time + 1.2
                        )
                    )

                    gradientOrb(
                        color: Color(red: 1.00, green: 0.42, blue: 0.38),
                        size: size.width * 0.48,
                        position: animatedPoint(
                            base: CGPoint(x: size.width * 0.72, y: size.height * 0.78),
                            radius: 82,
                            speed: 0.30,
                            phase: time + 2.4
                        )
                    )

                    gradientOrb(
                        color: Color(red: 0.98, green: 0.74, blue: 0.24),
                        size: size.width * 0.38,
                        position: animatedPoint(
                            base: CGPoint(x: size.width * 0.18, y: size.height * 0.84),
                            radius: 46,
                            speed: 0.48,
                            phase: time + 0.6
                        )
                    )

                    LinearGradient(
                        colors: [
                            baseColor.opacity(colorScheme == .dark ? 0.32 : 0.04),
                            baseColor.opacity(colorScheme == .dark ? 0.62 : 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .compositingGroup()
            }
        }
        .ignoresSafeArea()
    }

    private var baseColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private func animatedPoint(base: CGPoint, radius: CGFloat, speed: Double, phase: TimeInterval) -> CGPoint {
        CGPoint(
            x: base.x + cos(phase * speed) * radius,
            y: base.y + sin(phase * speed * 1.18) * radius
        )
    }

    private func gradientOrb(color: Color, size: CGFloat, position: CGPoint) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(colorScheme == .dark ? 0.45 : 0.42),
                        color.opacity(colorScheme == .dark ? 0.18 : 0.24),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(size / 2, 1)
                )
            )
            .frame(width: size, height: size)
            .position(position)
            .blur(radius: 38)
            .blendMode(colorScheme == .dark ? .screen : .normal)
            .allowsHitTesting(false)
    }
}

private struct StatsSidebar: View {
    let metrics: HabitMetrics

    private var level: Int { metrics.totalChecks / 100 + 1 }
    private var xp: Int { metrics.totalChecks % 100 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📊 Progress")
                        .font(.title3.weight(.semibold))
                    Text("Your stats at a glance")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int((metrics.progressToday * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }

                    ProgressView(value: metrics.progressToday)
                        .tint(.green)

                    HStack {
                        Text("\(metrics.doneToday) of \(metrics.totalHabits) done")
                        Spacer()
                        Text("\(metrics.currentPerfectStreak)d perfect streak")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .minimalGlassPanel()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(systemImage: "chart.bar", title: "📊 Summary")

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatTile(label: "Total habits", value: "\(metrics.totalHabits)", systemImage: "pin.fill")
                        StatTile(label: "Done today", value: "\(metrics.doneToday)", systemImage: "checkmark.circle.fill")
                        StatTile(label: "Perfect streak", value: "\(metrics.currentPerfectStreak)d", systemImage: "flame.fill")
                        StatTile(label: "Best perfect", value: "\(metrics.bestPerfectStreak)d", systemImage: "trophy.fill")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(systemImage: "star", title: "⭐ Level")
                    HStack(spacing: 12) {
                        Text("Lv \(level)")
                            .font(.headline)
                            .frame(width: 54, height: 54)
                            .liquidGlassControl(shape: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text("XP: \(xp) / 100")
                                .font(.subheadline.weight(.semibold))
                            ProgressView(value: Double(xp), total: 100)
                                .tint(.blue)
                            Text("Next level in \(100 - xp) XP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(systemImage: "trophy", title: "🏆 Achievements")
                    ForEach(metrics.medals) { medal in
                        AchievementRow(medal: medal)
                    }
                }
            }
            .padding(18)
        }
        .sidebarGlassStyle()
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
        .sidebarGlassStyle()
    }
}

private struct HabitCard: View {
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
                    .foregroundStyle(doneToday ? .green : .secondary.opacity(0.6))
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
                            .foregroundStyle(.orange)
                    }
                    if bestStreak > 0 {
                        Label("\(bestStreak)d best", systemImage: "trophy.fill")
                            .foregroundStyle(.yellow)
                    }
                    HStack(spacing: 3) {
                        ForEach(recentDays) { day in
                            Circle()
                                .fill(habit.completedDayKeys.contains(day.key) ? Color.green : Color.primary.opacity(0.1))
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 0.7 : 0.45)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct YearPerfectCalendar: View {
    let perfectDays: [String]

    private let columns = [GridItem(.adaptive(minimum: 122), spacing: 18)]
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var perfectSet: Set<String> { Set(perfectDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("🗓️ \(String(year)) Perfect Days")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 12) {
                    LegendDot(title: "Not perfect", color: Color.black.opacity(0.12))
                    LegendDot(title: "Perfect", color: .green)
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
                        .fill(perfectSet.contains(day.key) ? Color.green : Color.black.opacity(0.12))
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

private struct StatTile: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
                .minimalGlassPanel()

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
            .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .minimalGlassPanel()
    }
}

private struct AchievementRow: View {
    let medal: Medal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: medal.unlocked ? "checkmark.seal.fill" : "lock.fill")
                .foregroundStyle(medal.unlocked ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(medal.title)
                    .font(.subheadline.weight(.semibold))
                Text(medal.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .minimalGlassPanel()
    }
}

private struct SectionHeader: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.headline)
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

private struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        content
            .padding(16)
            .liquidGlassBackground(shape: shape, fillOpacity: 0.06, strokeOpacity: 0.34)
            .shadow(color: Color.black.opacity(0.13), radius: 18, x: 0, y: 8)
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }

    func minimalGlassPanel() -> some View {
        liquidGlassBackground(
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
            fillOpacity: 0.025,
            strokeOpacity: 0.24,
            shadowRadius: 10
        )
    }

    func sidebarGlassStyle() -> some View {
        liquidGlassBackground(
            shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
            fillOpacity: 0.02,
            strokeOpacity: 0.12,
            shadowRadius: 0
        )
    }

    func liquidGlassControl() -> some View {
        liquidGlassControl(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func liquidGlassControl<S: InsettableShape>(shape: S) -> some View {
        liquidGlassBackground(shape: shape, fillOpacity: 0.045, strokeOpacity: 0.32, shadowRadius: 8, interactive: true)
    }

    @ViewBuilder
    func liquidGlassBackground<S: InsettableShape>(
        shape: S,
        fillOpacity: Double,
        strokeOpacity: Double,
        shadowRadius: CGFloat = 12,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(Color.white.opacity(fillOpacity), in: shape)
                .glassEffect(.regular.interactive(interactive), in: shape)
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.00)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .overlay(
                    shape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(shadowRadius == 0 ? 0 : 0.10), radius: shadowRadius, x: 0, y: shadowRadius / 2)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(fillOpacity + 0.10),
                                    Color.white.opacity(fillOpacity),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    shape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(shadowRadius == 0 ? 0 : 0.10), radius: shadowRadius, x: 0, y: shadowRadius / 2)
        }
    }
}

private struct PrimaryCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color.blue, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.95), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.30), lineWidth: 1)
            )
    }
}

private struct EdgeHandleButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.72))
            .background(
                Color.white.opacity(configuration.isPressed || isActive ? 0.13 : 0.055),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isActive ? 0.36 : 0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
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

    static func compute(for habits: [Habit], todayKey: String) -> HabitMetrics {
        let totalHabits = habits.count
        let totalChecks = habits.reduce(0) { $0 + Set($1.completedDayKeys).count }
        let doneToday = habits.filter { $0.completedDayKeys.contains(todayKey) }.count
        let progressToday = totalHabits > 0 ? Double(doneToday) / Double(totalHabits) : 0
        let perfectDays = perfectDays(for: habits)
        let bestPerfectStreak = bestStreak(for: perfectDays)
        let currentAnchor = perfectDays.contains(todayKey) ? todayKey : DateKey.key(for: DateKey.addDays(DateKey.date(from: todayKey), -1))
        let currentPerfectStreak = currentStreak(for: perfectDays, endingAt: currentAnchor)
        let medals = medals(for: habits, perfectDays: perfectDays, totalChecks: totalChecks, bestPerfectStreak: bestPerfectStreak)

        return HabitMetrics(
            totalHabits: totalHabits,
            totalChecks: totalChecks,
            doneToday: doneToday,
            progressToday: progressToday,
            perfectDays: perfectDays,
            perfectDaysCount: perfectDays.count,
            bestPerfectStreak: bestPerfectStreak,
            currentPerfectStreak: currentPerfectStreak,
            medals: medals
        )
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

    private static func perfectDays(for habits: [Habit]) -> [String] {
        guard !habits.isEmpty else { return [] }

        let allKeys = Set(habits.flatMap(\.completedDayKeys))
        return allKeys
            .filter { key in habits.allSatisfy { $0.completedDayKeys.contains(key) } }
            .sorted()
    }

    private static func medals(for habits: [Habit], perfectDays: [String], totalChecks: Int, bestPerfectStreak: Int) -> [Medal] {
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
