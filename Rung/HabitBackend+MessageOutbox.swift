import Foundation
import Combine

/// One queued mentor message that the user wrote while offline. The
/// outbox persists these to UserDefaults so they survive app restarts
/// and the relaunch flow drains them as soon as connectivity returns.
struct OutboundMentorMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let matchId: Int64
    let body: String
    let queuedAt: Date
    var sendAttempts: Int
}

extension HabitBackendStore {

    /// UserDefaults key for the persisted message outbox. Versioned so
    /// a future schema change (e.g., per-attachment metadata) can be
    /// migrated without conflicting with already-queued entries.
    static let mentorMessageOutboxKey = "rung.mentorMessageOutbox.v1"

    // MARK: - Public API

    /// Append a message to the outbox. Persists to disk synchronously
    /// so a process kill between enqueue and flush doesn't lose work.
    @MainActor
    func enqueueOutboundMentorMessage(matchId: Int64, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = OutboundMentorMessage(
            id: UUID(),
            matchId: matchId,
            body: trimmed,
            queuedAt: Date(),
            sendAttempts: 0
        )
        var queue = outboundMentorMessages[matchId] ?? []
        queue.append(entry)
        outboundMentorMessages[matchId] = queue
        persistOutboundMentorMessages()
    }

    /// Drain the outbox once connectivity is back. Sends each message
    /// in queued order so the recipient sees the user's actual sequence
    /// rather than a network-jittered shuffle. Failures stay in the
    /// outbox; `NetworkMonitor` retriggers this on the next online flip.
    @MainActor
    func flushMentorMessageOutbox() async {
        guard token != nil else { return }
        let allEntries = outboundMentorMessages
            .values
            .flatMap { $0 }
            .sorted { $0.queuedAt < $1.queuedAt }
        guard !allEntries.isEmpty else { return }

        for entry in allEntries {
            // The repository call may block briefly; the in-memory
            // queue mutation must happen on the main actor before
            // each send so the UI's "pending" pill clears in real time.
            do {
                let value = try await accountabilityRepository.sendMenteeMessage(
                    matchId: entry.matchId,
                    message: entry.body
                )
                await syncSessionFromClient()
                await responseCache.invalidateDashboard()
                applyDashboardUpdate(value)
                removeOutboundMentorMessage(id: entry.id, matchId: entry.matchId)
            } catch HabitBackendError.network {
                // Still offline — leave the rest of the queue intact;
                // the next isOnline flip will retry.
                return
            } catch {
                // Server rejected (4xx / 5xx). Bump the attempt count
                // but don't drop yet — give the user a chance to see a
                // failure pill rather than silently losing the message.
                bumpOutboundMentorMessageAttempts(id: entry.id, matchId: entry.matchId)
                if outboundAttemptsExceeded(id: entry.id, matchId: entry.matchId) {
                    removeOutboundMentorMessage(id: entry.id, matchId: entry.matchId)
                }
            }
        }
    }

    /// Restore queued messages on cold launch. Called from
    /// `HabitBackendStore.init` so the published map is hydrated before
    /// any view tries to render.
    @MainActor
    func loadOutboundMentorMessagesFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.mentorMessageOutboxKey),
              let decoded = try? JSONDecoder().decode([OutboundMentorMessage].self, from: data)
        else { return }
        var grouped: [Int64: [OutboundMentorMessage]] = [:]
        for entry in decoded {
            grouped[entry.matchId, default: []].append(entry)
        }
        for (matchId, var entries) in grouped {
            entries.sort { $0.queuedAt < $1.queuedAt }
            grouped[matchId] = entries
        }
        outboundMentorMessages = grouped
    }

    // MARK: - Private helpers

    @MainActor
    private func removeOutboundMentorMessage(id: UUID, matchId: Int64) {
        guard var queue = outboundMentorMessages[matchId] else { return }
        queue.removeAll { $0.id == id }
        if queue.isEmpty {
            outboundMentorMessages.removeValue(forKey: matchId)
        } else {
            outboundMentorMessages[matchId] = queue
        }
        persistOutboundMentorMessages()
    }

    @MainActor
    private func bumpOutboundMentorMessageAttempts(id: UUID, matchId: Int64) {
        guard var queue = outboundMentorMessages[matchId] else { return }
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].sendAttempts += 1
        outboundMentorMessages[matchId] = queue
        persistOutboundMentorMessages()
    }

    @MainActor
    private func outboundAttemptsExceeded(id: UUID, matchId: Int64) -> Bool {
        guard let queue = outboundMentorMessages[matchId],
              let entry = queue.first(where: { $0.id == id }) else { return true }
        return entry.sendAttempts >= 5
    }

    @MainActor
    private func persistOutboundMentorMessages() {
        let flat = outboundMentorMessages.values.flatMap { $0 }
        guard let data = try? JSONEncoder().encode(flat) else { return }
        UserDefaults.standard.set(data, forKey: Self.mentorMessageOutboxKey)
    }
}
