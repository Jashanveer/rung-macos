import Foundation

/// Minimal backend client running entirely on the Apple Watch. Reads
/// the auth token persisted by `WatchAuthStore` (pushed from iOS over
/// WatchConnectivity at sign-in / refresh) and calls the Rung backend
/// directly so the watch never has to wait on a reachable iPhone.
///
/// Scope is intentionally narrow: this client only knows about the
/// `/api/watch/snapshot` endpoint. The iPhone owns the snapshot
/// construction; the watch just fetches the latest blob and the same
/// SwiftUI views that consume `WatchSession.snapshot` render off the
/// merged result. Token refresh isn't implemented here yet — when a
/// watch-side fetch returns 401 we surface the error and let the next
/// iPhone push refresh the token. Most users carry their phone often
/// enough that the existing token rotation handles this transparently.
struct WatchBackendClient {

    /// Backend base URL — same default as the iOS app's
    /// `BackendEnvironment` so a custom dev server can be set via
    /// the `BackendBaseURL` UserDefault on the watch's Settings.
    static let baseURL: URL = {
        if let arg = UserDefaults.standard.string(forKey: "BackendBaseURL"),
           case let trimmed = arg.trimmingCharacters(in: .whitespaces),
           !trimmed.isEmpty,
           let url = URL(string: trimmed) {
            return url
        }
        return URL(string: "https://rung-backend-dev.fly.dev")!
    }()

    /// Errors propagated up to `WatchBackendStore`. Mostly informational
    /// — the store decides whether to surface a user-visible message or
    /// fall back to the cached snapshot silently.
    enum Error: Swift.Error, LocalizedError {
        case noToken
        case unauthorized
        case noSnapshotYet
        case http(Int)
        case decode(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .noToken:        return "Open Rung on iPhone once to set up sync."
            case .unauthorized:   return "Sign in again on iPhone."
            case .noSnapshotYet:  return "Open Rung on iPhone once to populate the watch."
            case .http(let code): return "Network error (\(code))."
            case .decode:         return "Couldn't read the snapshot."
            case .transport:      return "Couldn't reach the server."
            }
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    /// Fetch the latest watch snapshot the iPhone uploaded. Returns the
    /// decoded `WatchSnapshot` (the same type the WC channel decodes
    /// into) plus the server-stamped freshness timestamp.
    ///
    /// On a 401 we transparently refresh the access token (using the
    /// stored refresh token) and retry once before propagating
    /// `.unauthorized`. This is the path that turns the watch into a
    /// genuinely standalone client — the user no longer has to open
    /// the iPhone after a token expiry to keep the watch live.
    func fetchSnapshot() async throws -> (snapshot: WatchSnapshot, updatedAt: Date) {
        // Pre-emptive refresh — when the token has under 5 min left we
        // refresh right away so a long-running fetch doesn't race the
        // expiry and waste a request on a guaranteed-401.
        await preemptivelyRefreshIfStale()
        do {
            return try await performSnapshotRequest()
        } catch Error.unauthorized {
            // Token rejected — try one refresh + retry. If that also
            // fails the user has to re-authenticate (rare path; the
            // refresh token usually outlives the access token by weeks).
            try await refreshAccessToken()
            return try await performSnapshotRequest()
        }
    }

    /// One-shot `/api/watch/snapshot` GET with the currently-stored
    /// access token. Pulled out of `fetchSnapshot` so the outer logic
    /// can call it twice — once with the original token, once after a
    /// refresh.
    private func performSnapshotRequest() async throws -> (snapshot: WatchSnapshot, updatedAt: Date) {
        guard let token = WatchAuthStore.shared.current()?.accessToken else {
            throw Error.noToken
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/watch/snapshot"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        switch http.statusCode {
        case 200:
            do {
                let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
                guard let payloadData = envelope.payload.data(using: .utf8) else {
                    throw Error.decode(NSError(domain: "WatchBackend", code: 1))
                }
                let snapshot = try decoder.decode(WatchSnapshot.self, from: payloadData)
                return (snapshot, envelope.updatedAt)
            } catch {
                throw Error.decode(error)
            }
        case 204:
            // iPhone hasn't uploaded yet — first-launch state.
            throw Error.noSnapshotYet
        case 401, 403:
            throw Error.unauthorized
        default:
            throw Error.http(http.statusCode)
        }
    }

    // MARK: - Token refresh

    /// Trade the stored refresh token for a new access token via the
    /// same `/api/auth/refresh` endpoint the iPhone uses. On success
    /// the new tokens are persisted to `WatchAuthStore` and the next
    /// `performSnapshotRequest` call will pick them up automatically.
    func refreshAccessToken() async throws {
        guard let stored = WatchAuthStore.shared.current(),
              let refreshToken = stored.refreshToken,
              !refreshToken.isEmpty else {
            throw Error.unauthorized
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            // 400/401 from refresh means the refresh token is dead;
            // there's no recovery here besides re-authenticating with
            // Apple, which the connecting view will gate on.
            if http.statusCode == 400 || http.statusCode == 401 {
                WatchAuthStore.shared.clear()
                throw Error.unauthorized
            }
            throw Error.http(http.statusCode)
        }
        do {
            let tokens = try decoder.decode(AuthResult.self, from: data)
            WatchAuthStore.shared.set(
                accessToken: tokens.accessToken,
                expiresAtEpoch: tokens.accessTokenExpiresAtEpochSeconds.map { TimeInterval($0) },
                refreshToken: tokens.refreshToken ?? refreshToken
            )
        } catch {
            throw Error.decode(error)
        }
    }

    /// Pre-emptive refresh — if the stored access token expires within
    /// the next 5 minutes, swap it for a fresh one before making the
    /// outbound call. Keeps long-running poll cycles from sleeping
    /// across an expiry boundary.
    private func preemptivelyRefreshIfStale() async {
        guard let token = WatchAuthStore.shared.current(),
              let expiresAt = token.accessTokenExpiresAt else { return }
        let buffer: TimeInterval = 5 * 60
        guard expiresAt <= Date().addingTimeInterval(buffer) else { return }
        // Best-effort — failures here are absorbed; the outer fetch
        // will still attempt with the (probably-soon-expired) token
        // and retry on 401 via the standard path.
        try? await refreshAccessToken()
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct SnapshotEnvelope: Decodable {
        let payload: String
        let updatedAt: Date
    }

    // MARK: - Apple sign-in (standalone watchOS auth)

    /// Exchange an Apple identity token for a Rung session — same
    /// `/api/auth/apple` endpoint the iOS app uses. The backend
    /// validates against Apple's JWKS and either links or provisions
    /// the account, returning the access + refresh tokens we persist
    /// in `WatchAuthStore`. This is the path that lets the watch
    /// authenticate without ever depending on a reachable iPhone —
    /// breaks the chicken-and-egg the WC auth handoff has.
    func exchangeAppleToken(
        identityToken: String,
        displayName: String?
    ) async throws -> AuthResult {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = AppleLoginRequest(identityToken: identityToken, displayName: displayName)
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.http(http.statusCode)
        }
        do {
            return try decoder.decode(AuthResult.self, from: data)
        } catch {
            throw Error.decode(error)
        }
    }

    private struct AppleLoginRequest: Encodable {
        let identityToken: String
        let displayName: String?
    }

    // MARK: - Habit / task toggle (direct from watch to backend)

    /// PUT `/api/habits/{id}/checks/{dayKey}` or its `/api/tasks/...`
    /// counterpart, identical contract to the iPhone's `setCheck`. The
    /// watch has its own auth token, so this call goes straight to the
    /// server — no iPhone WC roundtrip — which fixes the case where a
    /// flaky WC channel made watch-side toggles silently revert when
    /// the iPhone never received the message.
    ///
    /// `kind` chooses the path so habits and tasks land in the right
    /// SwiftData bucket on every other device after the SSE / poll
    /// fan-out.
    enum CheckKind { case habit, task }

    func setCheck(
        kind: CheckKind,
        backendID: Int64,
        dayKey: String,
        done: Bool
    ) async throws {
        // Pre-emptive refresh in case the access token is on the cusp
        // of expiring — same path the snapshot fetch uses.
        await preemptivelyRefreshIfStale()
        do {
            try await performSetCheck(
                kind: kind, backendID: backendID, dayKey: dayKey, done: done
            )
        } catch Error.unauthorized {
            try await refreshAccessToken()
            try await performSetCheck(
                kind: kind, backendID: backendID, dayKey: dayKey, done: done
            )
        }
    }

    private func performSetCheck(
        kind: CheckKind,
        backendID: Int64,
        dayKey: String,
        done: Bool
    ) async throws {
        guard let token = WatchAuthStore.shared.current()?.accessToken else {
            throw Error.noToken
        }
        let path: String
        switch kind {
        case .habit: path = "api/habits/\(backendID)/checks/\(dayKey)"
        case .task:  path = "api/tasks/\(backendID)/checks/\(dayKey)"
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body = CheckUpdateRequest(
            done: done,
            verificationTier: "selfReport",
            verificationSource: "selfReport",
            durationSeconds: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw Error.unauthorized
        default:
            throw Error.http(http.statusCode)
        }
    }

    private struct CheckUpdateRequest: Encodable {
        let done: Bool
        let verificationTier: String?
        let verificationSource: String?
        let durationSeconds: Int?
    }

    // MARK: - Create task (direct from watch to backend)

    /// POST `/api/tasks` with the given title. The watch's "Add" screen
    /// dictates / scribbles a title and we want it to land on iPhone +
    /// Mac + iPad even when the WC channel is dead — that's the same
    /// failure mode that was making toggles silently revert. Returns
    /// the new task's backend id; callers schedule a snapshot refresh
    /// shortly after so the freshly-created task appears in the watch's
    /// own pending list without waiting for the next poll tick.
    func createTask(title: String) async throws -> Int64 {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.http(400)
        }
        await preemptivelyRefreshIfStale()
        do {
            return try await performCreateTask(title: trimmed)
        } catch Error.unauthorized {
            try await refreshAccessToken()
            return try await performCreateTask(title: trimmed)
        }
    }

    private func performCreateTask(title: String) async throws -> Int64 {
        guard let token = WatchAuthStore.shared.current()?.accessToken else {
            throw Error.noToken
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tasks"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(TaskCreateRequest(title: title))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        switch http.statusCode {
        case 200..<300:
            do {
                let created = try decoder.decode(TaskCreateResponse.self, from: data)
                return created.id
            } catch {
                throw Error.decode(error)
            }
        case 401, 403:
            throw Error.unauthorized
        default:
            throw Error.http(http.statusCode)
        }
    }

    private struct TaskCreateRequest: Encodable {
        let title: String
    }

    /// Minimal projection of `BackendHabit` — we only need the new id,
    /// everything else flows in via the next snapshot refresh.
    private struct TaskCreateResponse: Decodable {
        let id: Int64
    }

    // MARK: - Primary list endpoints (standalone read path)

    /// One row from `/api/habits` or `/api/tasks` — the server-of-truth
    /// shape. Mirrors `BackendHabit` on iOS but drops the SwiftData /
    /// verification fields the watch UI doesn't need. The watch builds
    /// its own snapshot from these so an iPad toggle shows up on the
    /// wrist on the next 15 s poll, without the iPhone needing to be
    /// running to re-upload its cached `/api/watch/snapshot` payload.
    struct BackendHabitRow: Decodable {
        let id: Int64
        let title: String
        let checksByDate: [String: Bool]
        let canonicalKey: String?
        let verificationSource: String?
        let verificationTier: String?
        let weeklyTarget: Int?
        let createdAt: Date?

        private enum CodingKeys: String, CodingKey {
            case id, title, checksByDate, canonicalKey
            case verificationSource, verificationTier, weeklyTarget, createdAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(Int64.self, forKey: .id)
            self.title = try c.decode(String.self, forKey: .title)
            self.checksByDate = try c.decode([String: Bool].self, forKey: .checksByDate)
            self.canonicalKey = try c.decodeIfPresent(String.self, forKey: .canonicalKey)
            self.verificationSource = try c.decodeIfPresent(String.self, forKey: .verificationSource)
            self.verificationTier = try c.decodeIfPresent(String.self, forKey: .verificationTier)
            self.weeklyTarget = try c.decodeIfPresent(Int.self, forKey: .weeklyTarget)
            // The server can return createdAt as either an ISO string
            // or an epoch double depending on the deployment's
            // serializer config — try both via the configured
            // `dateDecodingStrategy`.
            self.createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        }
    }

    /// `GET /api/habits` — list of recurring habits. Auth-refreshing
    /// retry mirrors the snapshot fetch path.
    func listHabits() async throws -> [BackendHabitRow] {
        await preemptivelyRefreshIfStale()
        do {
            return try await performList(path: "api/habits")
        } catch Error.unauthorized {
            try await refreshAccessToken()
            return try await performList(path: "api/habits")
        }
    }

    /// `GET /api/tasks` — list of one-shot tasks.
    func listTasks() async throws -> [BackendHabitRow] {
        await preemptivelyRefreshIfStale()
        do {
            return try await performList(path: "api/tasks")
        } catch Error.unauthorized {
            try await refreshAccessToken()
            return try await performList(path: "api/tasks")
        }
    }

    private func performList(path: String) async throws -> [BackendHabitRow] {
        guard let token = WatchAuthStore.shared.current()?.accessToken else {
            throw Error.noToken
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1)
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode([BackendHabitRow].self, from: data)
            } catch {
                throw Error.decode(error)
            }
        case 401, 403:
            throw Error.unauthorized
        default:
            throw Error.http(http.statusCode)
        }
    }

    /// Decoded backend response — mirror of `BackendAuthTokens` on iOS.
    struct AuthResult: Decodable {
        let accessToken: String
        let refreshToken: String?
        let accessTokenExpiresAtEpochSeconds: Int64?
    }
}
