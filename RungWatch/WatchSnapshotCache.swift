import Foundation

/// Persistent cache for the most recently received `WatchSnapshot`.
///
/// Watch cold-launch is the worst offender for the "Open Rung on iPhone"
/// stall — `WCSession` activation can take 5–60 s when the phone is in a
/// pocket or in another room, and the user shouldn't be staring at an
/// empty screen the whole time. Caching the last good payload to the
/// watch's own UserDefaults turns cold launch into instant first-paint:
/// the previous snapshot renders straight away, then `WCSession` (or
/// the backend, when the watch wires that path up next) fills in any
/// updates as they arrive.
enum WatchSnapshotCache {
    private static let key = "WatchSnapshotCache.v1"

    /// Save the latest decoded snapshot. Idempotent — re-saving the same
    /// snapshot is a no-op cost. Errors are swallowed (the cache is a
    /// best-effort optimisation, never a source of correctness).
    static func save(_ snapshot: WatchSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Read the cached snapshot if any. Returns nil for a brand-new
    /// install or after a sign-out (which clears the cache via `clear`).
    static func load() -> WatchSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    /// Wipe the cache. Currently unused but exposed for a future
    /// sign-out path so a previous user's data isn't ghost-rendered
    /// after the watch handshakes with a re-signed-in iPhone.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
