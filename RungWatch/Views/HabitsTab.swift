import SwiftUI
import WatchKit

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
            VStack(alignment: .leading, spacing: 6) {
                header
                progressBar
                habitsList
            }
            .padding(.horizontal, 11)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .watchPageHeader("HABITS", accent: WatchTheme.success, trailing: snapshot.timeOfDay)
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(snapshot.metrics.doneToday)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                Text("/\(snapshot.metrics.totalToday)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WatchTheme.inkSoft)
            }
            Text(snapshot.weekdayShort)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(WatchTheme.gold)
            Spacer()
            if snapshot.metrics.currentStreak > 0 {
                Text("\u{1F525}\(snapshot.metrics.currentStreak)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WatchTheme.gold)
            }
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
///
/// Binary manual habits (target == 0) flip done/not-done with a single tap
/// for live-feel parity with iPhone — the optimistic update inside
/// `WatchSession.toggleHabit` flips the row instantly and the iPhone's
/// re-broadcast confirms within a few hundred milliseconds. Counted manual
/// habits (water 6/8 etc.) still drill into the crown-rotation detail view.
private struct NavigationLinkOrButton: View {
    @EnvironmentObject private var session: WatchSession
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
        case .manual where habit.unitsTarget == 0:
            Button {
                WKInterfaceDevice.current().play(habit.isCompleted ? .click : .success)
                session.toggleHabit(id: habit.id)
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
