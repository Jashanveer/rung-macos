#if os(iOS)
import ActivityKit
import Foundation

/// Shared payload for the Focus Mode Live Activity. Lives in `RungShared`
/// so both the main app target (which starts and updates activities) and
/// the RungWidgets target (which renders the lock-screen / Dynamic Island
/// UI) decode the same struct.
public struct FocusActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    /// State that mutates while the activity is live. Republished via
    /// `Activity.update(...)` whenever the user pauses, resumes, or rolls
    /// into the next pomodoro phase.
    public struct State: Codable, Hashable {
        /// Wall-clock end time. Lets the lock-screen widget render a
        /// `Text(timerInterval:)` countdown that ticks even while the app
        /// process is suspended — no per-second push needed.
        public var endsAt: Date
        /// Phase rawValue (`focus` / `shortBreak` / `longBreak`). Stored as
        /// String so future cases don't break old activity sessions.
        public var phaseRaw: String
        /// True when the user paused. The lock-screen freezes the timer
        /// readout until a resume update flips this back.
        public var isPaused: Bool

        public init(endsAt: Date, phaseRaw: String, isPaused: Bool) {
            self.endsAt = endsAt
            self.phaseRaw = phaseRaw
            self.isPaused = isPaused
        }
    }

    /// Static for the lifetime of the activity. The task title doesn't
    /// change once a session starts — moving it here saves re-encoding it
    /// on every state update.
    public var taskTitle: String

    public init(taskTitle: String) {
        self.taskTitle = taskTitle
    }
}
#endif
