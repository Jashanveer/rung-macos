#if os(iOS)
import ActivityKit
import Foundation

/// Shared payload for the Focus Mode Live Activity. The struct lives in
/// the main app target; **add this same file to the RungWidgets target
/// (Target Membership in Xcode's File Inspector)** so the widget bundle
/// can decode the same payload it presents on the lock screen / Dynamic
/// Island.
///
/// Companion widget view to add to RungWidgets: see `FocusLiveActivityWidget`
/// guidance at the bottom of this file. Without that widget bundle entry
/// ActivityKit will start the activity but iOS won't have a UI to show.
struct FocusActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    /// State that mutates while the activity is live. Re-published every
    /// few seconds via `update(...)` so the lock-screen + Dynamic Island
    /// stay in sync with the in-app timer.
    public struct State: Codable, Hashable {
        /// Wall-clock end time. Lets the lock-screen widget render a
        /// `Text(timerInterval:)` countdown that ticks even when the app
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
    /// change once the user kicks off a session — moving it here saves
    /// re-encoding it on every state update.
    public var taskTitle: String

    public init(taskTitle: String) {
        self.taskTitle = taskTitle
    }
}

/// Bridges `FocusController` into ActivityKit. The controller calls
/// `start(...)`, `updateProgress(...)`, and `end()` at the right moments.
/// Falls back to a no-op on platforms / OS versions where Live Activities
/// aren't supported (older iOS, all macOS), so callers can fire-and-forget.
///
/// All methods are MainActor-isolated to keep ActivityKit calls serialized.
@MainActor
enum FocusLiveActivityManager {
    /// Start a Live Activity for the given session. Returns silently if the
    /// user disabled Live Activities for the app or the system rejects the
    /// request (e.g. above the allowed concurrent activity cap).
    static func start(taskTitle: String, phaseRaw: String, endsAt: Date, isPaused: Bool) {
        guard #available(iOS 16.1, *) else { return }
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else { return }

        // Avoid stacking duplicate activities for the same session — the
        // controller calls `start` whenever the phase rolls, so we end any
        // prior activity first.
        Task { await endAll() }

        let attributes = FocusActivityAttributes(taskTitle: taskTitle)
        let state = FocusActivityAttributes.State(
            endsAt: endsAt,
            phaseRaw: phaseRaw,
            isPaused: isPaused
        )
        do {
            if #available(iOS 16.2, *) {
                _ = try Activity<FocusActivityAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(60)),
                    pushType: nil
                )
            } else {
                _ = try Activity<FocusActivityAttributes>.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            }
        } catch {
            // Activity creation can fail when system limits are hit. We
            // silently drop the request — the in-app timer is still the
            // source of truth.
        }
    }

    /// Push a new state snapshot to every active Focus activity.
    static func update(phaseRaw: String, endsAt: Date, isPaused: Bool) {
        guard #available(iOS 16.1, *) else { return }
        let state = FocusActivityAttributes.State(
            endsAt: endsAt,
            phaseRaw: phaseRaw,
            isPaused: isPaused
        )
        Task {
            for activity in Activity<FocusActivityAttributes>.activities {
                if #available(iOS 16.2, *) {
                    await activity.update(ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(60)))
                } else {
                    await activity.update(using: state)
                }
            }
        }
    }

    /// End every active Focus activity. Called when the user cancels.
    static func endAll() async {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<FocusActivityAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}

#else
// Stub the manager on platforms without ActivityKit (macOS) so call sites
// don't need to litter the call path with #if blocks.
import Foundation

@MainActor
enum FocusLiveActivityManager {
    static func start(taskTitle: String, phaseRaw: String, endsAt: Date, isPaused: Bool) {}
    static func update(phaseRaw: String, endsAt: Date, isPaused: Bool) {}
    static func endAll() async {}
}
#endif

// MARK: - Widget Bundle Setup
// To wire the lock-screen / Dynamic Island UI:
//
// 1. Add this file to the RungWidgets target (File Inspector → Target
//    Membership) so the attributes type is visible to the widget bundle.
// 2. Inside RungWidgets, add a Live Activity widget that decodes
//    `FocusActivityAttributes` and renders `Text(timerInterval:)` against
//    `state.endsAt`. Apple's "Update timeline of widgets" sample is the
//    canonical reference.
// 3. Register the widget in the existing `@main` `WidgetBundle` next to
//    the Streak widget.
