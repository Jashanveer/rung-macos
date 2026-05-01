import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-device "last used" tracker — fallback for sleep inference when
/// HealthKit doesn't have an Apple Watch sleep sample. Records the
/// current device's foreground/background timestamps into the App Group
/// `group.jashanveer.Rung` UserDefaults suite, keyed by device class
/// and day. Other devices in the same App Group can read those keys to
/// compute a cross-device sleep window.
///
/// Wire format (App Group UserDefaults keys):
///   interactions.<deviceClass>.<yyyy-MM-dd>.first  -> Double (epoch s)
///   interactions.<deviceClass>.<yyyy-MM-dd>.last   -> Double (epoch s)
/// where deviceClass ∈ {"iPhone", "iPad", "Mac"}.
///
/// Inference: the night ending on `today` ran from
///   max(interactions.*.<yesterday>.last) -> min(interactions.*.<today>.first)
/// across all device classes that have data. Returns nil unless both
/// sides are populated.
@MainActor
final class ForegroundTracker {
    static let shared = ForegroundTracker()

    private static let appGroupSuite = "group.jashanveer.Rung"

    private let dayFormatter: DateFormatter
    private var observers: [NSObjectProtocol] = []

    private init() {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = f
    }

    /// Begin listening for platform lifecycle notifications. Idempotent —
    /// safe to call from `RungApp.init()` on every launch. Also records
    /// the current moment as an "active" tick so a launch with no
    /// subsequent foreground transition still gets a stamp.
    func startListening() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        #if os(iOS)
        let active = UIApplication.didBecomeActiveNotification
        let inactive = UIApplication.didEnterBackgroundNotification
        #elseif os(macOS)
        let active = NSApplication.didBecomeActiveNotification
        let inactive = NSApplication.didResignActiveNotification
        #endif

        observers.append(center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recordActive() }
        })
        observers.append(center.addObserver(forName: inactive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recordResign() }
        })

        recordActive()
    }

    // MARK: - Device class

    /// Stable identifier for the current device's broad class. Two
    /// devices of the same class collapse to one entry (which is fine
    /// for sleep inference — any one waking the user counts).
    private var deviceClass: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #elseif os(macOS)
        return "Mac"
        #else
        return "Unknown"
        #endif
    }

    private var suite: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupSuite)
    }

    private func lastKey(day: String, device: String) -> String {
        "interactions.\(device).\(day).last"
    }
    private func firstKey(day: String, device: String) -> String {
        "interactions.\(device).\(day).first"
    }

    // MARK: - Recording

    /// Record this device as currently active. Updates today's "last"
    /// stamp, and seeds today's "first" stamp if this is the first
    /// active event today.
    func recordActive() {
        let now = Date()
        let day = dayFormatter.string(from: now)
        guard let d = suite else { return }
        d.set(now.timeIntervalSince1970, forKey: lastKey(day: day, device: deviceClass))
        let firstK = firstKey(day: day, device: deviceClass)
        if d.double(forKey: firstK) == 0 {
            d.set(now.timeIntervalSince1970, forKey: firstK)
        }
    }

    /// Record this device as no longer active. Just updates today's
    /// "last" stamp (a resign-active is equivalent to "they put it
    /// down at this moment").
    func recordResign() {
        let now = Date()
        let day = dayFormatter.string(from: now)
        suite?.set(now.timeIntervalSince1970, forKey: lastKey(day: day, device: deviceClass))
    }

    // MARK: - Inference

    /// Inferred sleep window for the night that ended on `today`.
    /// Returns nil when we don't have at least one "last" stamp on
    /// yesterday AND one "first" stamp on today across the known
    /// device classes.
    func inferSleepWindow(today: Date = Date()) -> (sleepOnset: Date, wake: Date)? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return nil
        }
        let yKey = dayFormatter.string(from: yesterday)
        let tKey = dayFormatter.string(from: today)
        guard let d = suite else { return nil }

        let devices = ["iPhone", "iPad", "Mac"]

        var latestLast: TimeInterval = 0
        for dev in devices {
            let v = d.double(forKey: lastKey(day: yKey, device: dev))
            if v > latestLast { latestLast = v }
        }

        var earliestFirst: TimeInterval = .infinity
        for dev in devices {
            let v = d.double(forKey: firstKey(day: tKey, device: dev))
            if v > 0, v < earliestFirst { earliestFirst = v }
        }

        guard latestLast > 0, earliestFirst.isFinite, earliestFirst > latestLast else {
            return nil
        }

        return (Date(timeIntervalSince1970: latestLast),
                Date(timeIntervalSince1970: earliestFirst))
    }

    /// Latest sleep window for which both sides are populated, scanning
    /// back up to `maxDaysBack` days. Useful when the user opens the
    /// app at noon and we want "last night's sleep" rather than
    /// strictly the window ending today.
    func mostRecentSleepWindow(maxDaysBack: Int = 7, asOf: Date = Date()) -> (sleepOnset: Date, wake: Date)? {
        let calendar = Calendar.current
        for offset in 0...maxDaysBack {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: asOf) else { continue }
            if let window = inferSleepWindow(today: day) {
                return window
            }
        }
        return nil
    }
}
