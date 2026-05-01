#if os(iOS)
import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings

/// iOS-only bridge to Family Controls + DeviceActivity for Screen Time
/// verification. Owns three things: the user's nominated set of "social"
/// apps, the per-day monitoring schedule that tallies their usage, and
/// the read-back path that lets `VerificationService` ask "did the user
/// exceed the limit on `dayKey`?".
///
/// Cross-process state lives in the shared App Group `UserDefaults`. The
/// `DeviceActivityMonitorExtension` (separate process, separate target)
/// writes events into the same suite and we read them here. Keep the
/// constants below in sync with the ones in the extension — they're the
/// only contract between the two processes.
@MainActor
final class ScreenTimeService {
    static let shared = ScreenTimeService()

    // The constants below are declared `nonisolated` so they're usable
    // from default-argument expressions on `startDailySocialMonitor`
    // (Swift 6 strict-concurrency requires this; without it the compiler
    // can't prove the value is captured outside the main actor).

    /// App Group identifier shared with the extension. Must match
    /// `Rung.entitlements`, `ScreenTimeMonitor.entitlements`, and the
    /// constant of the same name inside `DeviceActivityMonitorExtension`.
    nonisolated static let appGroupID = "group.jashanveer.Rung"

    /// DeviceActivity schedule + event names. Same string on both sides.
    nonisolated static let socialActivityName = DeviceActivityName("rung.social")
    nonisolated static let socialEventName = DeviceActivityEvent.Name("rung.social.overLimit")

    /// Default daily threshold for `.screenTimeSocial` habits, matching
    /// the canonical seed's `param: 60`. Per-habit overrides can be wired
    /// later by reading `Habit.verificationParam` at start time.
    nonisolated static let defaultThresholdMinutes = 60

    /// Mirrors `AuthorizationCenter.shared.authorizationStatus` on the main
    /// actor. Observed by UI to decide whether to re-surface the permission
    /// prompt at onboarding or hide it entirely.
    private(set) var isAuthorized: Bool = {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }()

    /// True once `startDailySocialMonitor` has successfully scheduled the
    /// monitor for the current selection. Persisted across launches so a
    /// cold start doesn't think monitoring is off.
    private(set) var isMonitoring: Bool = {
        UserDefaults.standard.bool(forKey: Keys.monitoringActive)
    }()

    private enum Keys {
        static let selection = "screenTime.selection"
        static let monitoringActive = "screenTime.monitoring.active"
        static let monitoringThresholdMinutes = "screenTime.monitoring.thresholdMinutes"
        /// Per-day overLimit flag written by the extension. Format:
        /// `screenTime.YYYY-MM-DD.overLimit`. We key by day so a Tuesday
        /// blowout doesn't poison Wednesday's verification.
        static func overLimit(dayKey: String) -> String {
            "screenTime.\(dayKey).overLimit"
        }
    }

    private init() {}

    // MARK: - Authorization

    /// Requests individual (self-managed) Family Controls authorization.
    /// Silent on failure — the caller's UI already shows "Not enabled" when
    /// `isAuthorized` stays false, so a thrown error never blocks onboarding.
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Selection persistence

    /// The user's nominated set of "social" applications and categories.
    /// Empty when the user hasn't picked yet — the picker sheet must run
    /// before monitoring can usefully start.
    func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: Keys.selection),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    /// Persists a new selection and immediately (re)starts the monitor so
    /// the user's choice takes effect on the current day's schedule.
    /// Re-entrant — calling with an empty selection stops monitoring and
    /// clears the persisted state.
    func storeSelection(_ selection: FamilyActivitySelection, thresholdMinutes: Int? = nil) {
        if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.selection)
            stopMonitoring()
            return
        }
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: Keys.selection)
        }
        startDailySocialMonitor(thresholdMinutes: thresholdMinutes ?? Self.defaultThresholdMinutes)
    }

    // MARK: - Monitoring lifecycle

    /// Schedules the daily social-media usage monitor against the persisted
    /// selection. Idempotent — calling again replaces the active schedule
    /// with the new threshold, which is what we want when the user nudges
    /// `Habit.verificationParam` later.
    func startDailySocialMonitor(thresholdMinutes: Int = ScreenTimeService.defaultThresholdMinutes) {
        guard isAuthorized else { return }
        let selection = loadSelection()
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            // Nothing to monitor — abort silently. The picker sheet will
            // call back into us once the user nominates apps.
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            threshold: DateComponents(minute: thresholdMinutes)
        )

        do {
            let center = DeviceActivityCenter()
            // Stop any prior schedule first; otherwise startMonitoring throws
            // .duplicateActivityName when a previous run is still active.
            center.stopMonitoring([Self.socialActivityName])
            try center.startMonitoring(
                Self.socialActivityName,
                during: schedule,
                events: [Self.socialEventName: event]
            )
            isMonitoring = true
            UserDefaults.standard.set(true, forKey: Keys.monitoringActive)
            UserDefaults.standard.set(thresholdMinutes, forKey: Keys.monitoringThresholdMinutes)
        } catch {
            isMonitoring = false
            UserDefaults.standard.set(false, forKey: Keys.monitoringActive)
        }
    }

    /// Tears down the schedule. Safe to call when the user removes their
    /// last `.screenTimeSocial` habit; subsequent verification calls will
    /// fall back to self-report because `wasOverLimit` returns false but
    /// `isMonitoring` is also false.
    func stopMonitoring() {
        DeviceActivityCenter().stopMonitoring([Self.socialActivityName])
        isMonitoring = false
        UserDefaults.standard.set(false, forKey: Keys.monitoringActive)
    }

    // MARK: - Read-back

    /// True if the extension reported the user crossed the social-media
    /// threshold on `dayKey`. Used by `VerificationService` to decide
    /// whether to award `.auto` (stayed under) or fall back to
    /// `.selfReport` (exceeded — can't honestly verify abstinence).
    func wasOverLimit(on dayKey: String) -> Bool {
        guard let shared = UserDefaults(suiteName: Self.appGroupID) else { return false }
        return shared.bool(forKey: Keys.overLimit(dayKey: dayKey))
    }
}
#endif
