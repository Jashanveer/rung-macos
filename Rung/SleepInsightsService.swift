import Combine
import Foundation
import HealthKit
import SwiftUI

/// Reads recent sleep samples from HealthKit and produces "best time" hints
/// for new habits. Designed for the cold-start case — we never recommend
/// based on fewer than 3 nights of data.
///
/// Energy-window heuristic (proxy for chronotype, not a clinical model):
/// - **Peak**: 1.5-3h after typical wake — most people are sharpest then.
/// - **Dip**: ~6-8h after wake — post-lunch slump.
/// - **Second wind**: ~10-11h after wake — short pre-dinner peak.
///
/// Habits are matched to a window by intent:
/// - Workouts / movement / study / focus → peak.
/// - Reading / meditation / journaling / gratitude → second wind.
/// - Hydration / vitamin / med-style upkeep → first thing after waking.
@MainActor
final class SleepInsightsService: ObservableObject {
    static let shared = SleepInsightsService()

    /// Most recent computed snapshot. Nil until `refresh()` succeeds at
    /// least once with sufficient data.
    @Published private(set) var snapshot: SleepSnapshot?

    /// Two-process energy forecast for today, derived from the snapshot's
    /// wake/bed times and the rolling sleep debt. Refreshed alongside
    /// `snapshot` — nil while we don't have enough data.
    @Published private(set) var forecast: EnergyForecast?

    /// True while a refresh is in flight. Lets the UI dim/disable
    /// suggestion chips so the user doesn't see them flicker.
    @Published private(set) var isRefreshing = false

    /// Server timestamp on the snapshot we last pulled from the backend.
    /// Nil on iOS (where the snapshot is computed locally) and on macOS
    /// before the first fetch. macOS uses this to dim the readout when
    /// the iPhone hasn't synced lately.
    @Published private(set) var snapshotUpdatedAt: Date?

    /// Number of distinct sleep nights returned by the most recent HK
    /// query, regardless of whether they cleared the 3-night minimum
    /// needed to build a snapshot. `nil` = HealthKit unavailable, the
    /// query failed, or refresh hasn't run yet. Empty-state UIs read
    /// this to tell "no access / no tracked sleep" (nil or 0) apart
    /// from "granted but not enough nights yet" (1-2).
    @Published private(set) var lastSleepNightCount: Int?

    /// Backend store reference, lazily set by the app delegate / scene
    /// once the user is authenticated. Without it, refresh runs in
    /// local-only mode (HK on iOS, no-op on macOS).
    private weak var backend: HabitBackendStore?

    private let store = HKHealthStore()

    /// Hours of sleep we treat as "fully rested" for the purpose of
    /// computing debt. Tunable; 8h is the population mean for adults.
    private static let idealSleepHoursPerNight: Double = 8.0

    /// Minimum nights of sleep data before we trust the user's own
    /// midpoint variance enough to tune their acrophase. Below this we
    /// fall back to the wake-anchored default (`wake + 10h`).
    private static let chronotypeMinNights: Int = 14

    /// Largest interquartile range (in minutes) we'll accept on the
    /// midpoint before declaring the chronotype "unstable" and reverting
    /// to the default. 90 min = ±45 around the median: roughly the
    /// natural variance of an adult who keeps a consistent schedule.
    private static let chronotypeMaxIQRMinutes: Int = 90

    /// Population-mean midpoint of sleep, used as the reference point
    /// for the lark/owl shift. ~04:00 is the canonical value across
    /// chronotype questionnaires (MEQ, MCTQ).
    private static let populationMidpointMinutes: Int = 4 * 60

    private init() {}

    /// Wire the backend store after sign-in so iOS can upload its
    /// snapshot and macOS can fetch a remote one. Safe to call multiple
    /// times — only the most recent reference is kept.
    func bind(backend: HabitBackendStore) {
        self.backend = backend
    }

    /// Pull the last `nights` nights of sleep samples and recompute the
    /// snapshot. Behaviour by platform:
    /// - **iOS**: queries HealthKit, computes locally, uploads to backend
    ///   so other devices can read it.
    /// - **macOS**: HealthKit isn't available on native Mac apps, so the
    ///   service skips straight to fetching the iPhone-uploaded snapshot
    ///   from the backend.
    func refresh(nights: Int = 14) async {
        #if os(macOS)
        // Native macOS apps can't read HealthKit. Skip the local query
        // entirely and lean on whatever the iPhone uploaded.
        await refreshFromBackend()
        return
        #else
        await refreshFromHealthKit(nights: nights)
        #endif
    }

    #if !os(macOS)
    /// HealthKit-driven refresh path. iOS-only because native macOS apps
    /// can't read HK. After computing locally, pushes the snapshot to
    /// the backend so the Mac client can read what we just computed.
    private func refreshFromHealthKit(nights: Int) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            // HK isn't available on this device — try the backend
            // fallback so the user still sees something.
            lastSleepNightCount = nil
            await refreshFromBackend()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -nights, to: end) ?? end.addingTimeInterval(-Double(nights) * 86_400)

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample]
        do {
            samples = try await fetchSleepSamples(type: sleepType, predicate: predicate)
        } catch {
            // Don't claim "0 nights" when the query itself failed — leave
            // the count nil so the empty-state UI can tell auth/data
            // problems apart from "we genuinely saw zero samples".
            lastSleepNightCount = nil
            return
        }

        let nightlySamples = bucketByNight(samples: samples)
        lastSleepNightCount = nightlySamples.count
        guard nightlySamples.count >= 3 else {
            // Not enough data — leave the prior snapshot in place so the
            // UI doesn't flap between "we have a suggestion" and "we don't".
            return
        }

        let wakeTimes = nightlySamples.compactMap { $0.wake }
        let bedTimes = nightlySamples.compactMap { $0.bed }

        guard let medianWake = medianMinutesOfDay(wakeTimes),
              let medianBed = medianMinutesOfDay(bedTimes) else {
            return
        }

        let avgDuration = nightlySamples.compactMap { $0.duration }
            .reduce(0, +) / Double(max(1, nightlySamples.count))

        // Sleep debt = sum of (ideal − actual) over the rolling window,
        // floored at zero per night so a string of 9-hour nights doesn't
        // bank credit (real Process S models reset, not accumulate).
        let nightlyDebt = nightlySamples.map { night -> Double in
            max(0, Self.idealSleepHoursPerNight - night.duration / 3600)
        }
        let totalDebt = nightlyDebt.reduce(0, +)

        // Sleep midpoint stats — used for chronotype detection. Midpoint
        // is computed per-night from the actual asleep interval (not bed
        // time), then medianed and IQR'd to decide whether the user's
        // schedule is consistent enough to trust.
        let midpointMinutes = nightlySamples.map { night -> Int in
            let midpoint = night.bed.addingTimeInterval(night.duration / 2)
            let components = calendar.dateComponents([.hour, .minute], from: midpoint)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
        let medianMidpoint = medianMinutesOfDay(
            midpointMinutes.compactMap { mins -> Date? in
                calendar.date(byAdding: .minute, value: mins, to: calendar.startOfDay(for: end))
            }
        )
        let midpointIQR = interquartileRange(midpointMinutes)
        let chronotypeStable = nightlySamples.count >= Self.chronotypeMinNights
            && midpointIQR <= Self.chronotypeMaxIQRMinutes

        let snap = SleepSnapshot(
            sampleCount: nightlySamples.count,
            medianWakeMinutes: medianWake,
            medianBedMinutes: medianBed,
            averageDurationHours: avgDuration / 3600,
            sleepDebtHours: totalDebt,
            medianSleepMidpointMinutes: medianMidpoint,
            midpointIQRMinutes: midpointIQR,
            chronotypeStable: chronotypeStable
        )
        snapshot = snap
        snapshotUpdatedAt = nil   // local-derived; no server timestamp yet

        // Materialise today's energy forecast off the same snapshot so
        // every consumer (suggestion chip, energy view, focus-time
        // recommender) reads from the same source.
        forecast = Self.makeForecast(snap: snap)

        // Push to the backend so other devices (notably macOS, where HK
        // isn't available) can read what iOS computed. Fire-and-forget.
        if let backend {
            let payload = BackendSleepSnapshot(
                sampleCount: snap.sampleCount,
                medianWakeMinutes: snap.medianWakeMinutes,
                medianBedMinutes: snap.medianBedMinutes,
                averageDurationHours: snap.averageDurationHours,
                sleepDebtHours: snap.sleepDebtHours,
                medianSleepMidpointMinutes: snap.medianSleepMidpointMinutes,
                midpointIqrMinutes: snap.midpointIQRMinutes,
                chronotypeStable: snap.chronotypeStable,
                updatedAt: nil
            )
            await backend.uploadSleepSnapshot(payload)
        }
    }
    #endif

    /// Backend-driven refresh. macOS calls this directly (no HK at all);
    /// iOS calls it as a fallback when HK isn't available. No-op when
    /// the user isn't signed in or the backend has no row yet.
    private func refreshFromBackend() async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard let backend, let remote = await backend.fetchSleepSnapshot() else {
            // Don't blow away an existing snapshot — let the empty state
            // continue showing if we already had nothing.
            return
        }

        let snap = SleepSnapshot(
            sampleCount: remote.sampleCount,
            medianWakeMinutes: remote.medianWakeMinutes,
            medianBedMinutes: remote.medianBedMinutes,
            averageDurationHours: remote.averageDurationHours,
            sleepDebtHours: remote.sleepDebtHours,
            medianSleepMidpointMinutes: remote.medianSleepMidpointMinutes,
            midpointIQRMinutes: remote.midpointIqrMinutes,
            chronotypeStable: remote.chronotypeStable
        )
        snapshot = snap
        snapshotUpdatedAt = remote.updatedAt
        forecast = Self.makeForecast(snap: snap)
    }

    /// IQR (Q3 - Q1) of an integer sample. Returns 0 when the sample is
    /// too small to have meaningful quartiles (< 4 entries) — the caller
    /// treats 0 as "ignore, not enough data".
    private func interquartileRange(_ values: [Int]) -> Int {
        guard values.count >= 4 else { return 0 }
        let sorted = values.sorted()
        let q1 = sorted[sorted.count / 4]
        let q3 = sorted[(3 * sorted.count) / 4]
        return max(0, q3 - q1)
    }

    /// Build today's `EnergyForecast` from a snapshot. Static so unit
    /// tests can call it without standing up the whole service.
    ///
    /// Acrophase derivation:
    /// - Default: `wakeTime + 10h` — population canonical "afternoon peak".
    /// - Chronotype-tuned: shift the default by half the user's offset
    ///   from the population midpoint, capped at ±3h. The 0.5 dampening
    ///   factor prevents extreme outliers (a midpoint 4h late doesn't
    ///   imply a 4h-late peak — the relationship is sub-linear) and the
    ///   ±3h cap is a hard sanity bound so a brief schedule shift can't
    ///   move the peak by more than that.
    static func makeForecast(snap: SleepSnapshot) -> EnergyForecast {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let wakeToday = calendar.date(
            byAdding: .minute, value: snap.medianWakeMinutes, to: startOfToday
        ) ?? startOfToday

        // Bedtime is presented "tonight" — if the median bed time is past
        // midnight (small minute-of-day) we roll it to the next day so
        // chart math stays monotonic.
        var bedToday = calendar.date(
            byAdding: .minute, value: snap.medianBedMinutes, to: startOfToday
        ) ?? startOfToday
        if bedToday <= wakeToday {
            bedToday = calendar.date(byAdding: .day, value: 1, to: bedToday) ?? bedToday
        }

        let defaultPeak = wakeToday.addingTimeInterval(10 * 3600)
        let circadianPeak: Date = {
            guard snap.chronotypeStable,
                  let midpointMinutes = snap.medianSleepMidpointMinutes else {
                return defaultPeak
            }
            // Midpoint may be in early-morning (e.g. 03:00) — interpret as
            // minutes-of-day directly. The shift is signed: positive
            // (later midpoint = owl) pushes the acrophase later in the day.
            let referenceMidpoint = populationMidpointMinutes
            let rawShiftMinutes = Double(midpointMinutes - referenceMidpoint)
            let dampened = rawShiftMinutes * 0.5
            let cappedMinutes = max(-180, min(180, dampened))
            return defaultPeak.addingTimeInterval(cappedMinutes * 60)
        }()

        return EnergyForecast(
            wakeTime: wakeToday,
            bedTime: bedToday,
            circadianPeak: circadianPeak,
            sleepDebtHours: snap.sleepDebtHours,
            sampleCount: snap.sampleCount,
            chronotypeStable: snap.chronotypeStable
        )
    }

    // MARK: - Private

    private func fetchSleepSamples(
        type: HKCategoryType,
        predicate: NSPredicate
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Group sleep samples by the calendar day of their *end* timestamp
    /// (the wake time). For each night, derive earliest "asleep" sample
    /// start = bedtime, latest "asleep" sample end = wake time. Skips
    /// nights consisting only of "in bed" or "awake" entries.
    private func bucketByNight(samples: [HKCategorySample]) -> [Night] {
        var buckets: [Date: [HKCategorySample]] = [:]
        let calendar = Calendar.current

        for sample in samples {
            guard isAsleepValue(sample.value) else { continue }
            let dayKey = calendar.startOfDay(for: sample.endDate)
            buckets[dayKey, default: []].append(sample)
        }

        return buckets
            .sorted(by: { $0.key < $1.key })
            .compactMap { _, daySamples -> Night? in
                guard let bed = daySamples.map(\.startDate).min(),
                      let wake = daySamples.map(\.endDate).max() else { return nil }
                let duration = wake.timeIntervalSince(bed)
                guard duration >= 3 * 3600 && duration <= 14 * 3600 else { return nil }
                return Night(bed: bed, wake: wake, duration: duration)
            }
    }

    /// HK exposes a few "asleep-ish" categories (REM, deep, core) post-
    /// iOS 16. Treat any of them as actual sleep; "in bed" alone doesn't
    /// count because Apple Watch users routinely log "in bed" without a
    /// real sleep session attached.
    private func isAsleepValue(_ raw: Int) -> Bool {
        let asleep = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        let core = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let deep = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let rem = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        return raw == asleep || raw == core || raw == deep || raw == rem
    }

    private func medianMinutesOfDay(_ dates: [Date]) -> Int? {
        guard !dates.isEmpty else { return nil }
        let calendar = Calendar.current
        let mins = dates.map { date -> Int in
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }.sorted()
        let middle = mins.count / 2
        if mins.count % 2 == 1 {
            return mins[middle]
        }
        return (mins[middle - 1] + mins[middle]) / 2
    }

    private struct Night {
        let bed: Date
        let wake: Date
        let duration: TimeInterval
    }
}

/// Snapshot of the user's recent sleep pattern. Stored in minutes-of-day
/// for wake/bed so consumers don't need to drag around a Date.
struct SleepSnapshot: Equatable {
    let sampleCount: Int
    let medianWakeMinutes: Int
    let medianBedMinutes: Int
    let averageDurationHours: Double
    /// Rolling sleep deficit (hours), summed over the snapshot window.
    /// Drives the Process S acceleration in `EnergyForecast`.
    let sleepDebtHours: Double
    /// Median midpoint of sleep (minute-of-day). Nil when the user has
    /// fewer than the threshold number of nights tracked.
    let medianSleepMidpointMinutes: Int?
    /// Interquartile range of midpoints in minutes. Larger = more
    /// scattered schedule. Used to gate chronotype confidence.
    let midpointIQRMinutes: Int
    /// True once we have ≥ 14 nights AND the midpoint IQR is ≤ 90 min.
    /// Forecasts switch from the wake-anchored default acrophase to a
    /// midpoint-shifted one when this is true.
    let chronotypeStable: Bool

    /// Pretty wake time, e.g. "7:30 AM".
    var wakeTimeLabel: String { Self.label(forMinutesOfDay: medianWakeMinutes) }
    /// Pretty bedtime, e.g. "11:15 PM".
    var bedTimeLabel: String { Self.label(forMinutesOfDay: medianBedMinutes) }
    /// Pretty midpoint, e.g. "3:45 AM". Nil until enough data.
    var midpointLabel: String? {
        medianSleepMidpointMinutes.map { Self.label(forMinutesOfDay: $0) }
    }

    /// Chronotype bucket derived from the midpoint offset vs the
    /// population mean. Returns nil until `chronotypeStable` is true so
    /// the UI never displays a guess.
    var chronotype: Chronotype? {
        guard chronotypeStable, let midpoint = medianSleepMidpointMinutes else { return nil }
        // 4 AM is the population mean; anything > 90 min past = strong owl,
        // > 90 min before = strong lark, in-between is neutral.
        let delta = midpoint - 4 * 60
        if delta < -90  { return .lark }
        if delta > 90   { return .owl }
        return .neutral
    }

    /// Recommended best window for a generic habit, given the user's
    /// chronotype proxy. Returns absolute minutes-of-day plus a label.
    func suggestedWindow(for kind: HabitKind) -> SuggestedWindow {
        switch kind {
        case .upkeep:
            // 30 minutes after wake — easy to attach to a morning routine.
            let minute = (medianWakeMinutes + 30) % (24 * 60)
            return SuggestedWindow(label: Self.label(forMinutesOfDay: minute), reason: "Anchored to your usual wake time")
        case .focus:
            // ~2h after wake — peak alertness for most chronotypes.
            let minute = (medianWakeMinutes + 120) % (24 * 60)
            return SuggestedWindow(label: Self.label(forMinutesOfDay: minute), reason: "Your peak focus window")
        case .movement:
            // ~10h after wake — afternoon performance peak; also avoids
            // disrupting sleep when scheduled later.
            let minute = (medianWakeMinutes + 600) % (24 * 60)
            return SuggestedWindow(label: Self.label(forMinutesOfDay: minute), reason: "Your afternoon energy peak")
        case .calm:
            // ~90 minutes before typical bedtime — good wind-down slot.
            let minute = max(0, medianBedMinutes - 90) % (24 * 60)
            return SuggestedWindow(label: Self.label(forMinutesOfDay: minute), reason: "Wind-down before bed")
        }
    }

    private static func label(forMinutesOfDay totalMinutes: Int) -> String {
        let normalized = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60)
        let hour24 = normalized / 60
        let minute = normalized % 60
        let hour12 = ((hour24 + 11) % 12) + 1
        let am = hour24 < 12
        return String(format: "%d:%02d %@", hour12, minute, am ? "AM" : "PM")
    }
}

/// Coarse chronotype bucket. Surfaced in the EnergyView as a small badge
/// so the user understands *why* their peak is shifted from the default.
enum Chronotype: String, Equatable {
    case lark      // midpoint earlier than population mean
    case neutral   // within ±90 min of mean
    case owl       // midpoint later than mean

    var label: String {
        switch self {
        case .lark:    return "Early bird"
        case .neutral: return "Average"
        case .owl:     return "Night owl"
        }
    }

    var systemImage: String {
        switch self {
        case .lark:    return "sunrise.fill"
        case .neutral: return "sun.max.fill"
        case .owl:     return "moon.stars.fill"
        }
    }
}

/// Coarse classification of habits used to pick an energy window. Mapped
/// from the user's habit title via simple keyword matching — not perfect,
/// but good enough for a "suggested time" hint.
enum HabitKind {
    case upkeep   // hydrate, vitamins, supplements
    case focus    // study, deep work, write
    case movement // run, gym, walk, yoga
    case calm     // read, meditate, journal, stretch

    static func classify(_ title: String) -> HabitKind {
        let t = title.lowercased()
        let movementKeywords = ["run", "jog", "gym", "workout", "exercise", "walk", "yoga", "swim", "lift", "hike", "bike", "cycle", "pilates"]
        let calmKeywords = ["read", "meditat", "journal", "gratitude", "stretch", "breath", "mindful", "pray"]
        let focusKeywords = ["study", "code", "write", "draw", "practice", "learn", "deep work", "focus"]

        if movementKeywords.contains(where: { t.contains($0) }) { return .movement }
        if calmKeywords.contains(where: { t.contains($0) }) { return .calm }
        if focusKeywords.contains(where: { t.contains($0) }) { return .focus }
        return .upkeep
    }
}

struct SuggestedWindow: Equatable {
    let label: String
    let reason: String
}

// MARK: - UI

/// Tiny inline chip that surfaces a sleep-derived best-time suggestion
/// for the habit currently being added. Renders nothing until the user
/// has typed at least 2 characters AND we have enough sleep data.
///
/// Live readout:
/// - **Now** segment shows the user's current energy band ("Peak 78").
/// - **Suggestion** segment picks one of three shapes depending on the
///   habit kind:
///     * `.movement` / `.focus` → recommends the next predicted peak.
///     * `.calm` → recommends 90 min before typical bedtime.
///     * `.upkeep` → keeps the existing "anchored to wake time" copy.
struct SleepSuggestionChip: View {
    @ObservedObject var service: SleepInsightsService
    let habitTitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let snapshot = service.snapshot,
               let forecast = service.forecast,
               !habitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let kind = HabitKind.classify(habitTitle)
                let suggestion = liveSuggestion(kind: kind, snapshot: snapshot, forecast: forecast)
                let now = Date()
                let energy = forecast.energy(at: now)
                let band = EnergyForecast.label(for: energy)

                HStack(spacing: 6) {
                    Image(systemName: band.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(bandTint(for: band))
                    Text("\(band.label) \(Int(energy.rounded()))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(bandTint(for: band))
                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(suggestion.headline)
                        .font(.system(size: 11, weight: .semibold))
                    Text(suggestion.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.indigo.opacity(colorScheme == .dark ? 0.16 : 0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.indigo.opacity(0.24), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: service.snapshot)
    }

    /// Pick a recommendation tailored to the habit kind. Movement/focus
    /// habits chase the next predicted peak; calm habits anchor to the
    /// wind-down window; upkeep falls back to the existing wake-time hint.
    private func liveSuggestion(
        kind: HabitKind,
        snapshot: SleepSnapshot,
        forecast: EnergyForecast
    ) -> (headline: String, detail: String) {
        let now = Date()
        let endOfWindow = Calendar.current.date(byAdding: .hour, value: 12, to: now) ?? now
        switch kind {
        case .movement, .focus:
            if let peak = forecast.nextPeak(after: now, until: endOfWindow) {
                return (headline: "Peak at \(Self.timeString(peak))", detail: "best for \(kind == .movement ? "movement" : "deep work")")
            }
            // Past today's peak — fall back to the static wake-anchor copy.
            let window = snapshot.suggestedWindow(for: kind)
            return (headline: "Try \(window.label)", detail: window.reason)
        case .calm:
            let window = snapshot.suggestedWindow(for: .calm)
            return (headline: "Try \(window.label)", detail: window.reason)
        case .upkeep:
            let window = snapshot.suggestedWindow(for: .upkeep)
            return (headline: "Try \(window.label)", detail: window.reason)
        }
    }

    private func bandTint(for band: EnergyBand) -> Color {
        switch band {
        case .peak:     return .green
        case .moderate: return .indigo
        case .dip:      return .orange
        case .low:      return .red
        }
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
