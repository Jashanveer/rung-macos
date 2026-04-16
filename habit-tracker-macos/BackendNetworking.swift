import Foundation

enum RequestState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

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

private enum JWTTokenInspector {
    nonisolated static func expirationDate(for token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard
            let payloadData = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let exp = object["exp"] as? TimeInterval
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }
}

struct BackendAuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAtEpochSeconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case accessTokenExpiresAtEpochSeconds
        case token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decode(String.self, forKey: .token)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        accessTokenExpiresAtEpochSeconds = try container.decodeIfPresent(Int64.self, forKey: .accessTokenExpiresAtEpochSeconds)
    }
}

struct MatchStreamMessageReadEvent: Decodable {
    let matchId: Int64
    let userId: Int64
    let at: String
}

actor BackendAPIClient {
    private let baseURL = URL(string: "http://127.0.0.1:8080")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: BackendSession?

    init(initialSession: BackendSession?) {
        session = initialSession
    }

    func currentSession() -> BackendSession? {
        session
    }

    func clearSession() {
        session = nil
    }

    func login(username: String, password: String) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/login",
            method: "POST",
            body: LoginRequest(username: username, password: password)
        )
        let newSession = BackendSession.fromAuthTokens(tokens)
        session = newSession
        return newSession
    }

    func register(username: String, email: String, password: String, avatarURL: String) async throws -> BackendSession {
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/register",
            method: "POST",
            body: RegisterRequest(username: username, email: email, password: password, avatarUrl: avatarURL)
        )
        let newSession = BackendSession.fromAuthTokens(tokens)
        session = newSession
        return newSession
    }

    func refreshSession() async throws -> BackendSession {
        guard let refreshToken = session?.refreshToken, !refreshToken.isEmpty else {
            throw HabitBackendError.notAuthenticated
        }
        let tokens: BackendAuthTokens = try await request(
            path: "/api/auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: refreshToken)
        )
        let updated = BackendSession.fromAuthTokens(tokens)
        session = updated
        return updated
    }

    func authorizedRequest<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await authorizedRequest(path: path, method: method, bodyData: nil)
    }

    func authorizedRequest<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: RequestBody
    ) async throws -> Response {
        try await authorizedRequest(path: path, method: method, bodyData: encoder.encode(body))
    }

    func authorizedSSERequest(path: String, lastEventID: String?) async throws -> URLRequest {
        let token = try await validAccessToken()
        do {
            return try sseRequest(path: path, token: token, lastEventID: lastEventID)
        } catch HabitBackendError.notAuthenticated {
            _ = try await refreshSession()
            let refreshedToken = try await validAccessToken()
            return try sseRequest(path: path, token: refreshedToken, lastEventID: lastEventID)
        }
    }

    private func authorizedRequest<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        let token = try await validAccessToken()
        do {
            return try await request(path: path, method: method, token: token, bodyData: bodyData)
        } catch HabitBackendError.notAuthenticated {
            _ = try await refreshSession()
            let refreshedToken = try await validAccessToken()
            return try await request(path: path, method: method, token: refreshedToken, bodyData: bodyData)
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else {
            throw HabitBackendError.notAuthenticated
        }
        if current.isAccessTokenExpired {
            _ = try await refreshSession()
            guard let refreshed = session else {
                throw HabitBackendError.notAuthenticated
            }
            return refreshed.accessToken
        }
        return current.accessToken
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        token: String? = nil
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: nil)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        token: String? = nil,
        body: RequestBody
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: encoder.encode(body))
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HabitBackendError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HabitBackendError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw HabitBackendError.notAuthenticated
                }
                let message = (try? decoder.decode(ApiErrorResponse.self, from: data).message)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw HabitBackendError.server(message)
            }

            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }

            return try decoder.decode(Response.self, from: data)
        } catch let error as HabitBackendError {
            throw error
        } catch {
            throw HabitBackendError.network(error.localizedDescription)
        }
    }

    private func sseRequest(path: String, token: String, lastEventID: String?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HabitBackendError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let lastEventID, !lastEventID.isEmpty {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }
        return request
    }

    private struct LoginRequest: Encodable {
        let username: String
        let password: String
    }

    private struct RegisterRequest: Encodable {
        let username: String
        let email: String
        let password: String
        let avatarUrl: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct ApiErrorResponse: Decodable {
        let message: String
    }

    private struct EmptyResponse: Decodable {}
}

struct AuthRepository {
    let client: BackendAPIClient

    func signIn(username: String, password: String) async throws -> BackendSession {
        try await client.login(username: username, password: password)
    }

    func register(username: String, email: String, password: String, avatarURL: String) async throws -> BackendSession {
        try await client.register(username: username, email: email, password: password, avatarURL: avatarURL)
    }
}

struct HabitRepository {
    let client: BackendAPIClient

    func listHabits() async throws -> [BackendHabit] {
        try await client.authorizedRequest(path: "/api/habits", method: "GET")
    }

    func createHabit(title: String) async throws -> BackendHabit {
        try await client.authorizedRequest(
            path: "/api/habits",
            method: "POST",
            body: HabitCreateRequest(title: title)
        )
    }

    func setCheck(habitID: Int64, dateKey: String, done: Bool) async throws -> BackendHabit {
        try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/checks/\(dateKey)",
            method: "PUT",
            body: CheckUpdateRequest(done: done)
        )
    }

    func deleteHabit(habitID: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)",
            method: "DELETE"
        )
    }

    private struct HabitCreateRequest: Encodable {
        let title: String
    }

    private struct CheckUpdateRequest: Encodable {
        let done: Bool
    }

    private struct EmptyResponse: Decodable {}
}

struct DeviceRepository {
    let client: BackendAPIClient

    func registerToken(_ token: String, platform: String) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/devices/token",
            method: "POST",
            body: DeviceTokenRequest(token: token, platform: platform)
        )
    }

    private struct DeviceTokenRequest: Encodable {
        let token: String
        let platform: String
    }

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
            path: "/api/accountability/matches/\(matchId)/messages",
            method: "POST",
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
            path: "/api/accountability/matches/\(matchId)/read",
            method: "POST"
        )
    }

    private struct MentorshipMessageRequest: Encodable {
        let message: String
    }

    private struct EmptyResponse: Decodable {}
}

enum HabitBackendError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Session expired. Sign in again to sync with the backend."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .server(let message):
            return message
        case .network(let message):
            return "Could not reach localhost:8080. \(message)"
        }
    }
}
