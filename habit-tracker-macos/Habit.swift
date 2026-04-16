import Foundation
import SwiftData

/// Tracks whether a local habit record reflects the server state.
/// Stored as a String raw value so SwiftData can persist it directly.
enum SyncStatus: String, Codable {
    /// Local record matches the last known server state.
    case synced
    /// A local change (toggle, create, title edit) hasn't been uploaded yet.
    case pending
    /// The last upload attempt failed; the app will retry on the next sync.
    case failed
    /// Marked for server deletion but the DELETE hasn't been confirmed yet.
    case deleted
}

@Model
final class Habit {
    var title: String
    var createdAt: Date
    var completedDayKeys: [String]
    var backendId: Int64?
    /// Wall-clock time of the last local modification; used for conflict detection.
    var updatedAt: Date
    /// Outbox state — never `.synced` until the server confirms the write.
    var syncStatus: SyncStatus

    init(
        title: String,
        createdAt: Date = Date(),
        completedDayKeys: [String] = [],
        backendId: Int64? = nil,
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending
    ) {
        self.title = title
        self.createdAt = createdAt
        self.completedDayKeys = completedDayKeys
        self.backendId = backendId
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
    }
}
