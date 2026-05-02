import Foundation

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

