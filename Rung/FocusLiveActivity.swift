#if os(iOS)
import ActivityKit
import Foundation

// `FocusActivityAttributes` lives in `RungShared/` so both the main app
// target and the widget bundle compile against the same definition.

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

// Widget bundle UI (lock-screen + Dynamic Island) lives in
// `RungWidgets/FocusLiveActivityWidget.swift` and is registered in
// `RungWidgetsBundle.swift`.
