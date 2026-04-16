import Foundation
import Combine

struct BackendHabit: Decodable, Identifiable {
    let id: Int64
    let title: String
    let checksByDate: [String: Bool]

    var completedDayKeys: [String] {
        checksByDate.filter { $0.value }.map(\.key).sorted()
    }
}

struct AccountabilityDashboard: Decodable {
    let profile: Profile
    let level: Level
    let match: MentorMatch?
    let menteeDashboard: MenteeDashboard
    let mentorDashboard: MentorDashboard
    let mentorship: MentorshipStatus?
    let rewards: Rewards
    let weeklyChallenge: WeeklyChallenge
    let social: SocialDashboard?
    let feed: [SocialPost]
    let notifications: [Notification]

    struct Profile: Decodable {
        let userId: Int64; let username: String?; let email: String
        let displayName: String; let avatarUrl: String?
        let timezone: String; let language: String; let goals: String
    }
    struct Level: Decodable {
        let name: String; let weeklyConsistencyPercent: Int
        let accountabilityScore: Int; let mentorEligible: Bool
        let needsMentor: Bool; let note: String
    }
    struct MentorMatch: Decodable {
        let id: Int64; let status: String
        let mentor: UserSummary; let mentee: UserSummary
        let matchScore: Int; let reasons: [String]
    }
    struct UserSummary: Decodable {
        let userId: Int64; let displayName: String
        let timezone: String; let language: String
        let goals: String; let weeklyConsistencyPercent: Int
    }
    struct MenteeDashboard: Decodable {
        let mentorTip: String; let missedHabitsToday: Int
        let progressScore: Int; let messages: [Message]
    }
    struct MentorDashboard: Decodable {
        let activeMenteeCount: Int; let mentees: [MenteeSummary]
    }
    struct MentorshipStatus: Decodable {
        let canFindMentor: Bool; let hasMentor: Bool
        let canChangeMentor: Bool; let lockedUntil: String?
        let lockDaysRemaining: Int; let message: String
    }
    struct MenteeSummary: Decodable, Identifiable {
        var id: Int64 { matchId }
        let matchId: Int64; let userId: Int64; let displayName: String
        let missedHabitsToday: Int; let weeklyConsistencyPercent: Int
        let suggestedAction: String
    }
    struct Rewards: Decodable { let xp: Int; let coins: Int; let badges: [String] }
    struct WeeklyChallenge: Decodable {
        let title: String; let description: String
        let completedPerfectDays: Int; let targetPerfectDays: Int
        let rank: Int; let leaderboard: [LeaderboardEntry]
    }
    struct LeaderboardEntry: Decodable, Identifiable {
        var id: String { "\(displayName)-\(score)-\(currentUser)" }
        let displayName: String; let score: Int; let currentUser: Bool
    }
    struct SocialPost: Decodable, Identifiable {
        let id: Int64; let author: String; let message: String; let createdAt: String
    }
    struct SocialDashboard: Decodable {
        let friendCount: Int; let updates: [SocialActivity]; let suggestions: [FriendSummary]
    }
    struct SocialActivity: Decodable, Identifiable {
        let id: String; let userId: Int64; let displayName: String
        let message: String; let weeklyConsistencyPercent: Int
        let progressPercent: Int; let kind: String; let createdAt: String?
    }
    struct FriendSummary: Decodable, Identifiable {
        var id: Int64 { userId }
        let userId: Int64; let displayName: String
        let weeklyConsistencyPercent: Int; let progressPercent: Int; let goals: String
    }
    struct Message: Decodable, Identifiable {
        let id: Int64; let senderId: Int64; let senderName: String
        let message: String; let nudge: Bool; let createdAt: String
    }
    struct Notification: Decodable, Identifiable {
        var id: String { "\(type)-\(title)" }
        let title: String; let body: String; let type: String
    }
}

// MARK: - HabitBackendStore

@MainActor
final class HabitBackendStore: ObservableObject {
    // MARK: Published state

    @Published private(set) var token: String?
    @Published var dashboard: AccountabilityDashboard?
    @Published var isSyncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    // Per-endpoint request states — UI can show per-section loading/error indicators
    @Published private(set) var authRequestState:        RequestState<Void>                    = .idle
    @Published private(set) var habitListRequestState:   RequestState<[BackendHabit]>           = .idle
    @Published private(set) var dashboardRequestState:   RequestState<AccountabilityDashboard>  = .idle
    @Published private(set) var createHabitRequestState: RequestState<BackendHabit>             = .idle
    @Published private(set) var checkUpdateRequestState: RequestState<Void>                    = .idle
    @Published private(set) var deleteHabitRequestState: RequestState<Void>                    = .idle
    @Published private(set) var mentorRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var messageRequestState:     RequestState<Void>                    = .idle
    @Published private(set) var friendRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var streamRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var liveMessagesByMatch:     [Int64: [AccountabilityDashboard.Message]] = [:]

    // MARK: Private

    private let sessionKey = "habitTracker.localhost.session.v1"
    private let apiClient: BackendAPIClient
    private let authRepository: AuthRepository
    private let habitRepository: HabitRepository
    private let accountabilityRepository: AccountabilityRepository
    private let deviceRepository: DeviceRepository
    /// Shared response cache; invalidated by any write that mutates the cached resource.
    let responseCache = ResponseCache()
    private var streamTask: Task<Void, Never>?
    private var streamingMatchID: Int64?
    private var lastStreamEventID: String?

    var isAuthenticated: Bool { token != nil }

    init() {
        let session = Self.loadSession(from: "habitTracker.localhost.session.v1")
        token = session?.accessToken

        let client = BackendAPIClient(initialSession: session)
        apiClient = client
        authRepository            = AuthRepository(client: client)
        habitRepository           = HabitRepository(client: client)
        accountabilityRepository  = AccountabilityRepository(client: client)
        deviceRepository          = DeviceRepository(client: client)
    }

    // MARK: - Convenience

    func messages(matchID: Int64?) -> [AccountabilityDashboard.Message] {
        guard let matchID else { return dashboard?.menteeDashboard.messages ?? [] }
        return liveMessagesByMatch[matchID] ?? dashboard?.menteeDashboard.messages ?? []
    }

    // MARK: - Auth

    func signIn(username: String, password: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.signIn(username: username, password: password)
            applySession(session)
            statusMessage = "Connected to localhost:8080"
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func register(username: String, email: String, password: String, avatarURL: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.register(
                username: username, email: email, password: password, avatarURL: avatarURL
            )
            applySession(session)
            statusMessage = "Connected to localhost:8080"
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func signOut() {
        stopStream()
        clearSession()
        Task { await apiClient.clearSession() }
    }

    // MARK: - Habits (cache-aware)

    func listHabits() async throws -> [BackendHabit] {
        // Return cached value if still fresh
        if let cached = await responseCache.cachedHabits() {
            habitListRequestState = .success(cached)
            return cached
        }

        habitListRequestState = .loading; refreshSyncingState()
        do {
            let habits = try await habitRepository.listHabits()
            await syncSessionFromClient()
            await responseCache.cacheHabits(habits)
            habitListRequestState = .success(habits)
            errorMessage = nil
            refreshSyncingState()
            return habits
        } catch {
            handleAuthenticatedRequestError(error)
            habitListRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func createHabit(title: String) async throws -> BackendHabit {
        createHabitRequestState = .loading; refreshSyncingState()
        do {
            let habit = try await habitRepository.createHabit(title: title)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()   // force re-fetch on next list
            createHabitRequestState = .success(habit)
            errorMessage = nil
            refreshSyncingState()
            return habit
        } catch {
            handleAuthenticatedRequestError(error)
            createHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func setCheck(habitID: Int64, dateKey: String, done: Bool) async throws {
        checkUpdateRequestState = .loading; refreshSyncingState()
        do {
            _ = try await habitRepository.setCheck(habitID: habitID, dateKey: dateKey, done: done)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            await responseCache.invalidateDashboard()
            checkUpdateRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            checkUpdateRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func deleteHabit(habitID: Int64) async throws {
        deleteHabitRequestState = .loading; refreshSyncingState()
        do {
            try await habitRepository.deleteHabit(habitID: habitID)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            deleteHabitRequestState = .success(())
            errorMessage = nil
            refreshSyncingState()
        } catch {
            handleAuthenticatedRequestError(error)
            deleteHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    // MARK: - Dashboard (cache-aware)

    func refreshDashboard() async {
        guard token != nil else { return }

        // Return cached dashboard if fresh (e.g., refreshDashboard called multiple times quickly)
        if let cached = await responseCache.cachedDashboard() {
            if case .success = dashboardRequestState { return }  // already showing latest
            applyDashboardUpdate(cached)
            dashboardRequestState = .success(cached)
            return
        }

        dashboardRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.dashboard()
            await syncSessionFromClient()
            await responseCache.cacheDashboard(value)
            applyDashboardUpdate(value)
            dashboardRequestState = .success(value)
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
            dashboardRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    // MARK: - Accountability (write methods always invalidate dashboard cache)

    func assignMentor() async {
        guard token != nil else { return }
        mentorRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.assignMentor()
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Mentor match updated"
            errorMessage = nil
            mentorRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            mentorRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func sendMenteeMessage(matchId: Int64, message: String) async {
        guard token != nil else { return }
        messageRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.sendMenteeMessage(matchId: matchId, message: message)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            messageRequestState = .success(())
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
            messageRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func requestFriend(userID: Int64) async {
        guard token != nil else { return }
        friendRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.requestFriend(friendUserID: userID)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Friend added"
            errorMessage = nil
            friendRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            friendRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func registerDeviceToken(_ token: Data) async {
        guard isAuthenticated else { return }
        let hex = token.map { String(format: "%02.2hhx", $0) }.joined()
        do { try await deviceRepository.registerToken(hex, platform: "macos") } catch {}
    }

    func markMatchRead(matchID: Int64?) async {
        guard let matchID, token != nil else { return }
        do { try await accountabilityRepository.markMatchRead(matchId: matchID) } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    // MARK: - SSE Stream

    private func applyDashboardUpdate(_ value: AccountabilityDashboard) {
        dashboard = value
        if let matchID = value.match?.id {
            liveMessagesByMatch[matchID] = value.menteeDashboard.messages
            startStream(for: matchID)
        } else {
            stopStream()
        }
    }

    private func startStream(for matchID: Int64) {
        if streamingMatchID == matchID, streamTask != nil { return }
        stopStream()
        streamingMatchID = matchID
        streamTask = Task { [weak self] in await self?.runStreamLoop(matchID: matchID) }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamingMatchID = nil
        lastStreamEventID = nil
        streamRequestState = .idle
    }

    private func runStreamLoop(matchID: Int64) async {
        var hadSuccessfulConnection = false
        var backoffSeconds: TimeInterval = 1

        while !Task.isCancelled, streamingMatchID == matchID, isAuthenticated {
            do {
                streamRequestState = .loading
                let request = try await accountabilityRepository.streamRequest(
                    matchId: matchID, lastEventID: lastStreamEventID
                )
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw HabitBackendError.invalidResponse
                }
                if hadSuccessfulConnection { await refreshDashboard() }
                hadSuccessfulConnection = true
                backoffSeconds = 1  // reset on successful connect
                streamRequestState = .success(())
                try await consumeSSELines(matchID: matchID, lines: bytes.lines)
            } catch {
                if Task.isCancelled { return }
                streamRequestState = .failure(error.localizedDescription)
                // Exponential backoff for stream reconnects (cap at 30s)
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
    }

    private func consumeSSELines<S: AsyncSequence>(matchID: Int64, lines: S) async throws where S.Element == String {
        var eventName = "message"
        var eventID: String?
        var dataLines: [String] = []

        for try await raw in lines {
            if Task.isCancelled || streamingMatchID != matchID { return }
            if raw.isEmpty {
                let payload = dataLines.joined(separator: "\n")
                if !payload.isEmpty {
                    handleStreamEvent(matchID: matchID, eventName: eventName, eventID: eventID, payload: payload)
                }
                eventName = "message"; eventID = nil; dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if raw.hasPrefix("event:") { eventName = raw.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("id:")    { eventID   = raw.dropFirst(3).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("data:")  { dataLines.append(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func handleStreamEvent(matchID: Int64, eventName: String, eventID: String?, payload: String) {
        if let id = eventID, !id.isEmpty { lastStreamEventID = id }
        switch eventName {
        case "message.created":
            guard
                let data = payload.data(using: .utf8),
                let msg = try? JSONDecoder().decode(AccountabilityDashboard.Message.self, from: data)
            else { return }
            appendMessage(msg, to: matchID)
            // Arriving messages make the cached dashboard stale
            Task { await responseCache.invalidateDashboard() }
        case "match.updated":
            Task { [weak self] in
                await self?.responseCache.invalidateDashboard()
                await self?.refreshDashboard()
            }
        case "message.read":
            _ = payload.data(using: .utf8).flatMap { try? JSONDecoder().decode(MatchStreamMessageReadEvent.self, from: $0) }
        case "ping", "stream.ready":
            break
        default:
            break
        }
    }

    private func appendMessage(_ message: AccountabilityDashboard.Message, to matchID: Int64) {
        var msgs = liveMessagesByMatch[matchID] ?? []
        guard !msgs.contains(where: { $0.id == message.id }) else { return }
        msgs.insert(message, at: 0)
        if msgs.count > 60 { msgs = Array(msgs.prefix(60)) }
        liveMessagesByMatch[matchID] = msgs
    }

    // MARK: - Error handling

    private func handleAuthenticatedRequestError(_ error: Error) {
        if case HabitBackendError.notAuthenticated = error {
            clearSession(errorMessage: error.localizedDescription)
            Task { await apiClient.clearSession() }
            return
        }
        errorMessage = error.localizedDescription
    }

    private func refreshSyncingState() {
        isSyncing = authRequestState.isLoading
            || habitListRequestState.isLoading
            || dashboardRequestState.isLoading
            || createHabitRequestState.isLoading
            || checkUpdateRequestState.isLoading
            || deleteHabitRequestState.isLoading
            || mentorRequestState.isLoading
            || messageRequestState.isLoading
            || friendRequestState.isLoading
            || streamRequestState.isLoading
    }

    // MARK: - Session persistence

    private func applySession(_ session: BackendSession) {
        token = session.accessToken
        Self.saveSession(session, key: sessionKey)
    }

    private func syncSessionFromClient() async {
        let session = await apiClient.currentSession()
        token = session?.accessToken
        Self.saveSession(session, key: sessionKey)
    }

    private func clearSession(errorMessage: String? = nil) {
        stopStream()
        token = nil; dashboard = nil; liveMessagesByMatch = [:]
        statusMessage = nil; self.errorMessage = errorMessage
        Self.saveSession(nil, key: sessionKey)
        UserDefaults.standard.removeObject(forKey: "habitTracker.localhost.token")
        authRequestState = .idle; habitListRequestState = .idle; dashboardRequestState = .idle
        createHabitRequestState = .idle; checkUpdateRequestState = .idle
        deleteHabitRequestState = .idle; mentorRequestState = .idle
        messageRequestState = .idle; friendRequestState = .idle
        Task { await responseCache.invalidateAll() }
        refreshSyncingState()
    }

    private static func saveSession(_ session: BackendSession?, key: String) {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func loadSession(from key: String) -> BackendSession? {
        if
            let data = UserDefaults.standard.data(forKey: key),
            let session = try? JSONDecoder().decode(BackendSession.self, from: data)
        { return session }
        if let legacy = UserDefaults.standard.string(forKey: "habitTracker.localhost.token") {
            return BackendSession.fromLegacyToken(legacy)
        }
        return nil
    }
}
