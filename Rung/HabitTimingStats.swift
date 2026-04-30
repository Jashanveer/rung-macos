import Foundation

/// Per-habit "when do they usually do this and how fast" rollup, computed
/// from `[HabitCompletion]`. Designed to be called once per habit per
/// list rebuild — pass it the slice for that habit (already filtered by
/// `habitLocalId`).
///
/// All fields are `nil` until we have enough samples to be honest. The
/// thresholds are deliberately conservative because a misleading "you
/// usually do this at 3 AM" hint is worse than no hint at all.
struct HabitTimingStats: Equatable {
    /// Median minutes-of-day across recent completions. Requires ≥ 3
    /// samples so a single late-night outlier doesn't dominate.
    var medianMinuteOfDay: Int?
    /// Median duration in seconds across the recent completions that have
    /// `durationSeconds` populated. Requires ≥ 3 duration samples.
    var medianDurationSeconds: Int?
    /// Percent change in median duration: last-7-days vs the 7 days
    /// before that. Negative = faster. `nil` until both buckets each have
    /// ≥ 2 duration samples.
    var speedDeltaPercent: Int?

    /// True when at least one of the surfaceable values is available.
    /// The card uses this to decide whether to render the pill at all.
    var isPresentable: Bool {
        medianMinuteOfDay != nil || medianDurationSeconds != nil || speedDeltaPercent != nil
    }

    static let empty = HabitTimingStats(medianMinuteOfDay: nil, medianDurationSeconds: nil, speedDeltaPercent: nil)
}

enum HabitTimingStatsCalculator {
    /// Compute the rollup from one habit's completion records. Pass an
    /// empty array to get back `.empty`.
    static func compute(from completions: [HabitCompletion], now: Date = Date()) -> HabitTimingStats {
        guard !completions.isEmpty else { return .empty }

        let calendar = Calendar.current
        let recentCutoff = calendar.date(byAdding: .day, value: -28, to: now)
            ?? now.addingTimeInterval(-28 * 86_400)
        let recent = completions.filter { $0.createdAt >= recentCutoff }
        guard !recent.isEmpty else { return .empty }

        // Time-of-day median across all recent completions.
        let medianMinute: Int? = {
            guard recent.count >= 3 else { return nil }
            let minutes = recent.map { date -> Int in
                let components = calendar.dateComponents([.hour, .minute], from: date.createdAt)
                return (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }.sorted()
            return median(minutes)
        }()

        // Duration medians require a separate filter: a check without a
        // captured Focus-Mode session has `durationSeconds == nil` and
        // shouldn't pull the median toward zero.
        let durations = recent.compactMap { $0.durationSeconds }
        let medianDuration: Int? = durations.count >= 3 ? median(durations) : nil

        // Speed trend: split the recent window in half (7-day buckets) and
        // compare medians. We need ≥ 2 in *each* bucket so a single check
        // can't flip the trend either way.
        let speedDelta: Int? = {
            guard !durations.isEmpty else { return nil }
            let last7Cutoff = calendar.date(byAdding: .day, value: -7, to: now)
                ?? now.addingTimeInterval(-7 * 86_400)
            let last7 = recent
                .filter { $0.createdAt >= last7Cutoff }
                .compactMap { $0.durationSeconds }
            let prior7 = recent
                .filter { $0.createdAt < last7Cutoff }
                .compactMap { $0.durationSeconds }
            guard last7.count >= 2, prior7.count >= 2 else { return nil }
            guard let lastMedian = median(last7),
                  let priorMedian = median(prior7),
                  priorMedian > 0 else { return nil }
            // Round to the nearest int; sign of delta matches speed
            // direction (negative = faster, positive = slower).
            let raw = (Double(lastMedian) - Double(priorMedian)) / Double(priorMedian) * 100
            return Int(raw.rounded())
        }()

        return HabitTimingStats(
            medianMinuteOfDay: medianMinute,
            medianDurationSeconds: medianDuration,
            speedDeltaPercent: speedDelta
        )
    }

    /// Group completions by local habit id. Cheap O(n) pass; consumers
    /// call this once per list refresh, then look up each habit's slice.
    static func groupByHabitLocalId(_ completions: [HabitCompletion]) -> [UUID: [HabitCompletion]] {
        Dictionary(grouping: completions, by: { $0.habitLocalId })
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}

extension HabitTimingStats {
    /// "7:42 AM" formatted from `medianMinuteOfDay`.
    var medianTimeOfDayLabel: String? {
        guard let mins = medianMinuteOfDay else { return nil }
        let normalized = ((mins % (24 * 60)) + 24 * 60) % (24 * 60)
        let hour24 = normalized / 60
        let minute = normalized % 60
        let hour12 = ((hour24 + 11) % 12) + 1
        let am = hour24 < 12
        return String(format: "%d:%02d %@", hour12, minute, am ? "AM" : "PM")
    }

    /// "18 min" / "1 h 5 min" formatted from `medianDurationSeconds`.
    var medianDurationLabel: String? {
        guard let secs = medianDurationSeconds, secs > 0 else { return nil }
        let mins = Int((Double(secs) / 60.0).rounded())
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "▼ 12% faster" / "▲ 8% slower" formatted from `speedDeltaPercent`.
    /// Returns nil when the delta is small enough to be noise (≤ 5%) so
    /// the user doesn't get a "1% slower" pill that means nothing.
    var speedDeltaLabel: String? {
        guard let delta = speedDeltaPercent else { return nil }
        if abs(delta) <= 5 { return nil }
        if delta < 0 {
            return "▼ \(-delta)% faster"
        }
        return "▲ \(delta)% slower"
    }
}
