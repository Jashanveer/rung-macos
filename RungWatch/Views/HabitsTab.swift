import SwiftUI
import WatchKit

/// Hero "DONE / TOTAL" with a circular progress ring filling most of the
/// screen, the next habit waiting under it, and a microphone button to add
/// a habit by voice. Modeled on the Activity-app and Workout-app aesthetic
/// — one big number, one supporting metric, no chrome.
struct HabitsTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    @State private var voiceSheetShown = false
    @State private var voiceText: String = ""

    private var snapshot: WatchSnapshot { session.snapshot }
    private var nextHabit: WatchSnapshot.WatchHabit? {
        snapshot.pendingHabits.first
    }
    private var ringFraction: Double {
        guard snapshot.metrics.totalToday > 0 else { return 0 }
        return Double(snapshot.metrics.doneToday) / Double(snapshot.metrics.totalToday)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 10) {
                    hero
                    if let nextHabit {
                        HabitNextUpRow(habit: nextHabit)
                    } else if !snapshot.completedHabits.isEmpty {
                        Text("All caught up.")
                            .font(WatchTheme.font(.body, scale: scale, weight: .medium))
                            .foregroundStyle(WatchTheme.inkSoft)
                            .padding(.top, 4)
                    } else {
                        Text("No habits yet.\nTap the mic to add one.")
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
                .padding(.bottom, 28)
            }

            voiceButton
                .padding(.bottom, 8)
                .padding(.trailing, 6)
        }
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
        .sheet(isPresented: $voiceSheetShown) {
            VoiceAddSheet(text: $voiceText) { final in
                let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                session.createHabit(title: trimmed)
                voiceText = ""
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            // Track + progress ring fills the watch face.
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 7)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(
                    WatchTheme.progressGradient,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ringFraction)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(snapshot.metrics.doneToday)")
                        .font(WatchTheme.font(.hero, scale: scale, weight: .heavy))
                        .foregroundStyle(WatchTheme.ink)
                    Text("/\(snapshot.metrics.totalToday)")
                        .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkSoft)
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

    // MARK: - Rest of habits (collapsed list under the hero)

    private var rest: some View {
        let remaining = Array(snapshot.pendingHabits.dropFirst())
        let completed = snapshot.completedHabits
        return VStack(spacing: 4) {
            ForEach(remaining) { habit in
                CompactHabitRow(habit: habit)
            }
            ForEach(completed) { habit in
                CompactHabitRow(habit: habit)
            }
        }
    }

    // MARK: - Voice button

    private var voiceButton: some View {
        Button {
            voiceText = ""
            voiceSheetShown = true
        } label: {
            ZStack {
                Circle()
                    .fill(WatchTheme.brandGradient)
                Image(systemName: "mic.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32 * scale, height: 32 * scale)
            .shadow(color: WatchTheme.accent.opacity(0.5), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Next-up (the primary actionable row, big tap target)

private struct HabitNextUpRow: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double
    let habit: WatchSnapshot.WatchHabit

    var body: some View {
        switch habit.kind {
        case .healthKit:
            NavigationLink {
                HealthDetailView(habit: habit)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        case .manual where habit.unitsTarget == 0:
            Button {
                WKInterfaceDevice.current().play(.success)
                session.toggleHabit(id: habit.id)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        case .manual:
            NavigationLink {
                HabitDetailView(habit: habit)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text(habit.emoji.isEmpty ? "•" : habit.emoji)
                .font(.system(size: 22 * scale))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(habit.title)
                    .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subtitle: String {
        if habit.kind == .healthKit { return "APPLE HEALTH · AUTO" }
        if habit.unitsTarget > 0 { return "\(habit.unitsLogged) of \(habit.unitsTarget) \(habit.unitsLabel)" }
        return "Tap to mark done"
    }

    @ViewBuilder
    private var trailing: some View {
        switch habit.kind {
        case .healthKit:
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 20 * scale))
                .foregroundStyle(WatchTheme.accent)
        case .manual where habit.unitsTarget == 0:
            Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22 * scale))
                .foregroundStyle(habit.isCompleted ? WatchTheme.success : WatchTheme.inkSoft)
        case .manual:
            Image(systemName: "chevron.right")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(WatchTheme.inkSoft)
        }
    }

    private var rowBackground: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Compact row (everything after the next-up)

private struct CompactHabitRow: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double
    let habit: WatchSnapshot.WatchHabit

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 8) {
                checkIcon
                Text(habit.title)
                    .font(WatchTheme.font(.body, scale: scale, weight: .regular))
                    .foregroundStyle(habit.isCompleted ? Color.white.opacity(0.6) : WatchTheme.ink)
                    .strikethrough(habit.isCompleted, color: .white.opacity(0.5))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func handleTap() {
        // Mirror the same action behavior as the next-up row but inline so
        // every row in the secondary list is just one tap away from done.
        switch habit.kind {
        case .healthKit:
            return    // healthKit rows don't toggle; user can still drill in via swipe
        case .manual where habit.unitsTarget == 0:
            WKInterfaceDevice.current().play(habit.isCompleted ? .click : .success)
            session.toggleHabit(id: habit.id)
        case .manual:
            return    // counted habits live in the next-up slot for crown logging
        }
    }

    @ViewBuilder
    private var checkIcon: some View {
        switch (habit.kind, habit.isCompleted) {
        case (.healthKit, _):
            Image(systemName: "heart.fill")
                .font(.system(size: 11 * scale))
                .foregroundStyle(WatchTheme.accent)
                .frame(width: 16, height: 16)
        case (.manual, true):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14 * scale))
                .foregroundStyle(WatchTheme.success)
                .frame(width: 16, height: 16)
        case (.manual, false):
            Image(systemName: "circle")
                .font(.system(size: 14 * scale))
                .foregroundStyle(WatchTheme.inkSoft)
                .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Voice add-habit sheet

private struct VoiceAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.watchFontScale) private var scale: Double
    @Binding var text: String
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("New habit")
                .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
            // watchOS auto-presents Dictation / Scribble / suggestions when
            // a TextField becomes first responder, so the mic icon on the
            // input chooser is the actual voice entry point.
            TextField("Speak or scribble", text: $text)
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit {
                    onSubmit(text)
                    dismiss()
                }
            Button("Add") {
                onSubmit(text)
                dismiss()
            }
            .font(WatchTheme.font(.body, scale: scale, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WatchTheme.brandGradient)
            )
            .buttonStyle(.plain)
        }
        .padding(12)
        .containerBackground(WatchTheme.bg.gradient, for: .navigation)
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
