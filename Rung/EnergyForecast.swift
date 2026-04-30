import Foundation

/// Borbély two-process model of human alertness.
///
/// The model says wake propensity at any moment is the difference between:
/// - **Process S** (homeostatic sleep pressure) — builds while you're awake,
///   decays while you sleep. Drawn as a sigmoid that approaches saturation
///   the longer you've been up.
/// - **Process C** (circadian alertness) — internal body-clock signal, a
///   24-hour cosine that peaks ~10 hours after wake-up and troughs around
///   the bottom of the night.
///
/// Energy ≈ C(t) − S(t), normalised into a 0…100 range so callers can
/// render it as a percentage. Sleep debt accelerates Process S, which is
/// why the same person feels worse during a busy week than a rested one.
///
/// References:
/// - Borbély, A. (1982). "A two process model of sleep regulation."
///   Human Neurobiology, 1, 195–204.
/// - Achermann, P. (2004). "The two-process model of sleep regulation
///   revisited." Aviation, Space, and Environmental Medicine, 75(3).
///
/// **What we deliberately don't model**: caffeine, naps, jet lag, HRV.
/// Adding any of those would meaningfully improve accuracy but each one
/// requires user input or a second data signal — Path C work, not this one.
struct EnergyForecast: Equatable {
    /// Today's typical wake time (median across the recent sleep window).
    let wakeTime: Date
    /// Today's typical bed time (median across the recent sleep window).
    let bedTime: Date
    /// Absolute time of today's circadian alertness peak. The factory in
    /// `SleepInsightsService.makeForecast` chooses between two modes:
    /// - **Default** (cold-start): `wakeTime + 10h` — the canonical
    ///   "afternoon peak" assumption for an average chronotype.
    /// - **Chronotype-tuned** (≥ 14 stable nights of HK data): shift the
    ///   default by the user's lark/owl tendency, derived from the
    ///   variance of recent sleep midpoints.
    let circadianPeak: Date
    /// Rolling sleep deficit in hours (positive = under-slept). Caps the
    /// faster-build-up effect at 5h to avoid a runaway curve.
    let sleepDebtHours: Double
    /// Sample count used to derive the snapshot — exposed so the UI can
    /// dim itself when there isn't enough data to be honest.
    let sampleCount: Int
    /// True once we've learned the user's acrophase from their own
    /// midpoints rather than the population default. Drives the
    /// "Learned chronotype" badge in EnergyView.
    let chronotypeStable: Bool

    /// Process S time-constant when fully rested. Rises faster under debt.
    private static let baseTau: Double = 18.18

    // MARK: - Public computations

    /// Energy reading at `instant`, in the 0…100 range. Clamped at the
    /// edges so the gauge never shows negative-energy or 110%-energy
    /// values that would confuse readers.
    func energy(at instant: Date) -> Double {
        let h = effectiveHoursSinceWake(at: instant)
        let s = sleepPressure(hoursSinceWake: h)
        let c = circadianAlertness(hoursSinceWake: h)
        // Wake propensity = C − S, raw range roughly [-1, 1]. Map to 0..100.
        let raw = c - s
        let scaled = ((raw + 1) / 2) * 100
        return max(0, min(100, scaled))
    }

    /// Find the next local peak in the energy curve between `start` and
    /// `end`. Walks the curve in 5-minute steps and looks for the first
    /// downturn after a sustained rise. Nil when the curve only descends
    /// in the window (e.g. you're already past today's peak).
    func nextPeak(after start: Date, until end: Date) -> Date? {
        nextExtremum(after: start, until: end, isPeak: true)
    }

    /// Symmetric counterpart to `nextPeak`. Used to warn users about an
    /// incoming dip ("low energy in 2h — schedule something easy").
    func nextDip(after start: Date, until end: Date) -> Date? {
        nextExtremum(after: start, until: end, isPeak: false)
    }

    /// Sample the curve every `step` between `start` and `end`. The Path B
    /// chart consumes this directly; downsampling at the call site keeps
    /// us from materialising the whole array unnecessarily.
    func curve(
        from start: Date,
        until end: Date,
        step: TimeInterval = 15 * 60
    ) -> [(Date, Double)] {
        guard end > start else { return [] }
        var samples: [(Date, Double)] = []
        var cursor = start
        while cursor <= end {
            samples.append((cursor, energy(at: cursor)))
            cursor = cursor.addingTimeInterval(step)
        }
        return samples
    }

    /// Coarse label corresponding to a 0…100 score. Lets the chip render
    /// "78 · Peak" without the caller knowing the bucket boundaries.
    static func label(for energy: Double) -> EnergyBand {
        switch energy {
        case ..<25:  return .low
        case ..<50:  return .dip
        case ..<75:  return .moderate
        default:     return .peak
        }
    }

    // MARK: - Process implementations

    /// Sigmoid build-up of sleep pressure. Time constant shrinks under
    /// debt so a tired person feels heavier earlier in the day.
    private func sleepPressure(hoursSinceWake h: Double) -> Double {
        guard h >= 0 else { return 0 }
        let debtFactor = 1 + min(5, max(0, sleepDebtHours)) / 12
        let tau = Self.baseTau / debtFactor
        return 1 - exp(-h / tau)
    }

    /// 24-hour cosine wave centred on `circadianPeak`. Returns 0…1 —
    /// peak at the acrophase, trough exactly 12h offset. We compute the
    /// phase from the absolute peak time rather than a wake-relative
    /// offset because the chronotype-tuned forecast may have shifted
    /// the peak independently of when the user actually woke up today.
    private func circadianAlertness(hoursSinceWake h: Double) -> Double {
        let instant = wakeTime.addingTimeInterval(h * 3600)
        let hoursFromPeak = instant.timeIntervalSince(circadianPeak) / 3600
        let phase = hoursFromPeak * 2 * .pi / 24
        return 0.5 + 0.5 * cos(phase)
    }

    /// Hours-since-wake measured from *today's* wake time, with edge
    /// handling for users who haven't yet woken up today (scrubbing
    /// the curve forward should still produce meaningful values).
    private func effectiveHoursSinceWake(at instant: Date) -> Double {
        let raw = instant.timeIntervalSince(wakeTime) / 3600
        // If the instant is more than 12h before wake, assume we're
        // looking at the prior day — wrap forward 24h. Mostly defensive;
        // chart consumers always pass instants on the same day.
        if raw < -12 { return raw + 24 }
        if raw > 36  { return raw - 24 }
        return raw
    }

    /// Shared implementation for next-peak and next-dip. Walks 5-minute
    /// steps and detects the first sign change of the slope.
    private func nextExtremum(after start: Date, until end: Date, isPeak: Bool) -> Date? {
        guard end > start else { return nil }
        let step: TimeInterval = 5 * 60
        var prev = energy(at: start)
        var risingPhase: Bool? = nil
        var cursor = start.addingTimeInterval(step)
        while cursor <= end {
            let now = energy(at: cursor)
            let rising = now > prev
            if let phase = risingPhase {
                // Peak: was rising, now falling. Dip: was falling, now rising.
                if isPeak && phase && !rising { return cursor.addingTimeInterval(-step) }
                if !isPeak && !phase && rising { return cursor.addingTimeInterval(-step) }
            }
            risingPhase = rising
            prev = now
            cursor = cursor.addingTimeInterval(step)
        }
        return nil
    }
}

/// Coarse alertness bucket. Rendered as a coloured pill so users get
/// "where am I right now" at a glance without reading numbers.
enum EnergyBand: Equatable {
    case low       // < 25 — running on fumes
    case dip       // 25-50 — afternoon slump territory
    case moderate  // 50-75 — getting things done
    case peak      // 75+ — best window for hard work

    var label: String {
        switch self {
        case .low:      return "Low"
        case .dip:      return "Dip"
        case .moderate: return "Steady"
        case .peak:     return "Peak"
        }
    }

    var systemImage: String {
        switch self {
        case .low:      return "battery.25"
        case .dip:      return "battery.50"
        case .moderate: return "bolt"
        case .peak:     return "bolt.fill"
        }
    }
}
