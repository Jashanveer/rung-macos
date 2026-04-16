import SwiftUI

struct TodayHeader: View {
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

struct AddHabitBar: View {
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

struct HabitListSection: View {
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

struct MinimalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CleanShotTheme.canvas(for: colorScheme)
            .ignoresSafeArea()
    }
}


struct HabitSidebar: View {
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

struct HabitCard: View {
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

            // Sync status badge — shown when a write is pending or failed
            SyncStatusBadge(status: habit.syncStatus)

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

// MARK: - Sync status badge

/// Compact indicator shown on a HabitCard when the local record diverges from the server.
/// Hidden entirely when synced so it consumes no layout space.
private struct SyncStatusBadge: View {
    let status: SyncStatus
    @State private var spinning = false

    var body: some View {
        Group {
            switch status {
            case .synced, .deleted:
                Color.clear.frame(width: 0, height: 0)
            case .pending:
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinning)
                    .onAppear { spinning = true }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .help("Sync failed — will retry on next sync")
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.smooth(duration: 0.2), value: status)
    }
}

