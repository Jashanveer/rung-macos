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

// MARK: - BackendAPIClient

actor BackendAPIClient {
    private let baseURL = BackendEnvironment.baseURL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: BackendSession?
    let retryPolicy: RetryPolicy
    /// Monotonic counter that increments on every session boundary
    /// (login, register, Apple sign-in, refresh-success, clearSession).
    /// Used by the session-invalidated notification to defeat a TOCTOU
    /// race: a delayed 401 from a request issued under session A can
    /// arrive AFTER the user signs back in as session B; without an
    /// epoch the handler would kick them out of session B. The handler
    /// compares the notification's epoch to the current epoch and drops
    /// the notification if the epoch advanced in the meantime.
    private var sessionEpoch: UInt = 0

    init(initialSession: BackendSession?, retryPolicy: RetryPolicy = .default) {
        session = initialSession
        self.retryPolicy = retryPolicy
        if initialSession != nil { sessionEpoch &+= 1 }
    }

    func currentSession() -> BackendSession? { session }
    func currentEpoch() -> UInt { sessionEpoch }
    func clearSession() {
        session = nil
        sessionEpoch &+= 1
    }

    // MARK: Auth

    func login(username: String, password: String) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/login", method: "POST",
            body: LoginRequest(username: username, password: password)
        )
        let s = BackendSession.fromAuthTokens(tokens)
        session = s
        sessionEpoch &+= 1
        return s
    }

    /// Sign in with Apple — exchanges Apple's identity token for Rung's
    /// own JWT pair. The backend verifies the token against Apple's JWKS,
    /// then either looks up the linked account or provisions a new one
    /// from the embedded email (only sent on the first authorization).
    func appleLogin(identityToken: String, displayName: String?) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/apple", method: "POST",
            body: AppleLoginRequest(identityToken: identityToken, displayName: displayName)
        )
        let s = BackendSession.fromAuthTokens(tokens)
        session = s
        sessionEpoch &+= 1
        return s
    }

    /// Live availability probe used by the profile-setup screen so users
    /// see "username taken" inline rather than only on submit.
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let response: UsernameAvailabilityResponse = try await authorizedRequest(
            path: "/api/users/me/username-available?username=\(encoded)",
            method: "GET"
        )
        return response.available
    }

    /// Fetches the server-side `MeResponse` so the client can read the
    /// V15 `profileSetupCompleted` flag on cold launch and re-show the
    /// `AppleProfileSetupView` if the user quit mid-setup. Treats a
    /// missing field as "true" so a pre-V15 server keeps working.
    func fetchMe() async throws -> ProfileStatus {
        let r: MeResponse = try await authorizedRequest(path: "/api/me", method: "GET")
        return ProfileStatus(profileSetupCompleted: r.profileSetupCompleted ?? true)
    }

    /// One-time post-Apple-signup setup — submits the chosen username,
    /// avatar URL, and (for Apple sign-ups where Apple didn't return
    /// fullName) the user's typed display name. Backend persists,
    /// returns the refreshed MeResponse the caller doesn't need.
    func setupProfile(username: String, avatarURL: String, displayName: String?) async throws {
        let _: MeResponse = try await authorizedRequest(
            path: "/api/users/me/setup-profile", method: "POST",
            body: ProfileSetupRequest(
                username: username,
                avatarUrl: avatarURL,
                displayName: displayName
            )
        )
    }

    func requestEmailVerification(email: String) async throws {
        let _: MessageResponse = try await request(
            path: "/api/auth/email-verification", method: "POST",
            body: EmailVerificationRequest(email: email)
        )
    }

    func register(
        username: String,
        email: String,
        password: String,
        avatarURL: String,
        verificationCode: String
    ) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/register", method: "POST",
            body: RegisterRequest(
                username: username,
                email: email,
                password: password,
                avatarUrl: avatarURL,
                verificationCode: verificationCode
            )
        )
        let s = BackendSession.fromAuthTokens(tokens)
        session = s
        sessionEpoch &+= 1
        return s
    }

    func refreshSession() async throws -> BackendSession {
        guard let rt = session?.refreshToken, !rt.isEmpty else {
            await Self.notifySessionInvalidated(epoch: sessionEpoch)
            throw HabitBackendError.notAuthenticated
        }
        do {
            let tokens: BackendAuthTokens = try await request(
                path: "/api/auth/refresh", method: "POST",
                body: RefreshRequest(refreshToken: rt)
            )
            let s = BackendSession.fromAuthTokens(tokens)
            session = s
            sessionEpoch &+= 1
            return s
        } catch HabitBackendError.notAuthenticated {
            // The refresh token itself is bad — the only recovery is for the
            // user to sign in again. Drop the local session and broadcast so
            // `HabitBackendStore` can sign out automatically. The epoch we
            // emit is the one that was current at notification time; if the
            // user has already re-authenticated by the time the handler runs
            // the apiClient's epoch will be higher and the handler drops
            // this notice instead of kicking them back out.
            session = nil
            sessionEpoch &+= 1
            await Self.notifySessionInvalidated(epoch: sessionEpoch)
            throw HabitBackendError.notAuthenticated
        } catch HabitBackendError.server(let msg) where msg.lowercased().contains("unauth") || msg.lowercased().contains("invalid") {
            session = nil
            sessionEpoch &+= 1
            await Self.notifySessionInvalidated(epoch: sessionEpoch)
            throw HabitBackendError.notAuthenticated
        }
    }

    /// Posted whenever the refresh token can't produce a valid session, so the
    /// store can drop local state and send the user back to the sign-in screen.
    static let sessionInvalidatedNotification = Notification.Name("BackendAPIClient.sessionInvalidated")
    /// Key for the `sessionEpoch` value attached to the userInfo dictionary.
    /// The handler reads this and compares it against the current API client
    /// epoch — if older, the notification is for a stale prior session and
    /// the handler drops it without signing the (now re-authenticated) user
    /// out of their valid newer session.
    static let sessionInvalidatedEpochKey = "epoch"

    private static func notifySessionInvalidated(epoch: UInt) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: sessionInvalidatedNotification,
                object: nil,
                userInfo: [sessionInvalidatedEpochKey: epoch]
            )
        }
    }

    /// Invalidates the refresh token server-side. Best-effort — never throws.
    func logout() async {
        guard let rt = session?.refreshToken, !rt.isEmpty else { return }
        _ = try? await request(
            path: "/api/auth/logout", method: "POST",
            body: LogoutRequest(refreshToken: rt)
        ) as EmptyResponse
    }

    // MARK: Authorized requests (with retry for network errors)

    func authorizedRequest<Response: Decodable>(path: String, method: String) async throws -> Response {
        try await authorizedRequest(path: path, method: method, bodyData: nil)
    }

    func authorizedRequest<RequestBody: Encodable, Response: Decodable>(
        path: String, method: String, body: RequestBody
    ) async throws -> Response {
        try await authorizedRequest(path: path, method: method, bodyData: encoder.encode(body))
    }

    func authorizedSSERequest(path: String, lastEventID: String?) async throws -> URLRequest {
        let token = try await validAccessToken()
        do {
            return try sseRequest(path: path, token: token, lastEventID: lastEventID)
        } catch HabitBackendError.notAuthenticated {
            _ = try await refreshSession()
            return try sseRequest(path: path, token: try await validAccessToken(), lastEventID: lastEventID)
        }
    }

    private func authorizedRequest<Response: Decodable>(
        path: String, method: String, bodyData: Data?
    ) async throws -> Response {
        var lastNetworkError: Error = HabitBackendError.network("Unknown")

        for attempt in 0..<retryPolicy.maxAttempts {
            // Back off before retries (not before the first attempt)
            if attempt > 0 {
                try await Task.sleep(for: .seconds(retryPolicy.delay(for: attempt)))
            }

            do {
                let token = try await validAccessToken()
                do {
                    return try await request(path: path, method: method, token: token, bodyData: bodyData)
                } catch HabitBackendError.notAuthenticated {
                    // Auth error — refresh once and retry immediately (not counted as a network retry)
                    _ = try await refreshSession()
                    let refreshed = try await validAccessToken()
                    return try await request(path: path, method: method, token: refreshed, bodyData: bodyData)
                }
            } catch HabitBackendError.network(let msg) {
                lastNetworkError = HabitBackendError.network(msg)
                // fall through to next attempt
            } catch {
                throw error  // server/decode/auth errors — do not retry
            }
        }

        throw lastNetworkError
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw HabitBackendError.notAuthenticated }
        if current.isAccessTokenExpired {
            _ = try await refreshSession()
            guard let refreshed = session else { throw HabitBackendError.notAuthenticated }
            return refreshed.accessToken
        }
        return current.accessToken
    }

    // MARK: Raw requests

    private func request<Response: Decodable>(path: String, method: String, token: String? = nil) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: nil)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        path: String, method: String, token: String? = nil, body: RequestBody
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: encoder.encode(body))
    }

    private func request<Response: Decodable>(
        path: String, method: String, token: String?, bodyData: Data?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HabitBackendError.invalidResponse
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw HabitBackendError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw HabitBackendError.notAuthenticated
                }
                let msg = (try? decoder.decode(ApiErrorResponse.self, from: data).message)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                if http.statusCode == 404 {
                    throw HabitBackendError.notFound(msg)
                }
                throw HabitBackendError.server(msg)
            }
            if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
                return empty
            }
            // 204 No Content (or any 2xx with empty body) — fall back to a
            // synthesised "{}" payload so callers that pass their own empty
            // Decodable type still succeed instead of failing with
            // `invalidResponse`. Without this, every caller that defines its
            // own `EmptyResponse` to discard the body slips past the metatype
            // check above and trips JSON decode on zero bytes.
            if data.isEmpty || http.statusCode == 204 {
                if let synthesised = try? decoder.decode(Response.self, from: Data("{}".utf8)) {
                    return synthesised
                }
            }
            return try decoder.decode(Response.self, from: data)
        } catch let error as HabitBackendError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                throw HabitBackendError.network(urlError.localizedDescription)
            }
            if error is DecodingError {
                throw HabitBackendError.invalidResponse
            }
            throw HabitBackendError.invalidResponse
        }
    }

    private func sseRequest(path: String, token: String, lastEventID: String?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HabitBackendError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 0
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache",          forHTTPHeaderField: "Cache-Control")
        req.setValue("Bearer \(token)",   forHTTPHeaderField: "Authorization")
        if let id = lastEventID, !id.isEmpty { req.setValue(id, forHTTPHeaderField: "Last-Event-ID") }
        return req
    }

    // MARK: Private DTOs

    private struct LoginRequest:    Encodable { let username: String; let password: String }
    private struct EmailVerificationRequest: Encodable { let email: String }
    private struct RegisterRequest: Encodable { let username, email, password, avatarUrl, verificationCode: String }
    private struct RefreshRequest:  Encodable { let refreshToken: String }
    private struct AppleLoginRequest: Encodable { let identityToken: String; let displayName: String? }
    private struct ProfileSetupRequest: Encodable { let username: String; let avatarUrl: String; let displayName: String? }
    private struct UsernameAvailabilityResponse: Decodable { let available: Bool }
    /// Mirror of `/api/me` and the response of `/api/users/me/setup-profile`.
    /// `profileSetupCompleted` is the V15 server-side flag — optional in the
    /// decoder so that talking to a pre-V15 server (during a partial
    /// rollout) doesn't fail decoding; the caller treats `nil` as "true"
    /// because legacy users had already finished setup.
    private struct MeResponse: Decodable {
        let userId: Int64?
        let email: String?
        let username: String?
        let profileSetupCompleted: Bool?
    }
    private struct LogoutRequest:   Encodable { let refreshToken: String }
    private struct MessageResponse: Decodable { let message: String }
    private struct ApiErrorResponse: Decodable { let message: String }
    private struct EmptyResponse: Decodable {}
}

// MARK: - Repositories

struct AuthRepository {
    let client: BackendAPIClient

    func signIn(username: String, password: String) async throws -> BackendSession {
        try await client.login(username: username, password: password)
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> BackendSession {
        try await client.appleLogin(identityToken: identityToken, displayName: displayName)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await client.isUsernameAvailable(username)
    }

    func fetchMe() async throws -> ProfileStatus {
        try await client.fetchMe()
    }

    func setupProfile(username: String, avatarURL: String, displayName: String?) async throws {
        try await client.setupProfile(username: username, avatarURL: avatarURL, displayName: displayName)
    }

    func requestEmailVerification(email: String) async throws {
        try await client.requestEmailVerification(email: email)
    }

    func register(
        username: String,
        email: String,
        password: String,
        avatarURL: String,
        verificationCode: String
    ) async throws -> BackendSession {
        try await client.register(
            username: username,
            email: email,
            password: password,
            avatarURL: avatarURL,
            verificationCode: verificationCode
        )
    }
}

struct HabitRepository {
    let client: BackendAPIClient

    func listHabits() async throws -> [BackendHabit] {
        let habits: [BackendHabit] = try await client.authorizedRequest(path: "/api/habits", method: "GET")
        return habits.map { habit in
            BackendHabit(
                id: habit.id,
                title: habit.title,
                checksByDate: habit.checksByDate,
                reminderWindow: habit.reminderWindow,
                entryType: .habit,
                createdAt: habit.createdAt
            )
        }
    }

    func listTasks() async throws -> [BackendHabit] {
        let tasks: [BackendHabit] = try await client.authorizedRequest(path: "/api/tasks", method: "GET")
        return tasks.map { task in
            BackendHabit(
                id: task.id,
                title: task.title,
                checksByDate: task.checksByDate,
                reminderWindow: nil,
                entryType: .task,
                createdAt: task.createdAt
            )
        }
    }

    func createHabit(
        title: String,
        reminderWindow: String?,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits",
            method: "POST",
            body: HabitWriteRequest(
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit,
            createdAt: habit.createdAt,
            canonicalKey: habit.canonicalKey,
            verificationTier: habit.verificationTier,
            verificationSource: habit.verificationSource,
            verificationParam: habit.verificationParam,
            weeklyTarget: habit.weeklyTarget
        )
    }

    /// LLM fallback for the dashboard's frequency parser. Called only when
    /// the local regex pass missed but the input contains hint keywords
    /// (numbers + "week" / "every" / "day"). Returns nil on any failure
    /// — caller falls back to the user's untouched input. Short timeout
    /// because the user is waiting on the confirmation card to appear.
    func parseHabitFrequency(text: String) async throws -> ParseFrequencyResult {
        let response: ParseFrequencyResult = try await client.authorizedRequest(
            path: "/api/habits/parse-frequency",
            method: "POST",
            body: ParseFrequencyRequestBody(text: text)
        )
        return response
    }

    private struct ParseFrequencyRequestBody: Encodable {
        let text: String
    }

    func createTask(title: String) async throws -> BackendHabit {
        let task: BackendHabit = try await client.authorizedRequest(
            path: "/api/tasks",
            method: "POST",
            body: TaskWriteRequest(title: title)
        )
        return BackendHabit(
            id: task.id,
            title: task.title,
            checksByDate: task.checksByDate,
            reminderWindow: nil,
            entryType: .task,
            createdAt: task.createdAt
        )
    }

    func updateHabit(
        habitID: Int64,
        title: String,
        reminderWindow: String?,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)",
            method: "PUT",
            body: HabitWriteRequest(
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit,
            createdAt: habit.createdAt,
            canonicalKey: habit.canonicalKey,
            verificationTier: habit.verificationTier,
            verificationSource: habit.verificationSource,
            verificationParam: habit.verificationParam,
            weeklyTarget: habit.weeklyTarget
        )
    }

    func updateTask(taskID: Int64, title: String) async throws -> BackendHabit {
        let task: BackendHabit = try await client.authorizedRequest(
            path: "/api/tasks/\(taskID)",
            method: "PUT",
            body: TaskWriteRequest(title: title)
        )
        return BackendHabit(
            id: task.id,
            title: task.title,
            checksByDate: task.checksByDate,
            reminderWindow: nil,
            entryType: .task,
            createdAt: task.createdAt
        )
    }

    func setCheck(
        habitID: Int64,
        dateKey: String,
        done: Bool,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        durationSeconds: Int? = nil
    ) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/checks/\(dateKey)",
            method: "PUT",
            body: CheckUpdateRequest(
                done: done,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                durationSeconds: durationSeconds
            )
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit,
            createdAt: habit.createdAt,
            canonicalKey: habit.canonicalKey,
            verificationTier: habit.verificationTier,
            verificationSource: habit.verificationSource,
            verificationParam: habit.verificationParam,
            weeklyTarget: habit.weeklyTarget
        )
    }

    func setTaskCheck(
        taskID: Int64,
        dateKey: String,
        done: Bool,
        durationSeconds: Int? = nil
    ) async throws -> BackendHabit {
        // Tasks never carry verification metadata — pass explicit nils to
        // keep the `CheckUpdateRequest` payload shape uniform.
        let task: BackendHabit = try await client.authorizedRequest(
            path: "/api/tasks/\(taskID)/checks/\(dateKey)",
            method: "PUT",
            body: CheckUpdateRequest(
                done: done,
                verificationTier: nil,
                verificationSource: nil,
                durationSeconds: durationSeconds
            )
        )
        return BackendHabit(
            id: task.id,
            title: task.title,
            checksByDate: task.checksByDate,
            reminderWindow: nil,
            entryType: .task,
            createdAt: task.createdAt
        )
    }

    func deleteHabit(habitID: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(path: "/api/habits/\(habitID)", method: "DELETE")
    }

    func deleteTask(taskID: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(path: "/api/tasks/\(taskID)", method: "DELETE")
    }

    private struct HabitWriteRequest: Encodable {
        let title: String
        let reminderWindow: String?
        let canonicalKey: String?
        let verificationTier: String?
        let verificationSource: String?
        let verificationParam: Double?
        let weeklyTarget: Int?
    }
    private struct TaskWriteRequest: Encodable { let title: String }
    private struct CheckUpdateRequest: Encodable {
        let done: Bool
        let verificationTier: String?
        let verificationSource: String?
        let durationSeconds: Int?
    }
    private struct EmptyResponse: Decodable {}
}

struct DeviceRepository {
    let client: BackendAPIClient

    func registerToken(_ token: String, platform: String) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/devices/token", method: "POST",
            body: DeviceTokenRequest(token: token, platform: platform)
        )
    }

    private struct DeviceTokenRequest: Encodable { let token: String; let platform: String }
    private struct EmptyResponse: Decodable {}
}

struct PreferencesRepository {
    let client: BackendAPIClient

    func get() async throws -> UserPreferences {
        try await client.authorizedRequest(path: "/api/users/me/preferences", method: "GET")
    }

    func update(emailOptIn: Bool) async throws -> UserPreferences {
        try await client.authorizedRequest(
            path: "/api/users/me/preferences", method: "PUT",
            body: PreferencesUpdateRequest(emailOptIn: emailOptIn)
        )
    }

    private struct PreferencesUpdateRequest: Encodable { let emailOptIn: Bool }
}

struct AccountabilityRepository {
    let client: BackendAPIClient

    func dashboard() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/dashboard", method: "GET")
    }

    func assignMentor() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/match", method: "POST")
    }

    func requestFriend(friendUserID: Int64) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/follows/\(friendUserID)", method: "POST")
    }

    func searchFriends(query: String) async throws -> [AccountabilityDashboard.FriendSummary] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await client.authorizedRequest(path: "/api/accountability/follows/search\(queryString)", method: "GET")
    }

    func sendMenteeMessage(matchId: Int64, message: String) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(
            path: "/api/accountability/matches/\(matchId)/messages", method: "POST",
            body: MentorshipMessageRequest(message: message)
        )
    }

    func streamRequest(matchId: Int64, lastEventID: String?) async throws -> URLRequest {
        try await client.authorizedSSERequest(
            path: "/api/accountability/matches/\(matchId)/stream",
            lastEventID: lastEventID
        )
    }

    /// Per-user SSE stream used for cross-device real-time habit sync.
    /// The backend publishes `habits.changed` every time this user writes
    /// a habit on any device; subscribers respond by re-running their
    /// normal sync pass so state converges across devices in seconds.
    /// `?platform=` lets the server log which devices are connected so
    /// "subscribers=2" diagnostics can distinguish iOS+macOS from two
    /// stale connections of the same client.
    func userStreamRequest(lastEventID: String?) async throws -> URLRequest {
        #if os(iOS)
        let platform = "ios"
        #else
        let platform = "macos"
        #endif
        return try await client.authorizedSSERequest(
            path: "/api/me/stream?platform=\(platform)",
            lastEventID: lastEventID
        )
    }

    func markMatchRead(matchId: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/accountability/matches/\(matchId)/read", method: "POST"
        )
    }

    func useStreakFreeze(dateKey: String) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(
            path: "/api/accountability/streak-freeze/use", method: "POST",
            body: StreakFreezeRequest(dateKey: dateKey)
        )
    }

    func undoStreakFreeze() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(
            path: "/api/accountability/streak-freeze/undo", method: "POST"
        )
    }

    func sendNudge(matchId: Int64) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/matches/\(matchId)/nudge", method: "POST")
    }

    private struct MentorshipMessageRequest: Encodable { let message: String }
    private struct StreakFreezeRequest: Encodable { let dateKey: String }
    private struct EmptyResponse: Decodable {}
}

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
