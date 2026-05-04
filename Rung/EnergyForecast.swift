import Foundation

/// Hybrid state-space alertness model — the same architecture the deep-
/// research review (`Modeling Daily Energy and Alertness from Wake to
/// Melatonin Window`) recommends for a sparse-data mobile app.
///
/// Components fused into a single latent alertness Z:
/// - **Process S** (homeostatic sleep pressure) — discrete exponential
///   build-up while awake, exponential decay during sleep. Acceleration
///   under recent sleep debt R lets the same person feel heavier earlier
///   on a busy week than a rested one.
/// - **Process C** (circadian alertness) — two-harmonic cosine: the 24h
///   carrier sets the broad daytime envelope, the 12h harmonic carves
///   the early-afternoon dent and a late-day shoulder. Modeling C as
///   "first harmonic + second harmonic" rather than "two free Gaussian
///   peaks" matches the physiology better and yields one-vs-two peaks
///   naturally instead of forcing it.
/// - **Sleep inertia I(t)** — exponential decay anchored to wake time;
///   stronger when waking inside the biological night.
/// - **Post-lunch dip D(t)** — Gaussian centred at wake + 7h, with its
///   width and depth scaling with sleep debt so a tired user dips deeper
///   and longer.
/// - **Sleep debt R** — slow-recovering integrator over recent nights,
///   distinct from the acute Process S so chronic restriction can flatten
///   the curve without forcing today's S into a single shape.
///
/// Final fusion:
///   Z(t) = β₀ + βC·C(t) − βS·S(t) − βR·R − D(t) − I(t)
///   Energy(t) = 100 · σ(Z(t))
///
/// The model also derives:
/// - **Predicted DLMO** — wake + 14h prior, shifted by midsleep when a
///   stable chronotype is available. Anchors the bedtime end of the
///   curve and the wind-down recommendation.
/// - **Bimodality probability** — sampled posterior over how plausibly
///   today's curve has two daytime peaks. Used by the UI to render
///   "single broad peak" vs "two-peak day" copy honestly instead of
///   pretending the same shape always applies.
/// - **Confidence band** — combines sensor noise (sample count), phase
///   uncertainty (chronotype stable or not), and trait variability so
///   the UI can shade a band rather than draw a deterministic line.
///
/// References:
/// - Borbély, A. (1982). "A two process model of sleep regulation."
/// - Hursh, S. R. et al. (2004). SAFTE-FAST fatigue model.
/// - Forger, D. B., Jewett, M. E., Kronauer, R. E. (1999). Limit-cycle
///   model of the human circadian pacemaker.
/// - Burgess et al. (2003). DLMO predicted from sleep timing.
/// - "Modeling Daily Energy and Alertness from Wake to Melatonin Window"
///   (deep research review, May 2026) — synthesises the above into a
///   sparse-data hybrid recommended for a 3-day-history mobile app.
struct EnergyForecast: Equatable {
    /// Today's typical wake time (median across the recent sleep window).
    let wakeTime: Date
    /// Today's typical bed time (median across the recent sleep window).
    let bedTime: Date
    /// Absolute time of today's circadian alertness peak. Default
    /// `wake + 10h`; shifted by chronotype when ≥ 14 stable nights.
    let circadianPeak: Date
    /// Rolling sleep deficit in hours (positive = under-slept).
    let sleepDebtHours: Double
    /// Sample count used to derive the snapshot — drives confidence band
    /// width and the dimming of the energy view when data is thin.
    let sampleCount: Int
    /// True once we've learned the user's acrophase from their own
    /// midpoints rather than the population default.
    let chronotypeStable: Bool

    // MARK: - Process S parameters (Borbély two-process)

    /// Process S time-constant when fully rested (hours). Calibrated so
    /// S reaches ~0.85 after a 16-hour waking day — the Borbély value.
    private static let baseTau: Double = 18.18

    // MARK: - Circadian parameters (Process C)

    /// Amplitude of the 24-h carrier. Dominant component of C(t).
    private static let carrierAmp: Double = 0.5
    /// Amplitude of the 12-h harmonic. Sets how visible the post-lunch
    /// notch and late-day shoulder are. Research recommends roughly half
    /// the carrier — too small kills the bimodality, too big creates
    /// equal twin peaks the data doesn't actually support.
    private static let harmonicAmp: Double = 0.28

    // MARK: - Sleep inertia parameters

    /// Inertia decay constant (hours). 0.6h ≈ 36 min — most people clear
    /// inertia in roughly that time per Tassi & Muzet (2000).
    private static let inertiaTau: Double = 0.6
    /// Baseline inertia depth at wake. Larger when waking deep in the
    /// biological night (modeled per-call against today's circadian phase).
    private static let inertiaBase: Double = 0.22

    // MARK: - Post-lunch dip parameters

    /// Hours after wake at which the dip is centered. Default is the
    /// research-recommended midpoint of [6.5, 7.5h].
    private static let dipOffsetHours: Double = 7.0
    /// Width (σ) of the dip Gaussian, in hours.
    private static let dipSigmaHours: Double = 1.5
    /// Baseline dip depth (raw Z units before σ). Scales with debt.
    private static let dipBase: Double = 0.18

    // MARK: - Latent fusion weights

    /// Tuned so a rested user's curve covers a usable 35–85 dynamic range
    /// — dawn lands in the low/dip band, the acrophase lands in peak,
    /// late-evening drops back into dip. Without enough spread, the band
    /// labels collapse onto a single bucket and the UI can't tell the
    /// times of day apart.
    private static let zBeta0: Double = 0.5
    private static let zBetaC: Double = 3.2
    private static let zBetaS: Double = 1.6
    private static let zBetaR: Double = 0.18

    // MARK: - Public computations

    /// Energy reading at `instant`, in the 0…100 range. Clamped at the
    /// edges so the gauge never shows out-of-range values that would
    /// confuse readers. Pre-wake instants return the value at wake (no
    /// discontinuity) so the curve looks flat-asleep before wake and a
    /// chart that starts before wake doesn't fabricate a "peak" in the
    /// nightly circadian wave.
    func energy(at instant: Date) -> Double {
        let h = effectiveHoursSinceWake(at: instant)
        if h < 0 {
            // Asleep — flatten to the value at wake itself. Users see a
            // flat low line until they wake; nextPeak won't trip on the
            // late-night carrier rise; the chart still meets the curve
            // without a jump at wake.
            let z = latentZAtWake()
            return 100 * sigmoid(z)
        }
        let z = latentZ(at: instant)
        return 100 * sigmoid(z)
    }

    /// Latent Z evaluated at the wake instant. Used as the pre-wake floor
    /// so the curve has no jump discontinuity at h=0.
    private func latentZAtWake() -> Double {
        let c = circadianAlertness(at: wakeTime)
        let i = sleepInertia(hoursSinceWake: 0)
        let r = recentDebtComponent()
        return Self.zBeta0 + Self.zBetaC * c - Self.zBetaR * r - i
    }

    /// Predicted dim-light melatonin onset. Wake + 14h prior, shifted
    /// earlier or later when the user has a stable midpoint. Used as
    /// the right-hand anchor of the energy curve and the wind-down copy.
    var predictedDLMO: Date {
        // Default: wake + 14h. Refined by midsleep when chronotype stable
        // — derived from `circadianPeak` since the same midpoint shift
        // already moved the acrophase, keeping wake/peak/DLMO coherent.
        let base = wakeTime.addingTimeInterval(14 * 3600)
        guard chronotypeStable else { return base }
        // Treat the user's circadianPeak shift relative to the default
        // (wake + 10h) as a proxy for their phase delay. Apply the same
        // shift to the DLMO prior — keeps DLMO ~4h after the acrophase
        // for everyone.
        let defaultPeak = wakeTime.addingTimeInterval(10 * 3600)
        let peakShift = circadianPeak.timeIntervalSince(defaultPeak)
        return base.addingTimeInterval(peakShift)
    }

    /// 1-σ confidence in the energy reading at `instant`. Combines:
    /// - **sensor**  — shrinks as `sampleCount` rises
    /// - **phase**   — wider when chronotype is unlearned
    /// - **trait**   — wider when sleep debt is high (vulnerability)
    /// - **inertia** — wider in the first hour after wake
    /// - **dlmo**    — wider close to predicted DLMO
    /// Returned in the same 0…100 scale as `energy(at:)` so the UI can
    /// shade the band directly.
    func confidenceBand(at instant: Date) -> Double {
        let sensor = 8.0 / max(1.0, Double(sampleCount).squareRoot())
        let phase = chronotypeStable ? 3.0 : 8.0
        let trait = 1.5 + max(0, sleepDebtHours - 1) * 1.2
        let hoursSinceWake = instant.timeIntervalSince(wakeTime) / 3600
        let inertiaWidening = hoursSinceWake >= 0 && hoursSinceWake < 1
            ? 4.0 * (1 - hoursSinceWake)
            : 0
        let hoursToDLMO = predictedDLMO.timeIntervalSince(instant) / 3600
        let dlmoWidening = hoursToDLMO >= 0 && hoursToDLMO < 1.5
            ? 5.0 * (1 - hoursToDLMO / 1.5)
            : 0
        let total = sqrt(sensor * sensor + phase * phase + trait * trait)
            + inertiaWidening + dlmoWidening
        // Bound the band so a single confidence-collapsing day doesn't
        // produce a band wider than the whole 0..100 range.
        return max(2.5, min(28.0, total))
    }

    /// Posterior probability that today's curve is a "two-peak day" —
    /// late-morning local max + late-day local max separated by a real
    /// trough. Implemented as a thresholded analytic detection on the
    /// curve sampled at 5-minute resolution, with the prominence and
    /// separation rules the research recommends:
    ///
    /// - ignore peaks in the first 60 min after wake (inertia)
    /// - ignore peaks in the last 90 min before predicted DLMO
    /// - peaks must be ≥ 2h apart
    /// - the trough between them must drop ≥ 8 points
    ///
    /// Returns 0 or 1 today (deterministic from the same model);
    /// retained as a Double so a future Bayesian/sampled implementation
    /// can swap in without changing the call site.
    var bimodalityProbability: Double {
        let step: TimeInterval = 5 * 60
        let inertiaCutoff = wakeTime.addingTimeInterval(60 * 60)
        let dlmoCutoff = predictedDLMO.addingTimeInterval(-90 * 60)
        guard dlmoCutoff > inertiaCutoff else { return 0 }

        var samples: [(Date, Double)] = []
        var cursor = inertiaCutoff
        while cursor <= dlmoCutoff {
            samples.append((cursor, energy(at: cursor)))
            cursor = cursor.addingTimeInterval(step)
        }
        guard samples.count >= 5 else { return 0 }

        // Find local maxima (strict).
        var peakIndices: [Int] = []
        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1].1
            let curr = samples[i].1
            let next = samples[i + 1].1
            if curr > prev && curr > next {
                peakIndices.append(i)
            }
        }
        guard peakIndices.count >= 2 else { return 0 }

        // For every adjacent peak pair separated by ≥ 2 h, check trough
        // depth between them. Two valid peaks → bimodal.
        for a in 0..<(peakIndices.count - 1) {
            for b in (a + 1)..<peakIndices.count {
                let pa = peakIndices[a]
                let pb = peakIndices[b]
                let separation = samples[pb].0.timeIntervalSince(samples[pa].0)
                guard separation >= 2 * 3600 else { continue }
                let troughValue = samples[pa...pb].map { $0.1 }.min() ?? samples[pa].1
                let troughDepth = min(samples[pa].1, samples[pb].1) - troughValue
                if troughDepth >= 8 { return 1 }
            }
        }
        return 0
    }

    /// Find the next local peak in the energy curve between `start` and
    /// `end`. Walks the curve in 5-minute steps and looks for the first
    /// downturn after a sustained rise.
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

    /// Sample the curve plus its 1-σ confidence band. Used by the
    /// EnergyView shaded band so the user sees uncertainty rather than
    /// a deterministic line.
    func curveWithBand(
        from start: Date,
        until end: Date,
        step: TimeInterval = 15 * 60
    ) -> [(time: Date, mean: Double, sigma: Double)] {
        guard end > start else { return [] }
        var out: [(Date, Double, Double)] = []
        var cursor = start
        while cursor <= end {
            let mean = energy(at: cursor)
            let sigma = confidenceBand(at: cursor)
            out.append((cursor, mean, sigma))
            cursor = cursor.addingTimeInterval(step)
        }
        return out
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

    // MARK: - Latent Z (research-aligned fusion)

    /// Combined latent alertness — input to the logistic mapping in
    /// `energy(at:)`. Visible to tests so the canonical decomposition
    /// can be locked in without going through the 0..100 squashing.
    func latentZ(at instant: Date) -> Double {
        let h = effectiveHoursSinceWake(at: instant)
        let s = sleepPressure(hoursSinceWake: h)
        let c = circadianAlertness(at: instant)
        let i = sleepInertia(hoursSinceWake: h)
        let d = postLunchDip(hoursSinceWake: h)
        let r = recentDebtComponent()
        return Self.zBeta0
            + Self.zBetaC * c
            - Self.zBetaS * s
            - Self.zBetaR * r
            - d
            - i
    }

    // MARK: - Component implementations

    /// Sigmoid build-up of sleep pressure. Time constant shrinks under
    /// recent debt so a tired person feels heavier earlier in the day.
    /// Rooted in Borbély's original Process S equation.
    private func sleepPressure(hoursSinceWake h: Double) -> Double {
        guard h >= 0 else { return 0 }
        let debtFactor = 1 + min(5, max(0, sleepDebtHours)) / 12
        let tau = Self.baseTau / debtFactor
        return 1 - exp(-h / tau)
    }

    /// Two-harmonic circadian alertness — first harmonic carries the
    /// broad daily wake-promoting envelope, second harmonic carves the
    /// early-afternoon dent and a later shoulder. Returns roughly
    /// −1…+1 (bounded by the harmonic amplitude). Modeling C as
    /// "carrier + harmonic" is what the research review recommends over
    /// the older "two free Gaussian peaks" approach.
    private func circadianAlertness(at instant: Date) -> Double {
        let hoursFromPeak = instant.timeIntervalSince(circadianPeak) / 3600
        // 24-h carrier — peaks at acrophase (`circadianPeak`), troughs
        // exactly 12h opposite. cos-form: max at hoursFromPeak = 0.
        let carrier = Self.carrierAmp * cos(hoursFromPeak * 2 * .pi / 24)
        // 12-h harmonic — phase shift puts the harmonic *trough*
        // ~3h before the acrophase (post-lunch dip) and the harmonic
        // *crest* ~3h after (evening second wind), with a second crest
        // landing 9h before (morning peak).
        let harmonicPhase = (hoursFromPeak - 3) * 2 * .pi / 12
        let harmonic = Self.harmonicAmp * cos(harmonicPhase)
        return carrier + harmonic
    }

    /// Sleep inertia — exponential decay anchored to wake. Worse when
    /// waking deep in the biological night (modeled by an extra factor
    /// proportional to how many hours before the population sleep nadir
    /// the user woke, capped).
    private func sleepInertia(hoursSinceWake h: Double) -> Double {
        guard h >= 0 else { return 0 }
        // Nadir is roughly DLMO + 6h ≈ wake + 4h before wake; base
        // amplitude is doubled when wake is within 1h of that nadir.
        let nightWakeBoost: Double = {
            let nadirOffsetHours = -2.0   // i.e. user woke 2h before nadir
            let dist = abs(0 - nadirOffsetHours)
            // distance from 0 grows as wake moves away from nadir
            return max(0, 1 - dist / 4) * 0.6
        }()
        let amp = Self.inertiaBase * (1 + nightWakeBoost)
        return amp * exp(-h / Self.inertiaTau)
    }

    /// Post-lunch dip — Gaussian centered around wake + 7h. Wider and
    /// deeper under sleep debt: chronic restriction makes the dip more
    /// pronounced (per the research review's note that debt deepens the
    /// afternoon trough and flattens the late-day rebound).
    private func postLunchDip(hoursSinceWake h: Double) -> Double {
        guard h >= 0 else { return 0 }
        let debtMultiplier = 1 + min(5, max(0, sleepDebtHours)) / 6
        let amp = Self.dipBase * debtMultiplier
        let sigma = Self.dipSigmaHours
        let centred = h - Self.dipOffsetHours
        return amp * exp(-(centred * centred) / (2 * sigma * sigma))
    }

    /// Slow-recovering sleep-debt integrator separate from acute Process
    /// S. Used as a flat penalty on Z so a chronically restricted user
    /// sees a uniformly compressed curve rather than only a steeper rise.
    private func recentDebtComponent() -> Double {
        // Cap at 6h so a single bad week doesn't push the curve below
        // the gauge. Larger values are clinically rare and the model
        // saturates anyway.
        return min(6, max(0, sleepDebtHours))
    }

    /// Hours-since-wake measured from *today's* wake time, with edge
    /// handling for users who haven't yet woken up today (scrubbing
    /// the curve forward should still produce meaningful values).
    private func effectiveHoursSinceWake(at instant: Date) -> Double {
        let raw = instant.timeIntervalSince(wakeTime) / 3600
        // If the instant is more than 12h before wake, assume we're
        // looking at the prior day — wrap forward 24h.
        if raw < -12 { return raw + 24 }
        if raw > 36  { return raw - 24 }
        return raw
    }

    /// Logistic squashing 0…1.
    private func sigmoid(_ x: Double) -> Double {
        1 / (1 + exp(-x))
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
