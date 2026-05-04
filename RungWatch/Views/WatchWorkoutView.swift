import SwiftUI
import Combine
import WatchKit

/// In-progress UI for a watch-led HKWorkout session. Lands on top of
/// `HabitDetailView` once the user taps "Start workout" on a cardio
/// canonical row. Three readouts: elapsed time, heart rate, calories.
/// Single big "End" button; back chevron also calls End so a reflexive
/// swipe-to-dismiss doesn't strand a session.
struct WatchWorkoutView: View {
    @EnvironmentObject private var session: WatchSession
    @ObservedObject private var workout = WatchWorkoutController.shared
    @Environment(\.dismiss) private var dismiss

    let habit: WatchSnapshot.WatchHabit

    /// Tick the local clock every second so the elapsed-time label stays
    /// fresh even when no HK sample lands.
    @State private var nowTick: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 4) {
            Text(habit.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WatchTheme.inkSoft)
                .lineLimit(1)

            Text(elapsedLabel)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchTheme.ink)
                .padding(.top, 2)

            HStack(spacing: 14) {
                metric(value: heartRateLabel, label: "BPM", systemImage: "heart.fill", tint: .pink)
                metric(value: kcalLabel,      label: "KCAL", systemImage: "flame.fill", tint: .orange)
            }
            .padding(.top, 4)

            if let error = workout.lastError {
                Text(error)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(WatchTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                WKInterfaceDevice.current().play(.stop)
                workout.end()
                // Optimistically flip the row to done — auto-verification
                // will replace this with the proper `auto` tier when the
                // saved HKWorkout reaches the iPhone.
                session.toggleHabit(id: habit.id)
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    if workout.isFinishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "stop.fill")
                    }
                    Text(workout.isFinishing ? "Saving..." : "End workout")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.red, Color(red: 0.78, green: 0.18, blue: 0.20)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                )
            }
            .buttonStyle(.plain)
            .disabled(workout.isFinishing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .containerBackground(WatchTheme.bg.gradient, for: .navigation)
        .onReceive(timer) { now in nowTick = now }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("\u{2039}") {
                    workout.end()
                    session.toggleHabit(id: habit.id)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(WatchTheme.ink)
            }
        }
    }

    @ViewBuilder
    private func metric(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WatchTheme.ink)
            }
            Text(label)
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(1)
                .foregroundStyle(WatchTheme.inkSoft)
        }
    }

    private var elapsedLabel: String {
        let elapsed = workout.startedAt.map { nowTick.timeIntervalSince($0) } ?? 0
        let total = max(0, Int(elapsed))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private var heartRateLabel: String {
        guard let bpm = workout.heartRateBPM else { return "--" }
        return String(Int(bpm.rounded()))
    }

    private var kcalLabel: String {
        let value = workout.activeEnergyKCal
        guard value > 0 else { return "--" }
        return String(Int(value.rounded()))
    }
}
