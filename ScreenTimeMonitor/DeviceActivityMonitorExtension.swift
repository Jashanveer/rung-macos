//
//  DeviceActivityMonitorExtension.swift
//  ScreenTimeMonitor
//
//  Daily monitor for the user's nominated "social" apps. The extension
//  runs in a separate process invoked by the OS — it cannot reach into
//  the main app's memory or SwiftData store. The only communication
//  channel is the shared App Group `UserDefaults` suite.
//
//  Contract with the main app (see `ScreenTimeService.swift`):
//    - App Group ID:           "group.jashanveer.Rung"
//    - Activity name:          "rung.social"
//    - Event name:             "rung.social.overLimit"
//    - Per-day overLimit key:  "screenTime.YYYY-MM-DD.overLimit"
//
//  Keep the four strings above in sync with `ScreenTimeService` — they're
//  the only wire format between the two processes.

import DeviceActivity
import Foundation

private let kAppGroupID = "group.jashanveer.Rung"

/// `DateFormatter` is moderately expensive to construct, and the extension
/// can be invoked rapidly across interval/event callbacks. Build once.
private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    /// Shared `UserDefaults` suite that bridges this process and the main
    /// app. Force-unwrapping is safe: the App Group entitlement is wired
    /// into both targets so the suite is guaranteed to exist.
    private var shared: UserDefaults? { UserDefaults(suiteName: kAppGroupID) }

    private func todayKey() -> String {
        dayFormatter.string(from: Date())
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Day rollover — clear yesterday's lingering overLimit flag so the
        // first verification on the new day starts from a clean slate.
        // (We rely on per-day keys, but resetting here keeps the suite
        // tidy and avoids unbounded growth.)
        let key = todayKey()
        shared?.removeObject(forKey: "screenTime.\(key).overLimit")
        shared?.set(Date(), forKey: "screenTime.\(key).intervalStartedAt")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let key = todayKey()
        shared?.set(Date(), forKey: "screenTime.\(key).intervalEndedAt")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        // The user crossed the social-media minutes threshold for the day.
        // From this point on, any `.screenTimeSocial` verification for the
        // current day must fall back to `.selfReport` — they can't
        // honestly claim to have limited their use.
        let key = todayKey()
        shared?.set(true, forKey: "screenTime.\(key).overLimit")
        shared?.set(Date(), forKey: "screenTime.\(key).overLimitAt")
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
    }
}
