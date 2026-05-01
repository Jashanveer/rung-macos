import Foundation

extension SleepInsightsService {
    /// Best-available sleep window for last night. Prefers a HealthKit
    /// snapshot (Apple Watch / phone-motion-via-Health) and falls back
    /// to the cross-device `ForegroundTracker` when HK has no sleep
    /// samples — e.g., the user doesn't wear an Apple Watch but does
    /// use their iPhone, iPad, and Mac across the night/morning.
    ///
    /// Returned bed time is `yesterday`'s last interaction across all
    /// devices; returned wake time is `today`'s earliest. Returns nil
    /// when neither source has enough data.
    @MainActor
    func bestEffortSleepWindow(asOf today: Date = Date()) -> (sleepOnset: Date, wake: Date, source: SleepWindowSource)? {
        if let snap = snapshot, snap.sampleCount > 0 {
            let calendar = Calendar.current
            let wake = calendar.date(
                bySettingHour: snap.medianWakeMinutes / 60,
                minute: snap.medianWakeMinutes % 60,
                second: 0,
                of: today
            ) ?? today

            // Bed time: yesterday evening if median bed minutes >= 12*60 (PM),
            // otherwise the same day (e.g., a 1 AM bed time on a 7 AM wake).
            let bedMinutes = snap.medianBedMinutes
            let bedAnchor = bedMinutes >= 12 * 60
                ? calendar.date(byAdding: .day, value: -1, to: today) ?? today
                : today
            let bed = calendar.date(
                bySettingHour: bedMinutes / 60,
                minute: bedMinutes % 60,
                second: 0,
                of: bedAnchor
            ) ?? bedAnchor
            return (bed, wake, .healthKit)
        }

        if let win = ForegroundTracker.shared.mostRecentSleepWindow(asOf: today) {
            return (win.sleepOnset, win.wake, .crossDevice)
        }

        return nil
    }
}

/// Provenance of a `bestEffortSleepWindow` result. UI can show
/// "Apple Health" vs "Cross-device" so the user knows which signal is
/// in play without surfacing it as an error state.
enum SleepWindowSource {
    case healthKit
    case crossDevice
}
