import Foundation

enum BackendEnvironment {
    // Resolution order, highest priority first:
    //   1. Launch argument `-BackendBaseURL <url>`.
    //      UserDefaults.standard auto-binds command-line args via the
    //      NSArgumentDomain. Toggle in Xcode → Edit Scheme → Run →
    //      Arguments → Arguments Passed On Launch. No rebuild required —
    //      just stop and ⌘R after toggling the checkbox.
    //   2. `BackendBaseURL` from Info.plist (the build-time default).
    //   3. Hard-coded Fly.io dev backend, so Previews, unit tests, and any
    //      build whose Info.plist key isn't wired still reach a server.
    nonisolated static let baseURL: URL = {
        let fallback = URL(string: "https://rung-backend-dev.fly.dev")!

        if let arg = UserDefaults.standard.string(forKey: "BackendBaseURL"),
           case let trimmed = arg.trimmingCharacters(in: .whitespaces),
           !trimmed.isEmpty,
           let url = URL(string: trimmed) {
            return url
        }

        if let raw = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           case let trimmed = raw.trimmingCharacters(in: .whitespaces),
           !trimmed.isEmpty,
           let url = URL(string: trimmed) {
            return url
        }

        return fallback
    }()

    nonisolated static var displayHost: String {
        guard let host = baseURL.host else { return baseURL.absoluteString }
        if let port = baseURL.port {
            return "\(host):\(port)"
        }
        return host
    }
}

// MARK: - RequestState

enum RequestState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failure(let msg) = self { return msg }
        return nil
    }
}

// MARK: - RetryPolicy

/// Exponential-backoff retry for transient network errors.
/// Server errors (4xx/5xx) and auth errors are never retried.
struct RetryPolicy {
    /// Maximum number of attempts (including the first try).
    let maxAttempts: Int
    /// Base delay in seconds; doubles each retry.
    let baseDelay: TimeInterval
    /// Upper bound on the computed delay.
    let maxDelay: TimeInterval

    nonisolated static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8)
    nonisolated static let none      = RetryPolicy(maxAttempts: 1, baseDelay: 0,   maxDelay: 0)

    /// Delay (seconds) before attempt `attempt` (0-indexed).
    func delay(for attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
    }
}

// MARK: - ResponseCache

/// Thread-safe, in-memory TTL cache for dashboard and habit list responses.
/// Invalidated on any write that mutates the cached resource.
actor ResponseCache {
    private struct Entry<T> {
        let value: T
        let expiresAt: Date
    }

    private var habits: Entry<[BackendHabit]>?
    private var dashboard: Entry<AccountabilityDashboard>?

    // MARK: Habits (TTL: 5 s)
    //
    // Long-lived habit caches were causing a real cross-device-sync bug:
    // when the SSE event fired and the receiver ran a fresh sync, the
    // sync would happily return a 30-120-second-stale snapshot from the
    // cache and the new habit would never land. Five seconds is short
    // enough that the polling fallback in ContentView always sees fresh
    // data, but still long enough to coalesce the burst of refreshes
    // SwiftUI scenes emit on launch.

    func cachedHabits() -> [BackendHabit]? {
        guard let e = habits, e.expiresAt > Date() else { return nil }
        return e.value
    }

    func cacheHabits(_ value: [BackendHabit], ttl: TimeInterval = 5) {
        habits = Entry(value: value, expiresAt: Date(timeIntervalSinceNow: ttl))
    }

    func invalidateHabits() { habits = nil }

    // MARK: Dashboard (TTL: 60 s)

    func cachedDashboard() -> AccountabilityDashboard? {
        guard let e = dashboard, e.expiresAt > Date() else { return nil }
        return e.value
    }

    func cacheDashboard(_ value: AccountabilityDashboard, ttl: TimeInterval = 60) {
        dashboard = Entry(value: value, expiresAt: Date(timeIntervalSinceNow: ttl))
    }

    func invalidateDashboard() { dashboard = nil }

    func invalidateAll() {
        habits    = nil
        dashboard = nil
    }
}

// MARK: - BackendSession

struct BackendSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAt: Date
    /// Carried through from the auth response — true only when the
    /// session was just minted via a fresh Apple sign-up. Consumed once
    /// by the client to gate the post-Apple profile-setup screen, then
    /// effectively ignored for the rest of the session lifecycle.
    var isNewUser: Bool = false
    /// V15 server-side `profile_setup_completed`, surfaced on the auth
    /// response. nil from older backends — store handles that case via
    /// the UserDefaults primer + /me reconcile fallback.
    var profileSetupCompleted: Bool? = nil

    nonisolated var isAccessTokenExpired: Bool {
        accessTokenExpiresAt <= Date().addingTimeInterval(30)
    }

    nonisolated static func fromAuthTokens(_ tokens: BackendAuthTokens) -> BackendSession {
        let expiresAt = tokens.accessTokenExpiresAtEpochSeconds
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date(timeIntervalSinceNow: 120)
        return BackendSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            accessTokenExpiresAt: expiresAt,
            isNewUser: tokens.isNewUser,
            profileSetupCompleted: tokens.profileSetupCompleted
        )
    }

    nonisolated static func fromLegacyToken(_ token: String) -> BackendSession {
        BackendSession(
            accessToken: token,
            refreshToken: nil,
            accessTokenExpiresAt: JWTTokenInspector.expirationDate(for: token) ?? Date(timeIntervalSinceNow: 120),
            isNewUser: false
        )
    }
}

// MARK: - JWTTokenInspector (private)

private enum JWTTokenInspector {
    nonisolated static func expirationDate(for token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard
            let payloadData = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let exp = object["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - BackendAuthTokens

/// Mirrors the backend's `ParseFrequencyResponse` DTO. `didMatch=false`
/// means the LLM couldn't extract a cadence — clients should leave the
/// user's input untouched in that case.
struct ParseFrequencyResult: Decodable {
    let cleanedTitle: String
    let weeklyTarget: Int?
    let didMatch: Bool
}

struct BackendAuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAtEpochSeconds: Int64?
    /// True only on the first-time Sign in with Apple path. Drives the
    /// post-Apple profile-setup screen (username + avatar) before the
    /// user lands on the dashboard. Default false so password
    /// register/login / refresh stay unchanged.
    let isNewUser: Bool
    /// V15 server-side flag, mirrored on every auth response. nil for
    /// older backends — clients fall back to the existing UserDefaults
    /// primer + /me reconcile path. Otherwise the client gates the
    /// profile-setup overlay synchronously off this value, so a user
    /// who quit mid-setup re-lands on the setup screen the moment the
    /// next sign-in completes (no dashboard flash).
    let profileSetupCompleted: Bool?

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, accessTokenExpiresAtEpochSeconds, token, isNewUser, profileSetupCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
            ?? c.decode(String.self, forKey: .token)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        accessTokenExpiresAtEpochSeconds = try c.decodeIfPresent(Int64.self, forKey: .accessTokenExpiresAtEpochSeconds)
        isNewUser = try c.decodeIfPresent(Bool.self, forKey: .isNewUser) ?? false
        profileSetupCompleted = try c.decodeIfPresent(Bool.self, forKey: .profileSetupCompleted)
    }
}

// MARK: - MatchStreamMessageReadEvent

struct MatchStreamMessageReadEvent: Decodable {
    let matchId: Int64
    let userId: Int64
    let at: String
}

// MARK: - UserPreferences

/// Mirror of the `/api/users/me/preferences` payload. Today only the weekly
/// report email is wired up; new toggles get added as fields, not flag maps,
/// so the client stays strictly typed.
struct UserPreferences: Codable, Equatable {
    let emailOptIn: Bool
}

// MARK: - ProfileStatus

/// Slice of the `/api/me` response the client actually consumes —
/// just the V15 `profileSetupCompleted` flag used to decide whether to
/// re-show `AppleProfileSetupView` on cold launch.
struct ProfileStatus {
    let profileSetupCompleted: Bool
}

