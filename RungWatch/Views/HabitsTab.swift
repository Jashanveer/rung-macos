import SwiftUI

/// Tab 1 — homepage. Shows pending habits as a vertical list.
/// HealthKit-linked rows display a ♥ AUTO badge instead of a hollow circle
/// and are read-only (tapping drills into a HealthDetailView).
struct HabitsTab: View {
    @EnvironmentObject private var session: WatchSession

    private var snapshot: WatchSnapshot { session.snapshot }
    private var allHabits: [WatchSnapshot.WatchHabit] {
        snapshot.pendingHabits + snapshot.completedHabits
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                header
                progressBar
                habitsList
            }
            .padding(.horizontal, 11)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // "4/7" — done count over total
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(snapshot.metrics.doneToday)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("/\(snapshot.metrics.totalToday)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WatchTheme.inkSoft)
            }
            // "WED · 9:41"
            Text("\(snapshot.weekdayShort) · \(snapshot.timeOfDay)")
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
        }
    }

    private var progressBar: some View {
        let p = snapshot.metrics.totalToday == 0
            ? 0.0
            : Double(snapshot.metrics.doneToday) / Double(snapshot.metrics.totalToday)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(WatchTheme.progressGradient)
                    .frame(width: max(0, proxy.size.width * p))
            }
        }
        .frame(height: 2.5)
    }

    // MARK: - Habits

    private var habitsList: some View {
        VStack(spacing: 2.5) {
            ForEach(allHabits) { habit in
                NavigationLinkOrButton(habit: habit)
            }
        }
    }
}

// MARK: - Row + Drill-in

/// Wraps each habit row in either a NavigationLink (drill-in) or a Button
/// (toggle for binary manuals). Auto-verified rows can still drill in to
/// see the synced number, but their tap behaviour never mutates state.
private struct NavigationLinkOrButton: View {
    let habit: WatchSnapshot.WatchHabit

    var body: some View {
        switch habit.kind {
        case .healthKit:
            NavigationLink {
                HealthDetailView(habit: habit)
            } label: {
                HabitRow(habit: habit)
            }
            .buttonStyle(.plain)
        case .manual:
            NavigationLink {
                HabitDetailView(habit: habit)
            } label: {
                HabitRow(habit: habit)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HabitRow: View {
    let habit: WatchSnapshot.WatchHabit

    var body: some View {
        HStack(spacing: 7) {
            checkBadge

            Text(habit.title)
                .font(.system(size: 10, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(habit.isCompleted, color: .white.opacity(0.7))
                .foregroundStyle(habit.isCompleted ? Color.white.opacity(0.7) : WatchTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingLabel
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Hollow circle for incomplete manual rows; filled green check for
    /// completed; outlined accent ♥ for HealthKit-linked rows.
    @ViewBuilder
    private var checkBadge: some View {
        switch (habit.kind, habit.isCompleted) {
        case (.healthKit, _):
            ZStack {
                Circle()
                    .fill(WatchTheme.accent.opacity(0.2))
                Circle()
                    .stroke(WatchTheme.accent, lineWidth: 1.5)
                Text("\u{2665}")  // ♥
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WatchTheme.accent)
            }
            .frame(width: 14, height: 14)
        case (.manual, true):
            ZStack {
                Circle().fill(WatchTheme.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 14, height: 14)
        case (.manual, false):
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private var trailingLabel: some View {
        switch habit.kind {
        case .healthKit:
            Text("HEALTH")
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(WatchTheme.accent)
        case .manual:
            if habit.unitsTarget > 0 {
                Text("\(habit.unitsLogged)/\(habit.unitsTarget)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkSoft)
            } else {
                EmptyView()
            }
        }
    }

    /// Gold-tinted "focused" background for the first row in the design mock —
    /// we mirror that on whichever pending row the user is most likely to tap
    /// next (first incomplete manual habit). Falls back to the default glass
    /// look for everything else.
    @ViewBuilder
    private var rowBackground: some View {
        if isFocused {
            LinearGradient(
                colors: [WatchTheme.gold.opacity(0.16), WatchTheme.gold.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WatchTheme.gold.opacity(0.45), lineWidth: 0.5)
            )
        } else {
            Color.clear
        }
    }

    /// Marks a row as the "next thing to do" so it gets the gold focus tint.
    /// Conservative: only the first uncompleted manual habit qualifies.
    private var isFocused: Bool {
        habit.kind == .manual && !habit.isCompleted && habit.progress > 0 && habit.progress < 1
    }
}

#Preview {
    NavigationStack {
        HabitsTab()
            .environmentObject(WatchSession.shared)
    }
}
