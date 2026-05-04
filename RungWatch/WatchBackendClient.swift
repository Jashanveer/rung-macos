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
    func fetchSnapshot() async throws -> (snapshot: WatchSnapshot, updatedAt: Date) {
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

    /// Decoded backend response — mirror of `BackendAuthTokens` on iOS.
    struct AuthResult: Decodable {
        let accessToken: String
        let refreshToken: String?
        let accessTokenExpiresAtEpochSeconds: Int64?
    }
}
