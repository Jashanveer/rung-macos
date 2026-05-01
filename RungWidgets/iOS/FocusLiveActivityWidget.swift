#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen and Dynamic Island presentation for an in-flight focus
/// session. The activity's `state.endsAt` lets us render
/// `Text(timerInterval:)`, which iOS ticks down for free without push
/// updates — the app only republishes state when the user pauses,
/// resumes, or rolls into the next phase.
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock-screen / banner view.
            FocusLockScreenView(
                state: context.state,
                taskTitle: context.attributes.taskTitle
            )
            .activityBackgroundTint(palette(for: context.state.phaseRaw).first?.opacity(0.20))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — shown when the user long-presses or the
                // Island is large enough.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: phaseIcon(context.state.phaseRaw))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette(for: context.state.phaseRaw).first ?? .orange)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(state: context.state)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(phaseLabel(context.state.phaseRaw).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phaseRaw))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette(for: context.state.phaseRaw).first ?? .orange)
            } compactTrailing: {
                timerText(state: context.state)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: phaseIcon(context.state.phaseRaw))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette(for: context.state.phaseRaw).first ?? .orange)
            }
            .keylineTint(palette(for: context.state.phaseRaw).first ?? .orange)
        }
    }
}

// MARK: - Lock-screen view

private struct FocusLockScreenView: View {
    let state: FocusActivityAttributes.State
    let taskTitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: paletteFor(state.phaseRaw),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: phaseIconFor(state.phaseRaw))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(taskTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(phaseLabelFor(state.phaseRaw))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            timerTextFor(state: state)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Helpers (free functions so both views can call them)

private func paletteFor(_ phaseRaw: String) -> [Color] {
    switch phaseRaw {
    case "focus":
        return [
            Color(red: 1.00, green: 0.42, blue: 0.20),
            Color(red: 0.92, green: 0.18, blue: 0.34),
        ]
    case "shortBreak":
        return [
            Color(red: 0.18, green: 0.62, blue: 0.95),
            Color(red: 0.13, green: 0.42, blue: 0.78),
        ]
    case "longBreak":
        return [
            Color(red: 0.16, green: 0.78, blue: 0.55),
            Color(red: 0.10, green: 0.55, blue: 0.42),
        ]
    default:
        return [Color.gray, Color.gray.opacity(0.6)]
    }
}

private func phaseIconFor(_ phaseRaw: String) -> String {
    switch phaseRaw {
    case "focus":      return "bolt.fill"
    case "shortBreak": return "cup.and.saucer.fill"
    case "longBreak":  return "leaf.fill"
    default:           return "timer"
    }
}

private func phaseLabelFor(_ phaseRaw: String) -> String {
    switch phaseRaw {
    case "focus":      return "Focus"
    case "shortBreak": return "Short break"
    case "longBreak":  return "Long break"
    default:           return "Timer"
    }
}

@ViewBuilder
private func timerTextFor(state: FocusActivityAttributes.State) -> some View {
    if state.isPaused {
        // Paused: hold the static remaining string. Live ticking would
        // be misleading.
        Text("Paused")
    } else {
        // `Text(timerInterval:)` ticks down without push updates — iOS
        // re-renders the widget once per second on its own.
        Text(timerInterval: Date()...state.endsAt, countsDown: true)
    }
}

// Wrap helpers above with the same names DynamicIsland builders use
// inline. Keeping a duplicated tiny shim makes the call sites easier to
// scan than threading parameters everywhere.
private func palette(for phaseRaw: String) -> [Color] { paletteFor(phaseRaw) }
private func phaseIcon(_ phaseRaw: String) -> String { phaseIconFor(phaseRaw) }
private func phaseLabel(_ phaseRaw: String) -> String { phaseLabelFor(phaseRaw) }

@ViewBuilder
private func timerText(state: FocusActivityAttributes.State) -> some View {
    timerTextFor(state: state)
}
#endif
