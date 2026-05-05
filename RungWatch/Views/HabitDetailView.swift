import SwiftUI
import WatchKit

/// Drill-in view for a manual habit. Shows a circular ring + count, and uses
/// `digitalCrownRotation` to let the user log +1 unit per click. Each tick
/// fires `WKHapticType.click` and pushes a `logHabit` message back to the iPhone.
struct HabitDetailView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    let habit: WatchSnapshot.WatchHabit

    /// Digital-crown driven counter. Initialised to the iPhone's authoritative
    /// `unitsLogged`; subsequent rotations bump it locally and tell the phone.
    @State private var crownValue: Double = 0
    @State private var localUnits: Int = 0
    @State private var lastTickedUnits: Int = 0
    @State private var ringPulse: Bool = false
    /// `true` once the user taps "Start workout" — drives the
    /// `NavigationLink` push into `WatchWorkoutView`. Bound state instead
    /// of NavigationLink(value:) because we want to fire-and-forget the
    /// HK request as soon as the link activates, not after navigation.
    @State private var presentWorkout: Bool = false

    private var target: Int { max(habit.unitsTarget, 1) }
    private var ringFraction: Double {
        min(1.0, Double(localUnits) / Double(target))
    }

    /// True when this habit's canonical key maps to a watchOS-supported
    /// `HKWorkoutActivityType`. Drives the "Start workout" CTA so chores
    /// and contemplative rows still get the original crown counter.
    private var supportsWorkout: Bool {
        WatchWorkoutController.supports(canonicalKey: habit.canonicalKey)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(habit.emoji.isEmpty ? "•" : habit.emoji)
                .font(.system(size: 22))

            Text(habit.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .padding(.bottom, 3)

            ZStack {
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(WatchTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: ringFraction)

                VStack(spacing: 0) {
                    Text("\(localUnits)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WatchTheme.ink)
                        .scaleEffect(ringPulse ? 1.08 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: ringPulse)
                    if habit.unitsTarget > 0 {
                        Text("OF \(habit.unitsTarget) \(habit.unitsLabel)")
                            .font(.system(size: 7.5, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(WatchTheme.inkSoft)
                    } else {
                        Text("LOGGED")
                            .font(.system(size: 7.5, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(WatchTheme.inkSoft)
                    }
                }
            }
            .frame(width: 88, height: 88)

            if supportsWorkout {
                // Cardio / strength canonical — kick off a real
                // HKWorkoutSession so the saved workout auto-verifies the
                // habit on iPhone. Crown still works as a manual fallback
                // beneath the button.
                NavigationLink(isActive: $presentWorkout) {
                    WatchWorkoutView(habit: habit)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                        Text("Start workout")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WatchTheme.brandGradient)
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    Task {
                        await WatchWorkoutController.shared.start(canonicalKey: habit.canonicalKey ?? "workout")
                    }
                })
                .padding(.top, 4)

                Text("\u{21BB} crown to log +1 manually")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkSoft)
                    .padding(.top, 2)
            } else {
                Text("\u{21BB} crown to log +1")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(WatchTheme.gold)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
        .watchWashNavigationBackground(.violet)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: 1_000_000,   // effectively unbounded; we only care about deltas
            by: 1,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: false   // we do our own taptics per +1
        )
        .onAppear {
            localUnits = max(habit.unitsLogged, 0)
            crownValue = Double(localUnits)
            lastTickedUnits = localUnits
        }
        .onChange(of: crownValue) { _, newValue in
            handleCrown(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("\u{2039}") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(WatchTheme.ink)
            }
        }
    }

    /// Each integer step of the crown logs +1. We snap the local counter to
    /// the rounded crown value, fire one haptic per actual unit increment,
    /// and push a delta message back to the phone.
    private func handleCrown(_ raw: Double) {
        let snapped = max(0, Int(raw.rounded()))
        if snapped == lastTickedUnits { return }

        let delta = snapped - lastTickedUnits
        lastTickedUnits = snapped
        localUnits = snapped

        if delta > 0 {
            WKInterfaceDevice.current().play(.click)
            ringPulse.toggle()
            session.logHabit(id: habit.id, delta: delta)
        }
    }
}

#Preview {
    NavigationStack {
        HabitDetailView(habit: .init(
            id: "demo",
            title: "Drink water",
            emoji: "\u{1F4A7}",
            kind: .manual,
            progress: 0.75,
            unitsLogged: 6,
            unitsTarget: 8,
            unitsLabel: "CUPS",
            isCompleted: false,
            sourceLabel: "",
            canonicalKey: "water"
        ))
        .environmentObject(WatchSession.shared)
    }
}
