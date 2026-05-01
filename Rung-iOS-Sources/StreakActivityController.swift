import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
#if os(iOS)
import UIKit
#endif

/// Coordinator for the "streak today" Live Activity. Fire-and-forget —
/// all calls are safe if the Widget Extension isn't installed; Activity.request
/// will simply fail and we'll log nothing user-facing.
@MainActor
enum StreakActivityController {
    static func start(
        userName: String,
        doneToday: Int,
        totalToday: Int,
        currentStreak: Int,
        todayKey: String,
        isFrozen: Bool = false
    ) {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Only one activity at a time — keep the running one in sync.
        if let existing = Activity<StreakActivityAttributes>.activities.first {
            update(
                activity: existing,
                doneToday: doneToday,
                totalToday: totalToday,
                currentStreak: currentStreak,
                todayKey: todayKey,
                isFrozen: isFrozen
            )
            return
        }
        let attrs = StreakActivityAttributes(userName: userName)
        let state = StreakActivityAttributes.ContentState(
            doneToday: doneToday,
            totalToday: totalToday,
            currentStreak: currentStreak,
            todayKey: todayKey,
            isFrozen: isFrozen
        )
        do {
            _ = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Widget Extension probably missing — ignore silently.
        }
        #endif
    }

    static func update(
        doneToday: Int,
        totalToday: Int,
        currentStreak: Int,
        todayKey: String,
        isFrozen: Bool = false
    ) {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<StreakActivityAttributes>.activities {
            update(
                activity: activity,
                doneToday: doneToday,
                totalToday: totalToday,
                currentStreak: currentStreak,
                todayKey: todayKey,
                isFrozen: isFrozen
            )
        }
        #endif
    }

    static func end() {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.1, *) else { return }
        Task {
            for activity in Activity<StreakActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    @available(iOS 16.1, *)
    private static func update(
        activity: Activity<StreakActivityAttributes>,
        doneToday: Int,
        totalToday: Int,
        currentStreak: Int,
        todayKey: String,
        isFrozen: Bool
    ) {
        let state = StreakActivityAttributes.ContentState(
            doneToday: doneToday,
            totalToday: totalToday,
            currentStreak: currentStreak,
            todayKey: todayKey,
            isFrozen: isFrozen
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    #endif
}
