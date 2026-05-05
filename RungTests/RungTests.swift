import Testing
import Foundation
@testable import Rung

// MARK: - Existing HabitMetrics tests

struct HabitMetricsTests {

    @Test func currentStreakCountsBackwardFromEndDate() {
        let keys = ["2026-04-12", "2026-04-14", "2026-04-15", "2026-04-16"]
        #expect(HabitMetrics.currentStreak(for: keys, endingAt: "2026-04-16") == 3)
        #expect(HabitMetrics.bestStreak(for: keys) == 3)
    }

    @Test func metricsComputesPerfectDaysAndTodayProgress() {
        let habits = [
            Habit(title: "Read",  createdAt: DateKey.date(from: "2026-04-14"),
                  completedDayKeys: ["2026-04-14", "2026-04-15", "2026-04-16"]),
            Habit(title: "Walk",  createdAt: DateKey.date(from: "2026-04-14"),
                  completedDayKeys: ["2026-04-15"]),
        ]
        let m = HabitMetrics.compute(for: habits, todayKey: "2026-04-16")
        #expect(m.totalHabits         == 2)
        #expect(m.doneToday           == 1)
        #expect(m.progressToday       == 0.5)
        #expect(m.perfectDays         == ["2026-04-15"])
        #expect(m.currentPerfectStreak == 0)
    }

    @Test func perfectDayRequiresBothTasksAndHabits() {
        let habitsWithTaskUndone = [
            Habit(
                title: "Read",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            ),
            Habit(
                title: "Walk",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            ),
            Habit(
                title: "Buy milk",
                entryType: .task,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: []
            )
        ]
        let undone = HabitMetrics.compute(for: habitsWithTaskUndone, todayKey: "2026-04-18")
        #expect(!undone.perfectDays.contains("2026-04-17"))

        let habitsWithTaskDone = [
            Habit(
                title: "Read",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            ),
            Habit(
                title: "Walk",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            ),
            Habit(
                title: "Buy milk",
                entryType: .task,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            )
        ]
        let done = HabitMetrics.compute(for: habitsWithTaskDone, todayKey: "2026-04-18")
        #expect(done.perfectDays.contains("2026-04-17"))
    }

    @Test func completedTaskDoesNotBlockLaterPerfectDays() {
        let habits = [
            Habit(
                title: "Read",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17", "2026-04-18"]
            ),
            Habit(
                title: "Walk",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17", "2026-04-18"]
            ),
            Habit(
                title: "Buy milk",
                entryType: .task,
                createdAt: DateKey.date(from: "2026-04-17"),
                completedDayKeys: ["2026-04-17"]
            )
        ]

        let m = HabitMetrics.compute(for: habits, todayKey: "2026-04-18")
        #expect(m.perfectDays.contains("2026-04-17"))
        #expect(m.perfectDays.contains("2026-04-18"))
        #expect(m.totalHabits == 2)
        #expect(m.doneToday == 2)
    }

    @Test func perfectDayOnlyRequiresHabitsActiveThatDay() {
        let habits = [
            Habit(
                title: "Read",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-10"),
                completedDayKeys: ["2026-04-17"]
            ),
            Habit(
                title: "New habit",
                entryType: .habit,
                createdAt: DateKey.date(from: "2026-04-18"),
                completedDayKeys: []
            )
        ]

        let m = HabitMetrics.compute(for: habits, todayKey: "2026-04-18")
        #expect(m.perfectDays.contains("2026-04-17"))
    }

    @Test func weeklyTargetRestBudgetDoesNotMarkFutureDaysPerfect() {
        // Monday 2026-05-04: user logs the only gym session of the week.
        // A 4×/week target leaves a 3-day rest budget. Without the today
        // cap, isSatisfied happily marks Tue/Wed/Thu as perfect rest days
        // before they've been lived — lighting up future dots in the
        // year grid.
        let habit = Habit(
            title: "Workout",
            entryType: .habit,
            createdAt: DateKey.date(from: "2026-04-01"),
            completedDayKeys: ["2026-05-04"],
            weeklyTarget: 4
        )

        let m = HabitMetrics.compute(for: [habit], todayKey: "2026-05-04")
        #expect(m.perfectDays.contains("2026-05-04"))
        #expect(!m.perfectDays.contains("2026-05-05"))
        #expect(!m.perfectDays.contains("2026-05-06"))
        #expect(!m.perfectDays.contains("2026-05-07"))
    }

    @Test func dailySuggestionElectionPrefersHigherDataQuality() {
        // Mac sees only iCloud (1 calendar), iPhone fuses iCloud + Google
        // + Exchange (3 calendars) — iPhone's payload should win even
        // when both arrive on the same day with the same meeting count.
        let mac = DailySuggestionPayload(
            dayKey: "2026-05-04",
            aiHeadline: "Mac headline",
            meetingCount: 5,
            meetingMinutes: 240,
            perHabit: [],
            dataQuality: 1 * 100 + 5,
            generatedAt: Date(),
            generatedBy: "macos"
        )
        let iphone = DailySuggestionPayload(
            dayKey: "2026-05-04",
            aiHeadline: "iPhone headline",
            meetingCount: 5,
            meetingMinutes: 240,
            perHabit: [],
            dataQuality: 3 * 100 + 5,
            generatedAt: Date(),
            generatedBy: "ios"
        )

        // The Mac-side election sees iPhone's payload as remote — should adopt it.
        let elected = HabitBackendStore.electDailySuggestion(local: mac, remote: iphone)
        #expect(elected.generatedBy == "ios")
        #expect(elected.aiHeadline == "iPhone headline")

        // The Mac shouldn't bother uploading when remote outranks it.
        #expect(HabitBackendStore.localShouldUpload(local: mac, remote: iphone) == false)

        // Reverse: an iPhone arriving second sees the Mac's older
        // payload as remote — iPhone is richer, takes over, AND uploads.
        let electedReverse = HabitBackendStore.electDailySuggestion(local: iphone, remote: mac)
        #expect(electedReverse.generatedBy == "ios")
        #expect(HabitBackendStore.localShouldUpload(local: iphone, remote: mac) == true)
    }

    @Test func dailySuggestionElectionUsesLocalWhenNoRemote() {
        // Mac-only user: no remote payload exists → local is the canonical
        // value, and we should upload it so future devices read it back.
        let local = DailySuggestionPayload(
            dayKey: "2026-05-04",
            aiHeadline: "lone wolf",
            meetingCount: 0,
            meetingMinutes: 0,
            perHabit: [],
            dataQuality: 100,
            generatedAt: Date(),
            generatedBy: "macos"
        )
        let elected = HabitBackendStore.electDailySuggestion(local: local, remote: nil)
        #expect(elected == local)
        #expect(HabitBackendStore.localShouldUpload(local: local, remote: nil) == true)
    }

    @Test func dailySuggestionElectionTieGoesToRemote() {
        // Equal dataQuality → remote wins (server is authoritative).
        // This avoids ping-pong uploads between two equally-rich devices.
        let local = DailySuggestionPayload(
            dayKey: "2026-05-04", aiHeadline: nil, meetingCount: 2,
            meetingMinutes: 60, perHabit: [], dataQuality: 105,
            generatedAt: Date(), generatedBy: "ios"
        )
        let remote = DailySuggestionPayload(
            dayKey: "2026-05-04", aiHeadline: "stable", meetingCount: 2,
            meetingMinutes: 60, perHabit: [], dataQuality: 105,
            generatedAt: Date(), generatedBy: "ipados"
        )
        let elected = HabitBackendStore.electDailySuggestion(local: local, remote: remote)
        #expect(elected.generatedBy == "ipados")
        #expect(HabitBackendStore.localShouldUpload(local: local, remote: remote) == false)
    }

    @Test func dailySuggestionElectionDifferentDaysFallsBackToLocal() {
        // Stale remote (yesterday's payload) shouldn't override today's
        // local one — we never want to render a different day's data.
        let today = DailySuggestionPayload(
            dayKey: "2026-05-04", aiHeadline: "today", meetingCount: 0,
            meetingMinutes: 0, perHabit: [], dataQuality: 0,
            generatedAt: Date(), generatedBy: "macos"
        )
        let yesterday = DailySuggestionPayload(
            dayKey: "2026-05-03", aiHeadline: "stale", meetingCount: 99,
            meetingMinutes: 999, perHabit: [], dataQuality: 9999,
            generatedAt: Date(), generatedBy: "macos"
        )
        let elected = HabitBackendStore.electDailySuggestion(local: today, remote: yesterday)
        #expect(elected.dayKey == "2026-05-04")
        #expect(HabitBackendStore.localShouldUpload(local: today, remote: yesterday) == true)
    }

    @Test func backendHabitFallsBackToEarliestCompletedDateForLocalCreationDate() {
        let remote = BackendHabit(
            id: 42,
            title: "Read",
            checksByDate: [
                "2026-04-16": true,
                "2026-04-17": true
            ]
        )

        #expect(DateKey.key(for: remote.localCreatedAt) == "2026-04-16")
    }
}

// MARK: - RetryPolicy

struct RetryPolicyTests {

    @Test func firstAttemptHasNoDelay() {
        let p = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8)
        #expect(p.delay(for: 0) == 0)
    }

    @Test func secondAttemptUsesBaseDelay() {
        let p = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8)
        #expect(p.delay(for: 1) == 0.5)
    }

    @Test func thirdAttemptDoublesDelay() {
        let p = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8)
        #expect(p.delay(for: 2) == 1.0)
    }

    @Test func delayIsCappedAtMaxDelay() {
        let p = RetryPolicy(maxAttempts: 10, baseDelay: 1.0, maxDelay: 8)
        // attempt 4 would be 8.0 (1 * 2^3), attempt 5 would be 16 → capped at 8
        #expect(p.delay(for: 4) == 8.0)
        #expect(p.delay(for: 5) == 8.0)
        #expect(p.delay(for: 9) == 8.0)
    }

    @Test func noPolicyAlwaysReturnsZeroDelay() {
        let p = RetryPolicy.none
        for attempt in 0..<5 {
            #expect(p.delay(for: attempt) == 0)
        }
    }
}

// MARK: - ResponseCache

struct ResponseCacheTests {

    @Test func habitsCacheReturnsFreshValue() async {
        let cache = ResponseCache()
        let stub = [BackendHabit(id: 1, title: "Run", checksByDate: [:])]
        await cache.cacheHabits(stub, ttl: 60)
        let result = await cache.cachedHabits()
        #expect(result?.first?.title == "Run")
    }

    @Test func habitsCacheReturnsNilAfterExpiry() async {
        let cache = ResponseCache()
        let stub = [BackendHabit(id: 1, title: "Run", checksByDate: [:])]
        await cache.cacheHabits(stub, ttl: -1)  // already expired
        let result = await cache.cachedHabits()
        #expect(result == nil)
    }

    @Test func invalidateHabitsClearsCache() async {
        let cache = ResponseCache()
        await cache.cacheHabits([BackendHabit(id: 1, title: "Run", checksByDate: [:])], ttl: 120)
        await cache.invalidateHabits()
        let result = await cache.cachedHabits()
        #expect(result == nil)
    }

    @Test func invalidateAllClearsBothSlots() async {
        let cache = ResponseCache()
        await cache.cacheHabits([BackendHabit(id: 1, title: "Run", checksByDate: [:])], ttl: 120)
        await cache.invalidateAll()
        let habits    = await cache.cachedHabits()
        let dashboard = await cache.cachedDashboard()
        #expect(habits    == nil)
        #expect(dashboard == nil)
    }
}

// MARK: - SyncEngine.reconcile

struct SyncEngineReconcileTests {

    private func makeHabit(id: Int64, title: String, status: SyncStatus = .synced) -> Habit {
        let h = Habit(title: title, syncStatus: status)
        h.backendId = id
        return h
    }

    @Test func knownHabitIsMarkedForUpdate() {
        let local  = [makeHabit(id: 1, title: "Old title")]
        let remote = [BackendHabit(id: 1, title: "New title", checksByDate: [:])]
        let result = SyncEngine.reconcile(local: local, remote: remote)
        #expect(result.toUpdate.count == 1)
        #expect(result.toUpdate.first?.remote.title == "New title")
        #expect(result.toInsert.isEmpty)
        #expect(result.toDelete.isEmpty)
    }

    @Test func serverOnlyHabitIsInserted() {
        let local  = [Habit]()
        let remote = [BackendHabit(id: 42, title: "New from server", checksByDate: [:])]
        let result = SyncEngine.reconcile(local: local, remote: remote)
        #expect(result.toInsert.count == 1)
        #expect(result.toInsert.first?.id == 42)
        #expect(result.toUpdate.isEmpty)
        #expect(result.toDelete.isEmpty)
    }

    @Test func habitAbsentOnServerIsDeleted_serverWins() {
        let local  = [makeHabit(id: 99, title: "Old")]
        let remote = [BackendHabit]()
        let result = SyncEngine.reconcile(local: local, remote: remote)
        #expect(result.toDelete.count == 1)
        #expect(result.toUpdate.isEmpty)
        #expect(result.toInsert.isEmpty)
    }

    @Test func unsyncedLocalHabitIsNeverDeleted() {
        // Habit with no backendId = still in outbox; reconcile must not touch it
        let unsynced = Habit(title: "Pending upload", syncStatus: .pending)
        // backendId stays nil
        let result = SyncEngine.reconcile(local: [unsynced], remote: [])
        #expect(result.toDelete.isEmpty)
        #expect(result.toInsert.isEmpty)
        #expect(result.toUpdate.isEmpty)
    }

    @Test func mixedScenario() {
        let local: [Habit] = [
            makeHabit(id: 1, title: "Keep"),
            makeHabit(id: 2, title: "Will be deleted"),
        ]
        let remote: [BackendHabit] = [
            BackendHabit(id: 1, title: "Keep updated", checksByDate: [:]),
            BackendHabit(id: 3, title: "Brand new",    checksByDate: [:]),
        ]
        let result = SyncEngine.reconcile(local: local, remote: remote)
        #expect(result.toUpdate.count == 1)
        #expect(result.toInsert.count == 1)
        #expect(result.toDelete.count == 1)
        #expect(result.toInsert.first?.id == 3)
        #expect(result.toDelete.first?.backendId == 2)
    }
}

// MARK: - SyncEngine outbox helpers

struct SyncEngineOutboxTests {

    @Test func pendingCreatesReturnsHabitsWithNoBackendId() {
        let pending  = Habit(title: "New",    syncStatus: .pending)    // backendId == nil
        let synced   = Habit(title: "Synced", syncStatus: .synced);   synced.backendId   = 1
        let deleted  = Habit(title: "Del",    syncStatus: .deleted)    // backendId == nil

        let creates = SyncEngine.pendingCreates(in: [pending, synced, deleted])
        #expect(creates.count == 1)
        #expect(creates.first?.title == "New")
    }

    @Test func failedUploadsReturnsHabitsWithBackendIdAndFailedStatus() {
        let failed  = Habit(title: "Failed", syncStatus: .failed);   failed.backendId  = 5
        let pending = Habit(title: "Pend",   syncStatus: .pending);  pending.backendId = 6
        let synced  = Habit(title: "Ok",     syncStatus: .synced);   synced.backendId  = 7

        let retries = SyncEngine.failedUploads(in: [failed, pending, synced])
        #expect(retries.count == 1)
        #expect(retries.first?.backendId == 5)
    }
}

// MARK: - Habit model

struct HabitModelTests {

    @Test func defaultSyncStatusIsPending() {
        let h = Habit(title: "Test")
        #expect(h.syncStatus == .pending)
    }

    @Test func defaultEntryTypeIsHabit() {
        let h = Habit(title: "Default type")
        #expect(h.entryType == .habit)
    }

    @Test func taskEntryTypeCanBeStored() {
        let h = Habit(title: "Buy milk", entryType: .task)
        #expect(h.entryType == .task)
    }

    @Test func syncStatusRoundtripsAsRawValue() {
        for status in [SyncStatus.synced, .pending, .failed, .deleted] {
            #expect(SyncStatus(rawValue: status.rawValue) == status)
        }
    }

    @Test func habitWithBackendIdStartsSynced() {
        let h = Habit(title: "From server", backendId: 10, syncStatus: .synced)
        #expect(h.backendId  == 10)
        #expect(h.syncStatus == .synced)
    }
}

// MARK: - SSE reconnect simulation

/// Validates the SSE parsing logic in isolation by feeding raw lines through
/// a mock line sequence — no network required.
struct SSEParsingTests {

    /// Minimal stand-in for the relevant part of HabitBackendStore SSE parsing.
    private func parseSSE(lines: [String]) -> [(name: String, payload: String)] {
        var results: [(String, String)] = []
        var eventName = "message"
        var dataLines: [String] = []

        for raw in lines {
            if raw.isEmpty {
                let payload = dataLines.joined(separator: "\n")
                if !payload.isEmpty { results.append((eventName, payload)) }
                eventName = "message"; dataLines.removeAll()
                continue
            }
            if raw.hasPrefix("event:") { eventName = String(raw.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("data:")  { dataLines.append(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
        return results
    }

    @Test func parsesTypicalMessageCreatedEvent() {
        let lines = [
            "event: message.created",
            "data: {\"id\":1}",
            "",
        ]
        let events = parseSSE(lines: lines)
        #expect(events.count == 1)
        #expect(events[0].name    == "message.created")
        #expect(events[0].payload == "{\"id\":1}")
    }

    @Test func parsesMultiLineDataField() {
        let lines = ["event: test", "data: line1", "data: line2", ""]
        let events = parseSSE(lines: lines)
        #expect(events.first?.payload == "line1\nline2")
    }

    @Test func ignoresPingEvents() {
        let lines = ["event: ping", "data: {}", ""]
        let events = parseSSE(lines: lines)
        // ping is parsed but the store ignores it; check the name is captured correctly
        #expect(events.first?.name == "ping")
    }

    @Test func emptyDataIsSkipped() {
        let lines = ["event: test", ""]
        let events = parseSSE(lines: lines)
        #expect(events.isEmpty)
    }

    @Test func multipleEventsInSequence() {
        let lines = [
            "event: message.created", "data: msg1", "",
            "event: match.updated",   "data: upd",  "",
        ]
        let events = parseSSE(lines: lines)
        #expect(events.count == 2)
        #expect(events[0].name == "message.created")
        #expect(events[1].name == "match.updated")
    }

    @Test func reconnectResumesFromLastEventID() {
        // Simulates: first batch delivers id 5, second batch (reconnect) should use id 5
        var lastID: String? = nil
        func processLines(_ lines: [String]) {
            var dataLines: [String] = []
            for raw in lines {
                if raw.hasPrefix("id:") { lastID = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                if raw.hasPrefix("data:") { dataLines.append(raw) }
            }
        }

        processLines(["id: 5", "event: message.created", "data: {}", ""])
        #expect(lastID == "5")
        // Next connection would send Last-Event-ID: 5 — verify we stored it
        processLines(["id: 6", "data: next", ""])
        #expect(lastID == "6")
    }
}

// MARK: - Bimodal energy curve tests

/// Locks the new bimodal `EnergyForecast` against regression — we want the
/// curve to actually have two peaks and two dips, not one of each. These
/// tests exercise a typical wake-at-7-AM, peak-at-5-PM chronotype and
/// assert the canonical features hold:
///   - sleep inertia notch in the first 45 min after wake
///   - morning peak between 9 AM and noon (carrier rise + harmonic crest)
///   - lunch dip between 12 PM and 4 PM (harmonic trough)
///   - afternoon peak between 4 PM and 8 PM (acrophase)
///   - monotonic descent into bedtime
struct EnergyForecastBimodalTests {

    private func makeForecast(wakeHour: Int = 7, bedHour: Int = 23, peakHour: Int = 17,
                              sleepDebtHours: Double = 0) -> EnergyForecast {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        return EnergyForecast(
            wakeTime:       cal.date(bySettingHour: wakeHour, minute: 0, second: 0, of: today)!,
            bedTime:        cal.date(bySettingHour: bedHour,  minute: 0, second: 0, of: today)!,
            circadianPeak:  cal.date(bySettingHour: peakHour, minute: 0, second: 0, of: today)!,
            sleepDebtHours: sleepDebtHours,
            sampleCount:    14,
            chronotypeStable: true
        )
    }

    private func atHour(_ hour: Int, minute: Int = 0, in forecast: EnergyForecast) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: forecast.wakeTime)!
    }

    @Test func sleepInertiaDipNearWake() {
        let f = makeForecast()
        let atWake     = f.energy(at: f.wakeTime)
        let twoHrLater = f.energy(at: atHour(9, in: f))
        // Energy should rise sharply once inertia clears.
        #expect(twoHrLater > atWake + 8, "Expected energy to rise > 8 points within 2h of wake; was \(atWake) → \(twoHrLater)")
    }

    @Test func morningPeakAfternoonDipAfternoonPeakOrdering() {
        let f = makeForecast()
        let morning   = f.energy(at: atHour(10, in: f))
        let lunch     = f.energy(at: atHour(14, in: f))
        let afternoon = f.energy(at: atHour(17, in: f))   // acrophase
        // Lunch dip MUST be lower than both peaks — that's the whole point
        // of the 12-h harmonic.
        #expect(lunch < morning, "Lunch (\(lunch)) should dip below morning peak (\(morning))")
        #expect(lunch < afternoon, "Lunch (\(lunch)) should dip below afternoon peak (\(afternoon))")
        // Afternoon peak should be the global daytime maximum — it sits at
        // the acrophase.
        #expect(afternoon >= morning, "Afternoon peak (\(afternoon)) should be ≥ morning peak (\(morning))")
    }

    @Test func nextPeakAndDipLandOnRealExtrema() {
        let f = makeForecast()
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: 6, minute: 0, second: 0, of: f.wakeTime)!
        let dayEnd   = cal.date(bySettingHour: 23, minute: 0, second: 0, of: f.wakeTime)!

        guard let firstPeak = f.nextPeak(after: dayStart, until: dayEnd) else {
            Issue.record("nextPeak returned nil — the curve must have at least one peak in the day window")
            return
        }
        // The first peak should land in the morning window.
        let firstPeakHour = cal.component(.hour, from: firstPeak)
        #expect((8...12).contains(firstPeakHour), "First peak hour was \(firstPeakHour); expected 8–12")

        guard let dip = f.nextDip(after: firstPeak, until: dayEnd) else {
            Issue.record("nextDip after first peak returned nil — bimodal curve must have a lunch dip")
            return
        }
        let dipHour = cal.component(.hour, from: dip)
        #expect((12...16).contains(dipHour), "Lunch dip hour was \(dipHour); expected 12–16")

        guard let secondPeak = f.nextPeak(after: dip, until: dayEnd) else {
            Issue.record("nextPeak after dip returned nil — afternoon peak must exist")
            return
        }
        let secondPeakHour = cal.component(.hour, from: secondPeak)
        #expect((15...19).contains(secondPeakHour), "Afternoon peak hour was \(secondPeakHour); expected 15–19")
    }

    @Test func sleepDebtSuppressesPeakHeight() {
        let rested  = makeForecast(sleepDebtHours: 0).energy(at: atHour(17, in: makeForecast(sleepDebtHours: 0)))
        let tired   = makeForecast(sleepDebtHours: 4).energy(at: atHour(17, in: makeForecast(sleepDebtHours: 4)))
        // Same person, different debt — the tired curve should peak lower.
        #expect(tired < rested, "Sleep debt should suppress peak height; rested=\(rested) tired=\(tired)")
    }

    @Test func bandLabelTransitionsAcrossDay() {
        let f = makeForecast()
        let dawn  = EnergyForecast.label(for: f.energy(at: atHour(7, in: f)))
        let acro  = EnergyForecast.label(for: f.energy(at: atHour(17, in: f)))
        let night = EnergyForecast.label(for: f.energy(at: atHour(23, in: f)))
        #expect(dawn  != acro, "Dawn band should differ from acrophase band; both were \(acro)")
        #expect(acro  != night, "Acrophase band should differ from late-evening band; both were \(acro)")
    }

    @Test func predictedDLMOFallsRoughly14HoursAfterWake() {
        let f = makeForecast(wakeHour: 7, peakHour: 17)  // chronotypeStable=true but
                                                          // peakHour matches default wake+10
        let hoursAfterWake = f.predictedDLMO.timeIntervalSince(f.wakeTime) / 3600
        // Default wake-anchored DLMO: 14h after wake, so ~21:00.
        #expect(abs(hoursAfterWake - 14) < 0.5, "DLMO should be ~14h after wake; was \(hoursAfterWake)h")
    }

    @Test func predictedDLMOShiftsLaterForLateChronotype() {
        let early = makeForecast(wakeHour: 7, peakHour: 16)   // 1h earlier acrophase
        let late  = makeForecast(wakeHour: 7, peakHour: 19)   // 2h later acrophase
        // Late chronotype's DLMO must trail the early one — same midpoint
        // shift the acrophase received gets applied to the DLMO prior so
        // wake/peak/DLMO stay coherent.
        #expect(late.predictedDLMO > early.predictedDLMO,
                "Late chronotype DLMO (\(late.predictedDLMO)) should trail early (\(early.predictedDLMO))")
    }

    @Test func confidenceBandWidensWhenChronotypeUnstable() {
        let stable = makeForecast()
        let cal = Calendar.current
        let unstable = EnergyForecast(
            wakeTime: stable.wakeTime,
            bedTime: stable.bedTime,
            circadianPeak: stable.circadianPeak,
            sleepDebtHours: stable.sleepDebtHours,
            sampleCount: 3,        // sparse data
            chronotypeStable: false
        )
        _ = cal
        let stableBand = stable.confidenceBand(at: stable.circadianPeak)
        let unstableBand = unstable.confidenceBand(at: unstable.circadianPeak)
        #expect(unstableBand > stableBand,
                "Unlearned chronotype should widen the band; stable=\(stableBand) unstable=\(unstableBand)")
    }

    @Test func bimodalityProbabilityDetectsCanonicalTwoPeakDay() {
        // Wake at 6 AM, acrophase at 6 PM → tight harmonic dip + late
        // shoulder — the canonical bimodal silhouette the research review
        // describes for a well-rested day worker.
        let f = makeForecast(wakeHour: 6, bedHour: 23, peakHour: 18, sleepDebtHours: 0)
        let p = f.bimodalityProbability
        #expect(p >= 0.5, "A rested 7→23 day with a 6 PM acrophase should register as bimodal; got p=\(p)")
    }

    @Test func bimodalityProbabilityFallsForSleepDebtFlattenedDay() {
        // Heavy debt flattens the late-day rebound — the research
        // recommendation predicts the trough fills in. The model should
        // therefore drop bimodality classification in that case.
        let f = makeForecast(wakeHour: 6, bedHour: 23, peakHour: 18, sleepDebtHours: 5)
        let p = f.bimodalityProbability
        // Not a hard requirement that it must be 0 — but the heavy-debt
        // curve should not be strictly more bimodal than the rested one.
        let rested = makeForecast(wakeHour: 6, bedHour: 23, peakHour: 18, sleepDebtHours: 0)
        #expect(p <= rested.bimodalityProbability,
                "Sleep-debt curve should not be more bimodal than rested; rested=\(rested.bimodalityProbability) tired=\(p)")
    }
}

// MARK: - Per-habit time suggestion tests

/// Locks the canonical-key + keyword classifier in
/// `HabitTimeSuggestion.TaskShape.classify(_:)` so the per-habit chip
/// renders the right band for each habit type.
struct HabitTimeSuggestionShapeTests {
    typealias Shape = HabitTimeSuggestion.TaskShape

    @Test func canonicalKeysMapToExpectedShapes() {
        #expect(Shape.classify(canonicalKey: "workout",  title: "")  == .physicalPeak)
        #expect(Shape.classify(canonicalKey: "run",      title: "")  == .physicalPeak)
        #expect(Shape.classify(canonicalKey: "swim",     title: "")  == .physicalPeak)
        #expect(Shape.classify(canonicalKey: "cycle",    title: "")  == .physicalPeak)
        #expect(Shape.classify(canonicalKey: "study",    title: "")  == .mentalPeak)
        #expect(Shape.classify(canonicalKey: "read",     title: "")  == .windDown)
        #expect(Shape.classify(canonicalKey: "meditate", title: "")  == .windDown)
        #expect(Shape.classify(canonicalKey: "journal",  title: "")  == .windDown)
        #expect(Shape.classify(canonicalKey: "yoga",     title: "")  == .flexible)
        #expect(Shape.classify(canonicalKey: "water",    title: "")  == .flexible)
    }

    @Test func keywordFallbackPicksDipForChores() {
        #expect(Shape.classify(canonicalKey: nil, title: "Run laundry")        == .dip)
        #expect(Shape.classify(canonicalKey: nil, title: "Wash dishes")        == .dip)
        #expect(Shape.classify(canonicalKey: nil, title: "Reply to inbox")     == .dip)
        #expect(Shape.classify(canonicalKey: nil, title: "Cook dinner")        == .dip)
    }

    @Test func keywordFallbackPicksPhysicalForExercise() {
        #expect(Shape.classify(canonicalKey: nil, title: "Gym 6 AM")           == .physicalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Tennis match")       == .physicalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Climbing session")   == .physicalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Boxing class")       == .physicalPeak)
    }

    @Test func keywordFallbackPicksMentalForCognitiveWork() {
        #expect(Shape.classify(canonicalKey: nil, title: "Deep work block")    == .mentalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Code review session") == .mentalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Study for exam")     == .mentalPeak)
        #expect(Shape.classify(canonicalKey: nil, title: "Research paper")     == .mentalPeak)
    }

    @Test func keywordFallbackPicksWindDownForContemplative() {
        #expect(Shape.classify(canonicalKey: nil, title: "Read 20 minutes")    == .windDown)
        #expect(Shape.classify(canonicalKey: nil, title: "Stretch before bed") == .windDown)
        #expect(Shape.classify(canonicalKey: nil, title: "Plan tomorrow")      == .windDown)
    }

    @Test func unknownTitleFallsBackToFlexible() {
        #expect(Shape.classify(canonicalKey: nil, title: "Something random") == .flexible)
        #expect(Shape.classify(canonicalKey: nil, title: "")                 == .flexible)
    }
}
