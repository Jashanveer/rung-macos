import Foundation

enum BackendEnvironment {
    nonisolated static let baseURL = URL(string: "http://127.0.0.1:8080")!

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

    // MARK: Habits (TTL: 120 s)

    func cachedHabits() -> [BackendHabit]? {
        guard let e = habits, e.expiresAt > Date() else { return nil }
        return e.value
    }

    func cacheHabits(_ value: [BackendHabit], ttl: TimeInterval = 120) {
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
            accessTokenExpiresAt: expiresAt
        )
    }

    nonisolated static func fromLegacyToken(_ token: String) -> BackendSession {
        BackendSession(
            accessToken: token,
            refreshToken: nil,
            accessTokenExpiresAt: JWTTokenInspector.expirationDate(for: token) ?? Date(timeIntervalSinceNow: 120)
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

struct BackendAuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAtEpochSeconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, accessTokenExpiresAtEpochSeconds, token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
            ?? c.decode(String.self, forKey: .token)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        accessTokenExpiresAtEpochSeconds = try c.decodeIfPresent(Int64.self, forKey: .accessTokenExpiresAtEpochSeconds)
    }
}

// MARK: - MatchStreamMessageReadEvent

struct MatchStreamMessageReadEvent: Decodable {
    let matchId: Int64
    let userId: Int64
    let at: String
}

// MARK: - BackendAPIClient

actor BackendAPIClient {
    private let baseURL = BackendEnvironment.baseURL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: BackendSession?
    let retryPolicy: RetryPolicy

    init(initialSession: BackendSession?, retryPolicy: RetryPolicy = .default) {
        session = initialSession
        self.retryPolicy = retryPolicy
    }

    func currentSession() -> BackendSession? { session }
    func clearSession() { session = nil }

    // MARK: Auth

    func login(username: String, password: String) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/login", method: "POST",
            body: LoginRequest(username: username, password: password)
        )
        let s = BackendSession.fromAuthTokens(tokens); session = s; return s
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
        let s = BackendSession.fromAuthTokens(tokens); session = s; return s
    }

    func refreshSession() async throws -> BackendSession {
        guard let rt = session?.refreshToken, !rt.isEmpty else {
            throw HabitBackendError.notAuthenticated
        }
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/refresh", method: "POST",
            body: RefreshRequest(refreshToken: rt)
        )
        let s = BackendSession.fromAuthTokens(tokens); session = s; return s
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
                throw HabitBackendError.server(msg)
            }
            if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
                return empty
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
                entryType: .habit
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
                entryType: .task
            )
        }
    }

    func createHabit(title: String, reminderWindow: String?) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits",
            method: "POST",
            body: HabitWriteRequest(title: title, reminderWindow: reminderWindow)
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit
        )
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
            entryType: .task
        )
    }

    func updateHabit(habitID: Int64, title: String, reminderWindow: String?) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)",
            method: "PUT",
            body: HabitWriteRequest(title: title, reminderWindow: reminderWindow)
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit
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
            entryType: .task
        )
    }

    func setCheck(habitID: Int64, dateKey: String, done: Bool) async throws -> BackendHabit {
        let habit: BackendHabit = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/checks/\(dateKey)",
            method: "PUT",
            body: CheckUpdateRequest(done: done)
        )
        return BackendHabit(
            id: habit.id,
            title: habit.title,
            checksByDate: habit.checksByDate,
            reminderWindow: habit.reminderWindow,
            entryType: .habit
        )
    }

    func setTaskCheck(taskID: Int64, dateKey: String, done: Bool) async throws -> BackendHabit {
        let task: BackendHabit = try await client.authorizedRequest(
            path: "/api/tasks/\(taskID)/checks/\(dateKey)",
            method: "PUT",
            body: CheckUpdateRequest(done: done)
        )
        return BackendHabit(
            id: task.id,
            title: task.title,
            checksByDate: task.checksByDate,
            reminderWindow: nil,
            entryType: .task
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
    }
    private struct TaskWriteRequest: Encodable { let title: String }
    private struct CheckUpdateRequest:  Encodable { let done: Bool }
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

struct AccountabilityRepository {
    let client: BackendAPIClient

    func dashboard() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/dashboard", method: "GET")
    }

    func assignMentor() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/match", method: "POST")
    }

    func requestFriend(friendUserID: Int64) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/friends/\(friendUserID)", method: "POST")
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

    func sendNudge(matchId: Int64) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/matches/\(matchId)/nudge", method: "POST")
    }

    private struct MentorshipMessageRequest: Encodable { let message: String }
    private struct StreakFreezeRequest: Encodable { let dateKey: String }
    private struct EmptyResponse: Decodable {}
}

// MARK: - Error

enum HabitBackendError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Session expired. Sign in again to sync with the backend."
        case .invalidResponse:  return "The backend returned an invalid response."
        case .server(let m):    return m
        case .network(let m):   return "Could not reach \(BackendEnvironment.displayHost). \(m)"
        }
    }

    /// True when it makes sense to show a "Retry" button to the user.
    var isRetryable: Bool {
        if case .network = self { return true }
        return false
    }
}
