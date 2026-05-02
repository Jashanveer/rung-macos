import Foundation

// MARK: - Sleep snapshot

/// Cross-device sleep snapshot. iOS uploads what it computed locally
/// from HealthKit; macOS reads it back because HK isn't available on
/// native Mac apps. Mirrors the backend's `SleepSnapshotResponse` DTO.
struct BackendSleepSnapshot: Codable, Equatable {
    let sampleCount: Int
    let medianWakeMinutes: Int
    let medianBedMinutes: Int
    let averageDurationHours: Double
    let sleepDebtHours: Double
    let medianSleepMidpointMinutes: Int?
    let midpointIqrMinutes: Int
    let chronotypeStable: Bool
    /// Server-stamped — not sent on upload, decoded on read so the Mac
    /// can dim the readout when the iPhone hasn't synced lately.
    let updatedAt: Date?
}

struct SleepSnapshotRepository {
    let client: BackendAPIClient

    /// Push the current snapshot to the backend so other devices can read
    /// it. Idempotent: server stores one row per user, overwritten in place.
    @discardableResult
    func upload(_ snapshot: BackendSleepSnapshot) async throws -> BackendSleepSnapshot {
        try await client.authorizedRequest(
            path: "/api/sleep/snapshot",
            method: "POST",
            body: snapshot
        )
    }

    /// Fetch the most recent snapshot. Returns nil when the server has
    /// no row yet for this user (204 No Content).
    func fetch() async throws -> BackendSleepSnapshot? {
        do {
            let snap: BackendSleepSnapshot = try await client.authorizedRequest(
                path: "/api/sleep/snapshot",
                method: "GET"
            )
            return snap
        } catch HabitBackendError.invalidResponse {
            // 204 lands here — the decoder fails on an empty body. Treat
            // as "no snapshot yet" so the Mac shows its empty state.
            return nil
        }
    }
}

// MARK: - Error

enum HabitBackendError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)
    case network(String)
    /// Server returned 404 for a resource the client thought existed.
    /// Caller should treat this as "your local copy is stale" and trigger
    /// a reconcile — never surface the raw "habit not found" message to
    /// the user, since the right fix is to converge to server state, not
    /// nag them about a divergence the app can heal itself.
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Session expired. Sign in again to sync with the backend."
        case .invalidResponse:  return "The backend returned an invalid response."
        case .server(let m):    return m
        case .network(let m):   return "Could not reach \(BackendEnvironment.displayHost). \(m)"
        case .notFound(let m):  return m
        }
    }

    /// True when it makes sense to show a "Retry" button to the user.
    var isRetryable: Bool {
        if case .network = self { return true }
        return false
    }
}
