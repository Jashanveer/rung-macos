import Foundation

/// Pure, testable reconciliation logic for the SwiftData ↔ backend sync.
///
/// Conflict policy: **server-wins**.
/// The server is the source of truth for title and completedDayKeys.
/// Local changes are first uploaded (outbox flush) then overwritten by the
/// pull result — any race between a local edit and a pull is resolved in
/// favour of what the server persisted.
///
/// The `updatedSince` cursor lets callers pass a timestamp to filter the
/// backend fetch once the server supports the `?updatedSince=` query param.
enum SyncEngine {

    // MARK: - Types

    struct ReconcileResult {
        /// Local habits whose fields should be refreshed from the server copy.
        let toUpdate: [(local: Habit, remote: BackendHabit)]
        /// Habits on the server that don't yet exist locally — insert them.
        let toInsert: [BackendHabit]
        /// Local habits (with a confirmed backendId) absent from the server list.
        /// Caller should delete them from SwiftData (server-wins).
        let toDelete: [Habit]
    }

    // MARK: - Reconcile

    /// Compute the diff between `local` (SwiftData) and `remote` (server).
    ///
    /// Habits with `backendId == nil` are in the outbox and are never touched
    /// by reconciliation — they must be uploaded first.
    static func reconcile(local: [Habit], remote: [BackendHabit]) -> ReconcileResult {
        let remoteByID  = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let localByBID  = Dictionary(
            uniqueKeysWithValues: local.compactMap { h in h.backendId.map { ($0, h) } }
        )

        var toUpdate: [(Habit, BackendHabit)] = []
        var toInsert: [BackendHabit] = []
        var toDelete: [Habit] = []

        for remoteHabit in remote {
            if let localHabit = localByBID[remoteHabit.id] {
                toUpdate.append((localHabit, remoteHabit))
            } else {
                toInsert.append(remoteHabit)
            }
        }

        for localHabit in local {
            guard let bid = localHabit.backendId else { continue }  // unsynced — skip
            if remoteByID[bid] == nil {
                toDelete.append(localHabit)
            }
        }

        return ReconcileResult(toUpdate: toUpdate, toInsert: toInsert, toDelete: toDelete)
    }

    // MARK: - Outbox helpers

    /// Returns habits that need to be created on the server (no backendId yet,
    /// not already marked deleted).
    static func pendingCreates(in habits: [Habit]) -> [Habit] {
        habits.filter { $0.backendId == nil && $0.syncStatus != .deleted }
    }

    /// Returns habits that have failed a previous upload and can be retried.
    static func failedUploads(in habits: [Habit]) -> [Habit] {
        habits.filter { $0.syncStatus == .failed && $0.backendId != nil }
    }

    /// Returns habits with a backendId whose checks may be out of sync
    /// with the server (pending local toggle that completed).
    static func pendingCheckUpdates(in habits: [Habit]) -> [Habit] {
        habits.filter { $0.syncStatus == .pending && $0.backendId != nil }
    }
}
