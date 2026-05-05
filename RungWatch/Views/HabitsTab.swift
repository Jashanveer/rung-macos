import SwiftUI
import WatchKit

/// Hero "DONE / TOTAL" with a circular progress ring filling most of the
/// screen, the next entry waiting under it, and a microphone button to add
/// a habit by voice. Tasks (`entryType == .task`) are surfaced alongside
/// habits and gain a long-press → Pomodoro affordance — held finger pops
/// the focus action sheet so the user can start a 25-minute session
/// without leaving the watch.
struct HabitsTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    /// Task currently being long-pressed — drives the running Pomodoro
    /// view directly (no intermediate menu, per user request). Nil =
    /// no session in flight.
    @State private var pomodoroTarget: WatchSnapshot.WatchHabit? = nil

    private var snapshot: WatchSnapshot { session.snapshot }
    private var nextEntry: WatchSnapshot.WatchHabit? {
        snapshot.pendingHabits.first
    }
    private var ringFraction: Double {
        guard snapshot.metrics.totalToday > 0 else { return 0 }
        return Double(snapshot.metrics.doneToday) / Double(snapshot.metrics.totalToday)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchPageTitle("Today", accent: WatchTheme.cAmber)
                hero
                if let nextEntry {
                    EntryRow(
                        habit: nextEntry,
                        style: .nextUp,
                        scale: scale,
                        onLongPress: pomodoroTarget(for: nextEntry)
                    )
                } else if !snapshot.completedHabits.isEmpty {
                    Text("All caught up")
                        .font(WatchTheme.font(.body, scale: scale, weight: .medium))
                        .foregroundStyle(WatchTheme.inkSoft)
                        .padding(.top, 4)
                } else {
                    Text("No habits yet.\nSwipe up to Add.")
                        .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                        .foregroundStyle(WatchTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }

                if snapshot.pendingHabits.count > 1 || !snapshot.completedHabits.isEmpty {
                    rest
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .watchWashBackground(.violet)
        .fullScreenCover(item: $pomodoroTarget) { task in
            // Long-press goes straight into the running Pomodoro
            // view — no action sheet, no extra confirmation. The user
            // already long-pressed; that IS their commitment.
            NavigationStack {
                PomodoroRunningView(habit: task) {
                    pomodoroTarget = nil
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            // Track + progress ring fills the watch face.
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 7)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(
                    WatchTheme.progressGradient,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(WatchMotion.smooth, value: ringFraction)
                .shadow(color: WatchTheme.cViolet.opacity(0.45), radius: 8)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(snapshot.metrics.doneToday)")
                        .font(WatchTheme.font(.hero, scale: scale, weight: .heavy))
                        .foregroundStyle(WatchTheme.ink)
                        .contentTransition(.numericText(value: Double(snapshot.metrics.doneToday)))
                        .animation(WatchMotion.snappy, value: snapshot.metrics.doneToday)
                    Text("/\(snapshot.metrics.totalToday)")
                        .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkSoft)
                        .contentTransition(.numericText(value: Double(snapshot.metrics.totalToday)))
                        .animation(WatchMotion.snappy, value: snapshot.metrics.totalToday)
                }
                Text("TODAY")
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(WatchTheme.inkSoft)
                    .padding(.top, -2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130 * scale)
        .padding(.top, 2)
    }

    // MARK: - Rest of entries (collapsed list under the hero)

    private var rest: some View {
        let remaining = Array(snapshot.pendingHabits.dropFirst())
        let completed = snapshot.completedHabits
        return VStack(spacing: 4) {
            ForEach(remaining) { entry in
                EntryRow(
                    habit: entry,
                    style: .compact,
                    scale: scale,
                    onLongPress: pomodoroTarget(for: entry)
                )
            }
            ForEach(completed) { entry in
                EntryRow(
                    habit: entry,
                    style: .compact,
                    scale: scale,
                    onLongPress: nil
                )
            }
        }
    }

    /// Long-press only opens Pomodoro on tasks (one-shot work units) —
    /// running a focus timer for "drink water" or other recurring habits
    /// would feel weird and corrupts the streak math iPhone owns.
    private func pomodoroTarget(for entry: WatchSnapshot.WatchHabit) -> ((WatchSnapshot.WatchHabit) -> Void)? {
        guard entry.entryType == .task, !entry.isCompleted else { return nil }
        return { task in
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.start)
            #endif
            pomodoroTarget = task
        }
    }

}

// MARK: - Unified entry row

/// One row in the Today list. Renders both habits and tasks — tasks gain
/// a flag glyph + a long-press gesture that hands the entry off to the
/// caller (HabitsTab opens the Pomodoro action sheet on long-press).
private struct EntryRow: View {
    enum Style { case nextUp, compact }

    @EnvironmentObject private var session: WatchSession

    let habit: WatchSnapshot.WatchHabit
    let style: Style
    let scale: Double
    let onLongPress: ((WatchSnapshot.WatchHabit) -> Void)?

    var body: some View {
        Group {
            if style == .nextUp {
                nextUpBody
            } else {
                compactBody
            }
        }
        .gesture(longPressIfTask)
    }

    @ViewBuilder
    private var nextUpBody: some View {
        let tint: Color = nextUpTint
        switch habit.kind {
        case .healthKit:
            NavigationLink {
                HealthDetailView(habit: habit)
            } label: { nextUpContent(tint: tint) }
            .buttonStyle(.plain)
        case .manual where habit.unitsTarget == 0:
            Button {
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.success)
                #endif
                session.toggleHabit(id: habit.id)
            } label: { nextUpContent(tint: tint) }
            .buttonStyle(.plain)
        case .manual:
            NavigationLink {
                HabitDetailView(habit: habit)
            } label: { nextUpContent(tint: tint) }
            .buttonStyle(.plain)
        }
    }

    private func nextUpContent(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(habit.emoji.isEmpty ? "•" : habit.emoji)
                    .font(.system(size: 22 * scale))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(habit.title)
                            .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                            .foregroundStyle(WatchTheme.ink)
                            .lineLimit(1)
                        if habit.entryType == .task {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8 * scale, weight: .heavy))
                                .foregroundStyle(WatchTheme.cAmber)
                        }
                    }
                    Text(subtitle)
                        .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                        .foregroundStyle(WatchTheme.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                trailing
            }
            if let suggestion = habit.suggestionLabel, !suggestion.isEmpty {
                Text(suggestion)
                    .font(WatchTheme.font(.label, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.cCyan)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 2)
            }
            if habit.entryType == .task && !habit.isCompleted {
                Text("HOLD ▸ FOCUS")
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WatchTheme.cAmber)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 14, tint: tint, strong: true)
    }

    private var nextUpTint: Color {
        if habit.kind == .healthKit { return WatchTheme.cRose }
        if habit.entryType == .task { return WatchTheme.cAmber }
        return WatchTheme.cCyan
    }

    @ViewBuilder
    private var compactBody: some View {
        Button {
            handleCompactTap()
        } label: {
            HStack(spacing: 8) {
                checkIcon
                Text(habit.title)
                    .font(WatchTheme.font(.body, scale: scale, weight: .regular))
                    .foregroundStyle(habit.isCompleted ? Color.white.opacity(0.6) : WatchTheme.ink)
                    .strikethrough(habit.isCompleted, color: .white.opacity(0.5))
                    .lineLimit(1)
                Spacer()
                if habit.kind == .healthKit {
                    Text("AUTO")
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(WatchTheme.cCyan)
                }
                if habit.entryType == .task && !habit.isCompleted {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9 * scale, weight: .heavy))
                        .foregroundStyle(WatchTheme.cAmber)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 11)
            .opacity(habit.isCompleted ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if habit.kind == .healthKit { return "APPLE HEALTH · AUTO" }
        if habit.unitsTarget > 0 { return "\(habit.unitsLogged) of \(habit.unitsTarget) \(habit.unitsLabel)" }
        if habit.entryType == .task { return "Tap to mark · hold to focus" }
        return "Tap to mark done"
    }

    @ViewBuilder
    private var trailing: some View {
        switch habit.kind {
        case .healthKit:
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 20 * scale))
                .foregroundStyle(WatchTheme.cRose)
                .symbolEffect(.pulse, options: .speed(0.4).repeating)
        case .manual where habit.unitsTarget == 0:
            Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22 * scale))
                .foregroundStyle(habit.isCompleted ? WatchTheme.cMint : WatchTheme.inkSoft)
                .contentTransition(.symbolEffect(.replace.byLayer))
                .symbolEffect(.bounce, value: habit.isCompleted)
                .animation(WatchMotion.snappy, value: habit.isCompleted)
        case .manual:
            Image(systemName: "chevron.right")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(WatchTheme.inkSoft)
        }
    }

    private func handleCompactTap() {
        switch habit.kind {
        case .healthKit:
            return
        case .manual where habit.unitsTarget == 0:
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(habit.isCompleted ? .click : .success)
            #endif
            session.toggleHabit(id: habit.id)
        case .manual:
            return
        }
    }

    @ViewBuilder
    private var checkIcon: some View {
        switch (habit.kind, habit.isCompleted) {
        case (.healthKit, _):
            Image(systemName: "heart.fill")
                .font(.system(size: 11 * scale))
                .foregroundStyle(WatchTheme.cRose)
                .frame(width: 16, height: 16)
        case (.manual, true):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14 * scale))
                .foregroundStyle(WatchTheme.cMint)
                .frame(width: 16, height: 16)
                .contentTransition(.symbolEffect(.replace.byLayer))
                .symbolEffect(.bounce, value: habit.isCompleted)
        case (.manual, false):
            Image(systemName: "circle")
                .font(.system(size: 14 * scale))
                .foregroundStyle(WatchTheme.inkSoft)
                .frame(width: 16, height: 16)
                .contentTransition(.symbolEffect(.replace.byLayer))
        }
    }

    /// Hand the row off on long-press only when the parent supplied a
    /// handler — this is how HabitsTab gates Pomodoro to tasks only.
    private var longPressIfTask: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                guard let onLongPress else { return }
                onLongPress(habit)
            }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HabitsTab()
            .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
    }
}
#endif
