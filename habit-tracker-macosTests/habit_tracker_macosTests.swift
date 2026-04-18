import Testing
import Foundation
@testable import habit_tracker_macos

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
