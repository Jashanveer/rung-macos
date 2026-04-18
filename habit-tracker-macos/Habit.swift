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

enum HabitEntryType: String, Codable, CaseIterable, Identifiable {
    case task
    case habit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task:
            return "Task"
        case .habit:
            return "Habit"
        }
    }

    var systemImage: String {
        switch self {
        case .task:
            return "checklist"
        case .habit:
            return "flame.fill"
        }
    }
}

@Model
final class Habit {
    var title: String
    @Attribute(originalName: "entryType")
    private var entryTypeRawValue: String?
    var createdAt: Date
    var completedDayKeys: [String]
    var backendId: Int64?
    /// Wall-clock time of the last local modification; used for conflict detection.
    var updatedAt: Date
    /// Outbox state — never `.synced` until the server confirms the write.
    var syncStatus: SyncStatus

    // MARK: - Pending check outbox
    // When the user toggles a habit and the upload hasn't been confirmed yet, these two
    // fields capture the exact operation. `flushOutbox` uses them to send the right
    // done/undone state rather than blindly re-pushing all completedDayKeys.
    // Both are nil when no pending check operation exists.

    /// The day key whose done-state is waiting to be uploaded to the server.
    var pendingCheckDayKey: String?
    /// The done value that should be sent for `pendingCheckDayKey`.
    var pendingCheckIsDone: Bool

    /// Raw value of `HabitReminderWindow`; nil means no time-window reminder.
    var reminderWindow: String?

    /// When true the habit is hidden from the dashboard and removed from sync.
    /// History is preserved locally so streaks remain intact.
    var isArchived: Bool

    /// Backward-compatible entry kind accessor.
    /// Older stores may contain missing/invalid values; those fall back to `.habit`.
    var entryType: HabitEntryType {
        get {
            HabitEntryType(rawValue: entryTypeRawValue ?? "") ?? .habit
        }
        set {
            entryTypeRawValue = newValue.rawValue
        }
    }

    init(
        title: String,
        entryType: HabitEntryType = .habit,
        createdAt: Date = Date(),
        completedDayKeys: [String] = [],
        backendId: Int64? = nil,
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending,
        pendingCheckDayKey: String? = nil,
        pendingCheckIsDone: Bool = false,
        reminderWindow: String? = nil,
        isArchived: Bool = false
    ) {
        self.title = title
        self.entryTypeRawValue = entryType.rawValue
        self.createdAt = createdAt
        self.completedDayKeys = completedDayKeys
        self.backendId = backendId
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
        self.pendingCheckDayKey = pendingCheckDayKey
        self.pendingCheckIsDone = pendingCheckIsDone
        self.reminderWindow = reminderWindow
        self.isArchived = isArchived
    }
}
