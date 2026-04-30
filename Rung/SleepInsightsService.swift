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

    /// True while a refresh is in flight. Lets the UI dim/disable
    /// suggestion chips so the user doesn't see them flicker.
    @Published private(set) var isRefreshing = false

    private let store = HKHealthStore()

    private init() {}

    /// Pull the last `nights` nights of sleep samples and recompute the
    /// snapshot. Safe to call on platforms without HealthKit (e.g. older
    /// macOS) — returns silently. Idempotent.
    func refresh(nights: Int = 14) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
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
            return
        }

        let nightlySamples = bucketByNight(samples: samples)
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

        snapshot = SleepSnapshot(
            sampleCount: nightlySamples.count,
            medianWakeMinutes: medianWake,
            medianBedMinutes: medianBed,
            averageDurationHours: avgDuration / 3600
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

    /// Pretty wake time, e.g. "7:30 AM".
    var wakeTimeLabel: String { Self.label(forMinutesOfDay: medianWakeMinutes) }
    /// Pretty bedtime, e.g. "11:15 PM".
    var bedTimeLabel: String { Self.label(forMinutesOfDay: medianBedMinutes) }

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
struct SleepSuggestionChip: View {
    @ObservedObject var service: SleepInsightsService
    let habitTitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let snapshot = service.snapshot,
               !habitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let kind = HabitKind.classify(habitTitle)
                let window = snapshot.suggestedWindow(for: kind)

                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                    Text("Try around \(window.label)")
                        .font(.system(size: 11, weight: .semibold))
                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(window.reason)
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
}
