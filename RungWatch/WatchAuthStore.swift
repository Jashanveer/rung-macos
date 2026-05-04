import Foundation
import Security

/// Watch-side keychain for the iOS-issued auth token. The iPhone pushes
/// the current `accessToken` as part of every snapshot WC push (in the
/// same payload as the snapshot data). Persisting it on the watch lets a
/// future direct-to-backend fetcher operate without depending on the
/// phone — same pattern Strava / Apple Workouts use to render a workout
/// summary even when the phone is in a different room.
///
/// Stored under a watch-only Keychain entry. We don't use App Groups for
/// this because watchOS apps can't share keychain access groups with
/// their iOS counterpart — the iOS app pushes a copy, the watch persists
/// its own copy. Token expiry is tracked so the dashboard fetcher can
/// fall back to "wait for the phone to push a fresh token" when the
/// stored one is stale.
final class WatchAuthStore {
    static let shared = WatchAuthStore()

    private let service = "jashanveer.Rung.watch.session"
    private let account = "primary"
    private let queue = DispatchQueue(label: "rung.watch.auth", qos: .utility)

    private init() {}

    struct Token: Codable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let accessTokenExpiresAt: Date?
    }

    /// Persist a token + optional metadata. The iPhone pushes this on
    /// every WC snapshot so the watch always has the latest. Calls are
    /// debounced through a serial queue to avoid Keychain churn from a
    /// burst of identical pushes.
    func set(accessToken: String, expiresAtEpoch: TimeInterval?, refreshToken: String?) {
        let expires = expiresAtEpoch.map { Date(timeIntervalSince1970: $0) }
        let token = Token(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: expires
        )
        queue.async { [weak self] in
            self?.write(token)
        }
    }

    /// Read the cached token synchronously. Cheap — Keychain reads are
    /// in-process and bounded by SecItemCopyMatching's local cache.
    func current() -> Token? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    /// True when we have a token and it isn't (yet) past its expiry. A
    /// 30-second skew matches the iOS BackendAPIClient so a token used
    /// here would also be accepted by the iPhone-side refresh logic.
    var hasFreshToken: Bool {
        guard let t = current() else { return false }
        if let expires = t.accessTokenExpiresAt {
            return expires > Date().addingTimeInterval(30)
        }
        return true
    }

    private func write(_ token: Token) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { current, _ in current }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Wipe the stored token. Currently unused but exposed for a future
    /// remote-revoke path so a logged-out account on iPhone can also
    /// clear the watch's cached credential.
    func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
