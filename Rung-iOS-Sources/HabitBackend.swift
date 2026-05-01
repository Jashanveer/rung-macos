import Foundation
import Combine
import SwiftData

struct BackendHabit: Decodable, Identifiable {
    let id: Int64
    let title: String
    let reminderWindow: String?
    let checksByDate: [String: Bool]
    let entryType: HabitEntryType
    let createdAt: Date?
    /// Verification metadata round-tripped through `/api/habits`. All nil
    /// when the server row is pre-Verification or the client didn't supply
    /// any on create. Matches the Swift `Habit.canonicalKey` / tier / etc.
    let canonicalKey: String?
    let verificationTier: String?
    let verificationSource: String?
    let verificationParam: Double?
    let weeklyTarget: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case reminderWindow
        case checksByDate
        case createdAt
        case canonicalKey
        case verificationTier
        case verificationSource
        case verificationParam
        case weeklyTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        reminderWindow = try container.decodeIfPresent(String.self, forKey: .reminderWindow)
        checksByDate = try container.decode([String: Bool].self, forKey: .checksByDate)
        createdAt = Self.decodeDateIfPresent(from: container, forKey: .createdAt)
        canonicalKey = try container.decodeIfPresent(String.self, forKey: .canonicalKey)
        verificationTier = try container.decodeIfPresent(String.self, forKey: .verificationTier)
        verificationSource = try container.decodeIfPresent(String.self, forKey: .verificationSource)
        verificationParam = try container.decodeIfPresent(Double.self, forKey: .verificationParam)
        weeklyTarget = try container.decodeIfPresent(Int.self, forKey: .weeklyTarget)
        entryType = .habit
    }

    init(
        id: Int64,
        title: String,
        checksByDate: [String: Bool],
        reminderWindow: String? = nil,
        entryType: HabitEntryType = .habit,
        createdAt: Date? = nil,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.reminderWindow = reminderWindow
        self.checksByDate = checksByDate
        self.entryType = entryType
        self.createdAt = createdAt
        self.canonicalKey = canonicalKey
        self.verificationTier = verificationTier
        self.verificationSource = verificationSource
        self.verificationParam = verificationParam
        self.weeklyTarget = weeklyTarget
    }

    var completedDayKeys: [String] {
        checksByDate.filter { $0.value }.map(\.key).sorted()
    }

    var localCreatedAt: Date {
        if let createdAt {
            return createdAt
        }
        if let firstCompletedKey = completedDayKeys.first {
            return DateKey.date(from: firstCompletedKey)
        }
        return Date()
    }

    private static func decodeDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) {
            return date
        }

        return DateKey.date(from: String(raw.prefix(10)))
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
    let habitClusters: [HabitTimeCluster]

    private enum CodingKeys: String, CodingKey {
        case profile, level, match, menteeDashboard, mentorDashboard, mentorship
        case rewards, weeklyChallenge, social, feed, notifications, habitClusters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile           = try c.decode(Profile.self,            forKey: .profile)
        level             = try c.decode(Level.self,              forKey: .level)
        match             = try c.decodeIfPresent(MentorMatch.self, forKey: .match)
        menteeDashboard   = try c.decode(MenteeDashboard.self,    forKey: .menteeDashboard)
        mentorDashboard   = try c.decode(MentorDashboard.self,    forKey: .mentorDashboard)
        mentorship        = try c.decodeIfPresent(MentorshipStatus.self, forKey: .mentorship)
        rewards           = try c.decode(Rewards.self,            forKey: .rewards)
        weeklyChallenge   = try c.decode(WeeklyChallenge.self,    forKey: .weeklyChallenge)
        social            = try c.decodeIfPresent(SocialDashboard.self, forKey: .social)
        feed              = try c.decodeIfPresent([SocialPost].self, forKey: .feed) ?? []
        notifications     = try c.decodeIfPresent([Notification].self, forKey: .notifications) ?? []
        habitClusters     = try c.decodeIfPresent([HabitTimeCluster].self, forKey: .habitClusters) ?? []
    }

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
        let aiMentor: Bool

        private enum CodingKeys: String, CodingKey {
            case id, status, mentor, mentee, matchScore, reasons, aiMentor
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id          = try c.decode(Int64.self,        forKey: .id)
            status      = try c.decode(String.self,       forKey: .status)
            mentor      = try c.decode(UserSummary.self,  forKey: .mentor)
            mentee      = try c.decode(UserSummary.self,  forKey: .mentee)
            matchScore  = try c.decode(Int.self,          forKey: .matchScore)
            reasons     = try c.decode([String].self,     forKey: .reasons)
            aiMentor    = try c.decodeIfPresent(Bool.self, forKey: .aiMentor) ?? false
        }
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
    struct Rewards: Decodable {
        let xp: Int
        let badges: [String]
        /// How many unique habit-day checks have already earned XP today.
        let checksToday: Int
        /// Server-side daily cap. Checks beyond this still track but earn 0 XP.
        let dailyCap: Int
        /// False once the daily cap is reached — UI should show a "cap reached" indicator.
        let rewardEligible: Bool
        /// Number of streak freeze tokens the user has available.
        let freezesAvailable: Int
        /// "YYYY-MM-DD" dates that have been protected by a streak freeze.
        let frozenDates: [String]

        private enum CodingKeys: String, CodingKey {
            case xp, badges, checksToday, dailyCap, rewardEligible
            case freezesAvailable, frozenDates
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            xp               = try c.decode(Int.self,    forKey: .xp)
            badges           = try c.decodeIfPresent([String].self, forKey: .badges) ?? []
            checksToday      = try c.decode(Int.self,    forKey: .checksToday)
            dailyCap         = try c.decode(Int.self,    forKey: .dailyCap)
            rewardEligible   = try c.decode(Bool.self,   forKey: .rewardEligible)
            freezesAvailable = try c.decodeIfPresent(Int.self,    forKey: .freezesAvailable) ?? 0
            frozenDates      = try c.decodeIfPresent([String].self, forKey: .frozenDates) ?? []
        }
    }
    struct HabitTimeCluster: Decodable, Identifiable {
        var id: Int64 { habitId }
        let habitId: Int64
        let habitTitle: String
        let timeSlot: String
        let avgHourOfDay: Int
        let sampleSize: Int
    }
    struct WeeklyChallenge: Decodable {
        let title: String; let description: String
        let completedPerfectDays: Int; let targetPerfectDays: Int
        let rank: Int; let leaderboard: [LeaderboardEntry]
    }
    struct LeaderboardEntry: Decodable, Identifiable {
        var id: String { "\(displayName)-\(score)-\(currentUser)" }
        let displayName: String
        let score: Int
        let currentUser: Bool
        /// Tier-weighted score from the server (auto × 10, partial × 5,
        /// self × 1). 0 when the backend hasn't enabled the weighted pass
        /// yet — older builds send no `verifiedScore` key at all, so the
        /// decodeIfPresent default keeps the UI safe across versions.
        let verifiedScore: Int

        private enum CodingKeys: String, CodingKey {
            case displayName, score, currentUser, verifiedScore
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try c.decode(String.self, forKey: .displayName)
            score = try c.decode(Int.self, forKey: .score)
            currentUser = try c.decode(Bool.self, forKey: .currentUser)
            verifiedScore = try c.decodeIfPresent(Int.self, forKey: .verifiedScore) ?? 0
        }
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
        /// Number of perfect days the friend has accumulated this calendar
        /// year. Backwards-compatible: defaults to 0 if the server doesn't
        /// supply it (older builds).
        let yearPerfectDays: Int

        private enum CodingKeys: String, CodingKey {
            case id, userId, displayName, message, weeklyConsistencyPercent
            case progressPercent, kind, createdAt, yearPerfectDays
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id                       = try c.decode(String.self,  forKey: .id)
            userId                   = try c.decode(Int64.self,   forKey: .userId)
            displayName              = try c.decode(String.self,  forKey: .displayName)
            message                  = try c.decode(String.self,  forKey: .message)
            weeklyConsistencyPercent = try c.decode(Int.self,     forKey: .weeklyConsistencyPercent)
            progressPercent          = try c.decode(Int.self,     forKey: .progressPercent)
            kind                     = try c.decode(String.self,  forKey: .kind)
            createdAt                = try c.decodeIfPresent(String.self, forKey: .createdAt)
            yearPerfectDays          = try c.decodeIfPresent(Int.self, forKey: .yearPerfectDays) ?? 0
        }
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
    /// Bumped every time the server returns 404 for a habit/task/check
    /// the local store thought existed. The dashboard owner observes
    /// this to trigger a full SwiftData↔backend reconcile so the local
    /// copy converges to whatever the server currently has — server-wins
    /// applied to the divergence the user just bumped into.
    @Published var staleResourceTick: Int = 0
    /// Set to true on a successful register() call so the UI can force the
    /// onboarding overview to appear regardless of any stale UserDefaults
    /// onboarded_<userId> key. UI should reset this to false after consuming.
    @Published var justRegistered: Bool = false
    /// True when the active session was just minted by a fresh Apple
    /// sign-up — the UI overlays an `AppleProfileSetupView` to collect a
    /// public username + avatar before letting the dashboard render.
    /// Cleared by `setupAppleProfile` on success.
    @Published var requiresProfileSetup: Bool = false
    /// Real name Apple's identity token returned on the first
    /// authorization, retained across the brief moment between
    /// `signInWithApple` succeeding and `AppleProfileSetupView` rendering
    /// so we can prefill the "Your name" field. Apple drops `fullName`
    /// on every subsequent sign-in, so when this is nil the setup
    /// screen forces the user to type a name themselves — that's the
    /// fix for the "my display name comes out as a random hash"
    /// behaviour seen with private-relay email accounts.
    @Published var pendingAppleFullName: String? = nil
    /// Mirrors `NWPathMonitor`. False while the device has no route to the
    /// backend; the UI uses this to hide network-failure toasts and to trigger
    /// a full sync on the next reconnection.
    @Published private(set) var isOnline: Bool = true

    // Per-endpoint request states — UI can show per-section loading/error indicators
    @Published private(set) var authRequestState:        RequestState<Void>                    = .idle
    @Published private(set) var habitListRequestState:   RequestState<[BackendHabit]>           = .idle
    @Published private(set) var dashboardRequestState:   RequestState<AccountabilityDashboard>  = .idle
    @Published private(set) var createHabitRequestState: RequestState<BackendHabit>             = .idle
    @Published private(set) var updateHabitRequestState: RequestState<BackendHabit>             = .idle
    @Published private(set) var checkUpdateRequestState: RequestState<Void>                    = .idle
    @Published private(set) var deleteHabitRequestState: RequestState<Void>                    = .idle
    @Published private(set) var mentorRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var messageRequestState:     RequestState<Void>                    = .idle
    @Published private(set) var friendRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var friendSearchRequestState: RequestState<[AccountabilityDashboard.FriendSummary]> = .idle
    @Published private(set) var friendSearchResults: [AccountabilityDashboard.FriendSummary] = []
    @Published private(set) var streakFreezeRequestState: RequestState<Void>                   = .idle
    @Published private(set) var streamRequestState:      RequestState<Void>                    = .idle
    @Published private(set) var preferencesRequestState: RequestState<UserPreferences>         = .idle
    @Published private(set) var preferences:             UserPreferences?                       = nil
    @Published private(set) var liveMessagesByMatch:     [Int64: [AccountabilityDashboard.Message]] = [:]
    /// True while we're waiting on the AI mentor to deliver a reply to the
    /// mentee's latest message. Drives the "mentor is typing…" bubble in
    /// MentorChatBubble. Flipped on in `sendMenteeMessage` for AI matches
    /// and cleared the moment a new AI mentor message arrives via SSE (or
    /// after a generous timeout, as a safety net).
    @Published private(set) var aiMentorTyping: Bool = false
    private var aiMentorTypingTimeoutTask: Task<Void, Never>?

    // MARK: Private

    // Legacy UserDefaults keys — read once at launch and migrated to the Keychain.
    private static let legacySessionKey = "habitTracker.localhost.session.v1"
    private static let legacyTokenKey   = "habitTracker.localhost.token"

    /// Per-user UserDefaults key for the in-progress profile-setup flag.
    /// Persisting this is what lets a user who quits the app mid-setup
    /// land back on the username/avatar screen on relaunch instead of
    /// the dashboard with the auto-generated placeholder handle.
    private static func profileSetupPendingKey(for userId: String) -> String {
        "rung.requiresProfileSetup.\(userId)"
    }
    private let apiClient: BackendAPIClient
    private let authRepository: AuthRepository
    private let habitRepository: HabitRepository
    private let accountabilityRepository: AccountabilityRepository
    private let deviceRepository: DeviceRepository
    private let preferencesRepository: PreferencesRepository
    private let sleepSnapshotRepository: SleepSnapshotRepository
    /// Shared response cache; invalidated by any write that mutates the cached resource.
    let responseCache = ResponseCache()
    private var streamTask: Task<Void, Never>?
    private var streamingMatchID: Int64?
    private var lastStreamEventID: String?
    /// Long-lived per-user SSE task. Connects on authentication,
    /// reconnects with exponential backoff on disconnect, and posts
    /// `.habitsChangedSSE` whenever the server publishes that another
    /// device mutated a habit so ContentView can trigger sync in seconds.
    private var userStreamTask: Task<Void, Never>?
    private var lastUserStreamEventID: String?
    /// Dedicated URLSession for the per-user SSE stream. The shared
    /// session can buffer text/event-stream responses — the server
    /// reports "delivered" but the client's `.lines` iterator never
    /// fires. A dedicated session with caching disabled forces bytes
    /// to flush as they arrive instead of waiting for buffer
    /// thresholds.
    ///
    /// `timeoutIntervalForRequest` is the per-event idle limit, NOT
    /// the total connection lifetime. We push it past the server's
    /// 15-second heartbeat so an idle stream that's only emitting
    /// pings doesn't time out, but keep it finite so a wedged
    /// connection eventually fails and triggers a reconnect rather
    /// than hanging forever. `timeoutIntervalForResource` is the
    /// total ceiling — we let it match the server's 30-min emitter
    /// timeout. Setting either to `0` on macOS is interpreted as
    /// "instant timeout" and silently drops the connection — that's
    /// the bug an earlier revision of this code shipped with.
    /// Shared URLSession for ALL SSE work (per-match stream + per-user stream).
    /// Held as `var` so `signOut` can `invalidateAndCancel()` it and replace
    /// with a fresh one — without that, the underlying URLSessionDataTask can
    /// keep trickling bytes after the user signs out, leaking the previous
    /// user's data into a re-signed-in session.
    /// (Uses the explicit class name instead of `Self.` because Swift refuses
    /// `Self` in stored-property initializers even on `final` classes.)
    private var sseSession: URLSession = HabitBackendStore.makeSseSession()

    private static func makeSseSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // Idle timeout — server sends a `ping` every 15s, so 45s lets
        // us tolerate one missed heartbeat before declaring the
        // stream wedged and reconnecting.
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 30 * 60    // matches server EMITTER_TIMEOUT_MS
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        // `waitsForConnectivity = true` is intentionally LEFT OFF: it
        // made URLSession wait silently when the backend was
        // unreachable instead of failing fast and triggering the
        // reconnect-with-backoff loop. We'd rather see Connection
        // refused immediately.
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }

    /// Invalidate any in-flight SSE bytes-async tasks and replace the session
    /// so subsequent sign-ins start with a fresh transport. Called from
    /// signOut + clearSession; safe to call multiple times.
    private func resetSseSession() {
        sseSession.invalidateAndCancel()
        sseSession = HabitBackendStore.makeSseSession()
    }

    /// DEBUG-only logger for the per-user SSE channel. The user-stream loop
    /// is chatty (one line per connect / event / disconnect) and the
    /// `habits.changed` payload contains user data — neither belongs in
    /// Release builds where it lands in the device's unified log.
    @inline(__always)
    private static func sseLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
    private var lastSentMessageAt: Date?
    private var lastSentMessageText: String?
    private let networkMonitor = NetworkMonitor()
    private var networkCancellable: AnyCancellable?

    var isAuthenticated: Bool { token != nil }

    /// Stable per-user identifier decoded from the JWT `sub` or `userId` claim.
    var currentUserId: String? {
        guard let t = token else { return nil }
        let parts = t.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let sub = obj["sub"] as? String { return sub }
        if let uid = obj["userId"] as? Int { return String(uid) }
        return nil
    }

    init() {
        let session = Self.loadSession()
        token = session?.accessToken

        let client = BackendAPIClient(initialSession: session)
        apiClient = client
        authRepository            = AuthRepository(client: client)
        habitRepository           = HabitRepository(client: client)
        accountabilityRepository  = AccountabilityRepository(client: client)
        deviceRepository          = DeviceRepository(client: client)
        preferencesRepository     = PreferencesRepository(client: client)
        sleepSnapshotRepository   = SleepSnapshotRepository(client: client)

        // Cold launch with a previously-saved session: open the per-user
        // SSE stream so cross-device sync works on app relaunches, not
        // just on fresh sign-ins. Without this the stream only ran on
        // the very first login per install — every relaunch silently
        // skipped the SSE setup, breaking the live-update path.
        if session != nil {
            startUserStream()
        }

        // Restore the "in-progress profile setup" overlay if the user
        // quit during the username/avatar pick on a previous launch.
        // Has to run after all stored properties are initialised because
        // `currentUserId` reads `self.token`.
        if let uid = currentUserId,
           UserDefaults.standard.bool(forKey: Self.profileSetupPendingKey(for: uid)) {
            requiresProfileSetup = true
        }

        // Server-side reconcile (V15 `profile_setup_completed`). The
        // UserDefaults check above is the offline / pre-network primer;
        // this Task asks the server for the truth and either confirms
        // (no-op), forces the overlay even if local state forgot, or
        // clears it (e.g. user finished setup on another device).
        if session != nil {
            Task { [weak self] in await self?.reconcileProfileSetupFromServer() }
        }

        isOnline = networkMonitor.isOnline
        networkCancellable = networkMonitor.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] online in
                guard let self else { return }
                guard self.isOnline != online else { return }
                self.isOnline = online
                if online {
                    // Connectivity restored — clear any stale "offline" toast so
                    // the UI can reflect the recovery immediately. The caller
                    // (ContentView) drives the outbox flush via syncWithBackend.
                    if self.errorMessage == Self.offlineStatusMessage {
                        self.errorMessage = nil
                    }
                }
            }

        // Auto-sign-out when the refresh token is rejected — `BackendAPIClient`
        // posts this once it has cleared its own session and confirmed there
        // is no recovery without a fresh login.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInvalidatedNotification),
            name: BackendAPIClient.sessionInvalidatedNotification,
            object: nil
        )
    }

    @objc private func handleSessionInvalidatedNotification(_ notification: Notification) {
        guard isAuthenticated else { return }
        // Defeat the stale-401 race: a 401 from a request issued under
        // session A can arrive at the notification handler AFTER the user
        // has signed out and back in (session B). The notification's userInfo
        // carries the API client epoch at post time; if our current epoch is
        // higher, the user is on session B and we must NOT kick them out.
        let staleEpoch = notification.userInfo?[BackendAPIClient.sessionInvalidatedEpochKey] as? UInt
        Task { @MainActor in
            let currentEpoch = await apiClient.currentEpoch()
            if let staleEpoch, staleEpoch < currentEpoch {
                #if DEBUG
                print("[Auth] dropped stale session-invalidated (epoch \(staleEpoch) < current \(currentEpoch))")
                #endif
                return
            }
            guard isAuthenticated else { return }
            clearSession(errorMessage: "Your session expired — please sign in again.")
        }
    }

    /// Shown in place of raw URLSession errors when the device is offline.
    /// Kept short so the existing error banner reads like a status line.
    fileprivate static let offlineStatusMessage = "Offline — changes will sync when you're back online."

    // MARK: - Convenience

    func messages(matchID: Int64?) -> [AccountabilityDashboard.Message] {
        let source: [AccountabilityDashboard.Message]
        if let matchID {
            source = liveMessagesByMatch[matchID] ?? dashboard?.menteeDashboard.messages ?? []
        } else {
            source = dashboard?.menteeDashboard.messages ?? []
        }
        // Sort chronologically (oldest → newest). Messages come from two
        // sources — the dashboard snapshot and SSE `message.created` events —
        // each with their own ordering, so normalise on read for a stable
        // chat transcript.
        return source.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Auth

    func signIn(username: String, password: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.signIn(username: username, password: password)
            applySession(session)
            statusMessage = nil
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Sign in with Apple. The caller (AuthViews) hands us the verified
    /// identityToken from `ASAuthorizationAppleIDCredential` plus the
    /// optional name Apple returns on first sign-in. Backend handles the
    /// rest — verifying the token, linking or creating the account, and
    /// returning the same JWT pair as password login.
    func signInWithApple(identityToken: String, displayName: String?) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.signInWithApple(
                identityToken: identityToken,
                displayName: displayName
            )
            applySession(session)
            statusMessage = nil
            errorMessage = nil
            authRequestState = .success(())
            // Setup overlay decision, in priority order:
            //   1. session.isNewUser  → fresh Apple account, always show setup.
            //   2. server says profileSetupCompleted=false → user quit
            //      mid-setup on a previous launch (or different device);
            //      re-land them on the setup screen synchronously off
            //      this auth response, no dashboard flash.
            //   3. server says profileSetupCompleted=true → clear the
            //      flag (covers users who finished setup elsewhere).
            //   4. server omitted the field (legacy backend) → defer to
            //      the existing async /me reconcile path.
            let serverCompleted = session.profileSetupCompleted
            let needsSetup = session.isNewUser || (serverCompleted == false)
            if needsSetup {
                requiresProfileSetup = true
                if let uid = currentUserId {
                    UserDefaults.standard.set(true, forKey: Self.profileSetupPendingKey(for: uid))
                }
                if session.isNewUser { justRegistered = true }
                // Stash whatever Apple returned in `fullName` (only
                // populated on the very first authorization) so the
                // setup screen can prefill the "Your name" field.
                // When this is nil, the screen requires the user to
                // type a name — that's the fix for private-relay
                // email accounts that previously ended up with a
                // random-looking hash as their display name.
                let trimmed = displayName?.trimmingCharacters(in: .whitespaces) ?? ""
                pendingAppleFullName = trimmed.isEmpty ? nil : trimmed
            } else if serverCompleted == true {
                requiresProfileSetup = false
                if let uid = currentUserId {
                    UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
                }
                pendingAppleFullName = nil
            } else {
                // Legacy backend (no flag in response) — let the async
                // reconcile decide. Don't touch requiresProfileSetup so
                // any UserDefaults primer set earlier survives.
                pendingAppleFullName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Submits the user's chosen username + avatar to the backend after
    /// a fresh Apple sign-up. Clears `requiresProfileSetup` on success
    /// so the UI can hand off to the regular onboarding flow.
    ///
    /// Error shape matters here — the backend may *succeed* on write but
    /// the client may fail to decode the response (e.g. a Jackson schema
    /// drift). In that case we'd soft-lock the user on the setup screen
    /// despite the profile being persisted. To avoid the loop, we
    /// inspect the error: `invalidResponse` means the server likely
    /// committed; every other case (network, 4xx with recognizable
    /// message) leaves the flag set so the user can retry.
    func setupAppleProfile(username: String, avatarURL: String, displayName: String?) async -> Bool {
        authRequestState = .loading; refreshSyncingState()
        defer { refreshSyncingState() }
        do {
            try await authRepository.setupProfile(
                username: username,
                avatarURL: avatarURL,
                displayName: displayName
            )
            if let uid = currentUserId {
                UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
            }
            requiresProfileSetup = false
            pendingAppleFullName = nil
            errorMessage = nil
            authRequestState = .success(())
            return true
        } catch {
            // No more silently-pretend-success on invalidResponse — that path
            // masked half-provisioned accounts where the server actually
            // failed but the decoder happened to throw before we could
            // surface the failure. Always surface the error so the user
            // re-prompts; `requiresProfileSetup` stays true so they can retry.
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
            return false
        }
    }

    /// Cold-launch reconciliation against the V15 `profile_setup_completed`
    /// flag. Local UserDefaults primes the overlay before the network
    /// returns; this method is the source of truth that overrides it.
    /// Silently no-ops on network failure — the local primer is the
    /// fallback, so the worst case is a one-launch lag in either
    /// direction.
    private func reconcileProfileSetupFromServer() async {
        guard isAuthenticated else { return }
        do {
            let status = try await authRepository.fetchMe()
            await MainActor.run {
                if status.profileSetupCompleted {
                    if requiresProfileSetup {
                        requiresProfileSetup = false
                    }
                    if let uid = currentUserId {
                        UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
                    }
                } else {
                    requiresProfileSetup = true
                    if let uid = currentUserId {
                        UserDefaults.standard.set(true, forKey: Self.profileSetupPendingKey(for: uid))
                    }
                }
            }
        } catch {
            // Silent — Fix-A's UserDefaults flag (if any) already drove
            // the right initial state.
        }
    }

    /// Live availability probe used by the profile-setup screen so the
    /// "this is taken" feedback is in front of the user before they tap
    /// Continue. Falls back to `true` on transient network errors so a
    /// flaky connection doesn't permanently block the screen.
    func isUsernameAvailable(_ username: String) async -> Bool {
        do {
            return try await authRepository.isUsernameAvailable(username)
        } catch {
            return true
        }
    }

    func requestEmailVerification(email: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            try await authRepository.requestEmailVerification(email: email)
            statusMessage = "Verification code sent to \(email)"
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func register(
        username: String,
        email: String,
        password: String,
        avatarURL: String,
        verificationCode: String
    ) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.register(
                username: username,
                email: email,
                password: password,
                avatarURL: avatarURL,
                verificationCode: verificationCode
            )
            applySession(session)
            justRegistered = true
            statusMessage = nil
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
        stopUserStream()
        // Invalidate the SSE transport so any bytes still in flight from the
        // prior session don't leak into a subsequent sign-in. Without this,
        // signing in as a different user could see the previous user's
        // residual `habits.changed` events bleed through.
        resetSseSession()
        clearSession()
        Task {
            await apiClient.logout()
            await apiClient.clearSession()
        }
    }

    func deleteAccount() async {
        do {
            let _: EmptyResponse = try await apiClient.authorizedRequest(
                path: "/api/users/me", method: "DELETE"
            )
            errorMessage = nil
            statusMessage = "Account deleted from server."
            // Tell the dashboard to wipe SwiftData before signOut clears
            // tokens — otherwise any in-flight 401 handling could race
            // the local-data wipe.
            NotificationCenter.default.post(name: .rungAccountDeleted, object: nil)
            signOut()
        } catch {
            errorMessage = "Couldn’t delete account on server: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private struct EmptyResponse: Decodable {}

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

    func listTasks() async throws -> [BackendHabit] {
        habitListRequestState = .loading; refreshSyncingState()
        do {
            let tasks = try await habitRepository.listTasks()
            await syncSessionFromClient()
            habitListRequestState = .success(tasks)
            errorMessage = nil
            refreshSyncingState()
            return tasks
        } catch {
            handleAuthenticatedRequestError(error)
            habitListRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    /// LLM frequency-parse fallback. Returns `nil` if the user isn't
    /// authenticated, the network call fails, or the LLM couldn't extract
    /// a cadence. Callers fall through to the user's untouched input on
    /// nil — never block the UX waiting for AI.
    func parseHabitFrequencyWithAI(text: String) async -> ParseFrequencyResult? {
        guard token != nil else { return nil }
        do {
            let result = try await habitRepository.parseHabitFrequency(text: text)
            return result.didMatch ? result : nil
        } catch {
            return nil
        }
    }

    /// Push the local sleep snapshot to the backend so other devices
    /// (notably macOS, where HK isn't available) can read what iOS
    /// computed. Fire-and-forget — failures don't bubble up to the UI.
    func uploadSleepSnapshot(_ snapshot: BackendSleepSnapshot) async {
        guard token != nil else { return }
        _ = try? await sleepSnapshotRepository.upload(snapshot)
    }

    /// Read the most recent server-side snapshot. Used by macOS to
    /// hydrate `SleepInsightsService` when local HK data isn't available.
    /// Returns nil on no-row, network failure, or unauthenticated state.
    func fetchSleepSnapshot() async -> BackendSleepSnapshot? {
        guard token != nil else { return nil }
        return try? await sleepSnapshotRepository.fetch()
    }

    func createHabit(
        title: String,
        reminderWindow: String? = nil,
        canonicalKey: String? = nil,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        verificationParam: Double? = nil,
        weeklyTarget: Int? = nil
    ) async throws -> BackendHabit {
        createHabitRequestState = .loading; refreshSyncingState()
        do {
            let habit = try await habitRepository.createHabit(
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
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

    func createTask(title: String) async throws -> BackendHabit {
        createHabitRequestState = .loading; refreshSyncingState()
        do {
            let task = try await habitRepository.createTask(title: title)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            createHabitRequestState = .success(task)
            errorMessage = nil
            refreshSyncingState()
            return task
        } catch {
            handleAuthenticatedRequestError(error)
            createHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
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
        updateHabitRequestState = .loading; refreshSyncingState()
        do {
            let habit = try await habitRepository.updateHabit(
                habitID: habitID,
                title: title,
                reminderWindow: reminderWindow,
                canonicalKey: canonicalKey,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                verificationParam: verificationParam,
                weeklyTarget: weeklyTarget
            )
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            updateHabitRequestState = .success(habit)
            errorMessage = nil
            refreshSyncingState()
            return habit
        } catch {
            handleAuthenticatedRequestError(error)
            updateHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func updateTask(taskID: Int64, title: String) async throws -> BackendHabit {
        updateHabitRequestState = .loading; refreshSyncingState()
        do {
            let task = try await habitRepository.updateTask(taskID: taskID, title: title)
            await syncSessionFromClient()
            await responseCache.invalidateHabits()
            updateHabitRequestState = .success(task)
            errorMessage = nil
            refreshSyncingState()
            return task
        } catch {
            handleAuthenticatedRequestError(error)
            updateHabitRequestState = .failure(error.localizedDescription)
            refreshSyncingState()
            throw error
        }
    }

    func setCheck(
        habitID: Int64,
        dateKey: String,
        done: Bool,
        verificationTier: String? = nil,
        verificationSource: String? = nil,
        durationSeconds: Int? = nil
    ) async throws {
        checkUpdateRequestState = .loading; refreshSyncingState()
        do {
            _ = try await habitRepository.setCheck(
                habitID: habitID, dateKey: dateKey, done: done,
                verificationTier: verificationTier,
                verificationSource: verificationSource,
                durationSeconds: durationSeconds
            )
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

    func setTaskCheck(
        taskID: Int64,
        dateKey: String,
        done: Bool,
        durationSeconds: Int? = nil
    ) async throws {
        checkUpdateRequestState = .loading; refreshSyncingState()
        do {
            _ = try await habitRepository.setTaskCheck(
                taskID: taskID, dateKey: dateKey, done: done,
                durationSeconds: durationSeconds
            )
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

    // MARK: - Verification

    /// Runs HealthKit (or other external-signal) verification for a freshly
    /// toggled-done habit and persists the resulting `HabitCompletion` record.
    ///
    /// Intentionally separate from `setCheck` so the server round-trip and the
    /// verification round-trip run independently — neither blocks the other,
    /// and a HealthKit auth denial never prevents a check from syncing.
    ///
    /// Callers should fire this fire-and-forget from their toggle path
    /// (usually inside the same Task that runs `setCheck`), only when `done`
    /// is transitioning false→true. Replays from the sync outbox should skip
    /// this — verification already ran the first time the user toggled.
    func verifyCompletion(habit: Habit, dayKey: String, modelContext: ModelContext) async {
        guard let source = habit.verificationSource, source != .selfReport else { return }
        // Snapshot primitives off the @Model before crossing into the
        // VerificationService actor so we don't pass a non-Sendable Habit
        // across the boundary.
        let backendId = habit.backendId
        let tier = habit.verificationTier
        let param = habit.verificationParam
        // Seed a stable UUID on the habit the first time we verify it so
        // evidence records can be reconciled to this habit before its
        // backendId exists. On subsequent calls we return the same UUID.
        let localId = habit.ensureLocalUUID()

        let completion = await VerificationService.shared.verify(
            habitBackendId: backendId,
            habitLocalId: localId,
            source: source,
            tier: tier,
            param: param,
            dayKey: dayKey
        )

        modelContext.insert(completion)
        try? modelContext.save()
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

    func deleteTask(taskID: Int64) async throws {
        deleteHabitRequestState = .loading; refreshSyncingState()
        do {
            try await habitRepository.deleteTask(taskID: taskID)
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
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        if let lastAt = lastSentMessageAt, now.timeIntervalSince(lastAt) < 0.8 {
            statusMessage = "You're sending too fast. Try again."
            return
        }
        if
            let lastText = lastSentMessageText,
            let lastAt = lastSentMessageAt,
            now.timeIntervalSince(lastAt) < 5,
            lastText.caseInsensitiveCompare(trimmed) == .orderedSame
        {
            statusMessage = "Duplicate message blocked."
            return
        }

        lastSentMessageAt = now
        lastSentMessageText = trimmed
        messageRequestState = .loading; refreshSyncingState()

        // Immediately raise the "mentor is typing…" indicator for AI matches
        // so the UI has something to show during the async Gemini round-trip.
        // Cleared in `appendMessage` the moment the AI reply lands via SSE,
        // or after a safety timeout if the stream is slow.
        let isAI = dashboard?.match?.aiMentor ?? false
        if isAI {
            setAIMentorTyping(true, matchId: matchId)
        }
        do {
            let value = try await accountabilityRepository.sendMenteeMessage(matchId: matchId, message: trimmed)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            messageRequestState = .success(())
            errorMessage = nil
        } catch {
            setAIMentorTyping(false, matchId: matchId)
            handleAuthenticatedRequestError(error)
            messageRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Flips the typing indicator on/off. While the indicator is on, also
    /// runs a light polling loop that refreshes the dashboard every 3s as a
    /// fallback for any case where the SSE event gets dropped (flaky
    /// network, proxy buffering, etc.) — a dashboard refresh will pick up
    /// the AI message via the merge in `applyDashboardUpdate`, which in
    /// turn fires `appendMessage` and clears this indicator.
    private func setAIMentorTyping(_ typing: Bool, matchId: Int64) {
        aiMentorTyping = typing
        aiMentorTypingTimeoutTask?.cancel()
        aiMentorTypingTimeoutTask = nil
        guard typing else { return }
        aiMentorTypingTimeoutTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            let poll: TimeInterval = 3
            let maxWait: TimeInterval = 45
            while elapsed < maxWait {
                try? await Task.sleep(for: .seconds(poll))
                if Task.isCancelled { return }
                guard let self, self.aiMentorTyping else { return }
                await self.responseCache.invalidateDashboard()
                await self.refreshDashboard()
                elapsed += poll
            }
            // Hard timeout — clear the indicator so the UI doesn't hang
            // forever if the AI call failed silently.
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.aiMentorTyping = false }
        }
    }

    func requestFriend(userID: Int64) async {
        guard token != nil else { return }
        friendRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.requestFriend(friendUserID: userID)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            friendSearchResults.removeAll { $0.userId == userID }
            statusMessage = "Following"
            errorMessage = nil
            friendRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            friendRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func searchFriends(query: String) async {
        guard token != nil else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            friendSearchResults = []
            friendSearchRequestState = .idle
            refreshSyncingState()
            return
        }

        friendSearchRequestState = .loading; refreshSyncingState()
        do {
            let results = try await accountabilityRepository.searchFriends(query: trimmed)
            await syncSessionFromClient()
            friendSearchResults = results
            friendSearchRequestState = .success(results)
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
            friendSearchRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func useStreakFreeze(dateKey: String) async {
        guard token != nil else { return }
        streakFreezeRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.useStreakFreeze(dateKey: dateKey)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Streak freeze applied for \(dateKey)"
            errorMessage = nil
            streakFreezeRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            streakFreezeRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Reverts the most recent streak-freeze usage, provided the server is
    /// still within its undo grace window. Paired with the 5-second undo
    /// banner in `StreakFreezeCard`.
    func undoStreakFreeze() async {
        guard token != nil else { return }
        streakFreezeRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.undoStreakFreeze()
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Streak freeze undone"
            errorMessage = nil
            streakFreezeRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            streakFreezeRequestState = .failure(error.localizedDescription)
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

    func sendNudge(matchId: Int64) async {
        guard token != nil else { return }
        do {
            let value = try await accountabilityRepository.sendNudge(matchId: matchId)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    // MARK: - Preferences

    func loadPreferences() async {
        guard token != nil else { return }
        preferencesRequestState = .loading
        do {
            let value = try await preferencesRepository.get()
            preferences = value
            preferencesRequestState = .success(value)
        } catch {
            handleAuthenticatedRequestError(error)
            preferencesRequestState = .failure(error.localizedDescription)
        }
    }

    /// Optimistically flips the local toggle, then syncs with the server. On
    /// failure the previous value is restored so the UI never disagrees with
    /// the persisted state.
    func setEmailOptIn(_ enabled: Bool) async {
        guard token != nil else { return }
        let previous = preferences
        preferences = UserPreferences(emailOptIn: enabled)
        preferencesRequestState = .loading
        do {
            let value = try await preferencesRepository.update(emailOptIn: enabled)
            preferences = value
            preferencesRequestState = .success(value)
        } catch {
            preferences = previous
            handleAuthenticatedRequestError(error)
            preferencesRequestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - SSE Stream

    private func applyDashboardUpdate(_ value: AccountabilityDashboard) {
        dashboard = value
        WidgetSnapshotWriter.shared.updateBackendData(value)
        if let matchID = value.match?.id {
            // Snapshot the highest known message id before merging so we can
            // tell whether the dashboard payload carried a fresh AI reply —
            // otherwise the typing indicator hangs until its safety timeout
            // because SSE may deliver the event after this merge has already
            // de-duplicated it away.
            let prevMaxId = (liveMessagesByMatch[matchID] ?? []).map(\.id).max() ?? 0

            // Merge the dashboard snapshot with whatever SSE has already
            // delivered — dropping existing live entries would wipe an AI
            // reply that landed between the server's snapshot time and the
            // client applying the response.
            var merged: [Int64: AccountabilityDashboard.Message] = [:]
            for msg in value.menteeDashboard.messages { merged[msg.id] = msg }
            for msg in liveMessagesByMatch[matchID] ?? [] { merged[msg.id] = msg }
            liveMessagesByMatch[matchID] = merged.values.sorted { $0.createdAt < $1.createdAt }

            if aiMentorTyping, let match = value.match, match.aiMentor {
                let mentorId = match.mentor.userId
                let gotFreshAIReply = merged.values.contains { $0.senderId == mentorId && $0.id > prevMaxId }
                if gotFreshAIReply { setAIMentorTyping(false, matchId: matchID) }
            }

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
        refreshSyncingState()
    }

    // MARK: - Per-user SSE (cross-device real-time sync)

    private func startUserStream() {
        if userStreamTask != nil { return }
        userStreamTask = Task { [weak self] in await self?.runUserStreamLoop() }
    }

    private func stopUserStream() {
        userStreamTask?.cancel()
        userStreamTask = nil
        lastUserStreamEventID = nil
    }

    private func runUserStreamLoop() async {
        var backoffSeconds: TimeInterval = 1
        var attempt = 0
        while !Task.isCancelled, isAuthenticated {
            attempt += 1
            HabitBackendStore.sseLog("[UserStream] attempt #\(attempt) connecting…")
            do {
                let request = try await accountabilityRepository.userStreamRequest(
                    lastEventID: lastUserStreamEventID
                )
                let (bytes, response) = try await sseSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    HabitBackendStore.sseLog("[UserStream] connect failed — status \(code)")
                    throw HabitBackendError.invalidResponse
                }
                HabitBackendStore.sseLog("[UserStream] connected (attempt #\(attempt))")
                backoffSeconds = 1
                try await consumeUserStreamLines(lines: bytes.lines)
                HabitBackendStore.sseLog("[UserStream] disconnected (peer closed) — will reconnect")
            } catch {
                if Task.isCancelled {
                    HabitBackendStore.sseLog("[UserStream] task cancelled — exiting loop")
                    return
                }
                HabitBackendStore.sseLog("[UserStream] error: \(error.localizedDescription) — retrying in \(Int(backoffSeconds))s")
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
        HabitBackendStore.sseLog("[UserStream] loop exited (cancelled=\(Task.isCancelled) authed=\(isAuthenticated))")
    }

    private func consumeUserStreamLines<S: AsyncSequence>(lines: S) async throws where S.Element == String {
        var eventName = "message"
        var eventID: String?
        var dataLines: [String] = []

        for try await raw in lines {
            if Task.isCancelled { return }
            if raw.isEmpty {
                // Blank line = event boundary.
                let payload = dataLines.joined(separator: "\n")
                if !payload.isEmpty {
                    handleUserStreamEvent(name: eventName, id: eventID, payload: payload)
                }
                eventName = "message"; eventID = nil; dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if raw.hasPrefix("event:") { eventName = raw.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("id:")    { eventID   = raw.dropFirst(3).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("data:")  { dataLines.append(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func handleUserStreamEvent(name: String, id: String?, payload: String) {
        if let id = id, !id.isEmpty { lastUserStreamEventID = id }
        switch name {
        case "habits.changed":
            HabitBackendStore.sseLog("[UserStream] habits.changed received id=\(id ?? "-") payload=\(payload)")
            Task {
                await responseCache.invalidateHabits()
                await responseCache.invalidateDashboard()
                HabitBackendStore.sseLog("[UserStream] cache invalidated; posting .habitsChangedSSE")
                await MainActor.run {
                    NotificationCenter.default.post(name: .habitsChangedSSE, object: nil)
                }
            }
        case "prefs.changed":
            // Profile (username/avatar/displayName) or settings
            // (weekly-report toggle) changed on another device. Refresh
            // both — dashboard caches displayName/avatar and the
            // preferences endpoint backs the email-opt-in toggle.
            #if DEBUG
            HabitBackendStore.sseLog("[UserStream] prefs.changed received id=\(id ?? "-")")
            #endif
            Task { @MainActor in
                await responseCache.invalidateDashboard()
                await loadPreferences()
                await refreshDashboard()
                // Push the fresh displayName into Widgets so they stop
                // rendering the stale name. Without this, the rename appears
                // in the dashboard within seconds but Widgets can lag for
                // hours until the next foreground tick.
                // (Live Activity content state is streak-only — it doesn't
                // carry displayName, so no update is needed here.)
                WidgetSnapshotWriter.shared.refresh()
            }
        case "session.revoked":
            // Server hard-deleted the current user (or revoked the
            // session for some other reason). Wipe local SwiftData
            // first — ContentView listens on `.rungAccountDeleted`
            // — then tear the session down so the auth flow appears
            // immediately. After this, signing in with the same Apple
            // ID provisions a fresh account; previous habits are gone.
            HabitBackendStore.sseLog("[UserStream] session.revoked received id=\(id ?? "-") payload=\(payload)")
            Task { @MainActor in
                NotificationCenter.default.post(name: .rungAccountDeleted, object: nil)
                signOut()
            }
        case "ping", "stream.ready":
            break
        default:
            HabitBackendStore.sseLog("[UserStream] unknown event '\(name)'")
        }
    }

    private func runStreamLoop(matchID: Int64) async {
        var hadSuccessfulConnection = false
        var backoffSeconds: TimeInterval = 1

        while !Task.isCancelled, streamingMatchID == matchID, isAuthenticated {
            do {
                streamRequestState = .loading
                refreshSyncingState()
                let request = try await accountabilityRepository.streamRequest(
                    matchId: matchID, lastEventID: lastStreamEventID
                )
                // Use the shared sseSession (not URLSession.shared) so signOut
                // can invalidate it cleanly — URLSession.shared is global and
                // can't be reset without affecting other consumers.
                let (bytes, response) = try await sseSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw HabitBackendError.invalidResponse
                }
                if hadSuccessfulConnection { await refreshDashboard() }
                hadSuccessfulConnection = true
                backoffSeconds = 1  // reset on successful connect
                streamRequestState = .success(())
                refreshSyncingState()
                try await consumeSSELines(matchID: matchID, lines: bytes.lines)
            } catch {
                if Task.isCancelled { return }
                streamRequestState = .failure(error.localizedDescription)
                refreshSyncingState()
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
        // Clear the "typing…" indicator the moment a message from the AI
        // mentor is observed. Run this *before* the dedup guard so SSE
        // re-deliveries (server may emit the event after the dashboard
        // snapshot already imported the row) still clear the indicator.
        if let match = dashboard?.match,
           match.id == matchID,
           match.aiMentor,
           message.senderId == match.mentor.userId {
            setAIMentorTyping(false, matchId: matchID)
        }

        var msgs = liveMessagesByMatch[matchID] ?? []
        guard !msgs.contains(where: { $0.id == message.id }) else { return }
        msgs.append(message)
        // Sort chronologically so the chat view doesn't depend on insertion
        // order (dashboard snapshot + SSE deliveries can interleave).
        msgs.sort { $0.createdAt < $1.createdAt }
        if msgs.count > 60 { msgs = Array(msgs.suffix(60)) }
        liveMessagesByMatch[matchID] = msgs
    }

    // MARK: - Error handling

    private func handleAuthenticatedRequestError(_ error: Error) {
        if case HabitBackendError.notAuthenticated = error {
            clearSession(errorMessage: error.localizedDescription)
            Task { await apiClient.clearSession() }
            return
        }
        // Network failures while offline are expected — the outbox will retain
        // the change and flushOutbox will retry once connectivity returns.
        // Surface a single soft status line instead of a per-request error toast.
        if case HabitBackendError.network = error {
            errorMessage = Self.offlineStatusMessage
            return
        }
        // 404s mean the local store is out of sync with the server (e.g. a
        // habit was deleted on another device). Don't show the raw "habit
        // not found" message — bump the staleness tick so the dashboard
        // re-fetches and the reconcile heals the divergence with server
        // state as the source of truth.
        if case HabitBackendError.notFound = error {
            errorMessage = nil
            staleResourceTick &+= 1
            return
        }
        errorMessage = error.localizedDescription
    }

    private func refreshSyncingState() {
        isSyncing = authRequestState.isLoading
            || habitListRequestState.isLoading
            || dashboardRequestState.isLoading
            || createHabitRequestState.isLoading
            || updateHabitRequestState.isLoading
            || checkUpdateRequestState.isLoading
            || deleteHabitRequestState.isLoading
            || mentorRequestState.isLoading
            || messageRequestState.isLoading
            || friendRequestState.isLoading
            || friendSearchRequestState.isLoading
            || streamRequestState.isLoading
            || streakFreezeRequestState.isLoading
    }

    // MARK: - Session persistence

    private func applySession(_ session: BackendSession) {
        token = session.accessToken
        KeychainSessionStore.save(session)
        // Open the per-user SSE stream so cross-device habit writes
        // flow to us in seconds instead of on the next 5-min timer.
        // Idempotent — skipped if a stream is already running.
        startUserStream()
    }

    private func syncSessionFromClient() async {
        let session = await apiClient.currentSession()
        token = session?.accessToken
        if let session {
            KeychainSessionStore.save(session)
        } else {
            KeychainSessionStore.delete()
        }
    }

    private func clearSession(errorMessage: String? = nil) {
        // Capture the outgoing user id before nil'ing the token so we can
        // clear their persisted profile-setup flag — otherwise a stale
        // entry would survive a sign-out and re-trigger the overlay if
        // someone signed back in to the same account.
        let outgoingUserId = currentUserId
        stopStream()
        stopUserStream()
        token = nil; dashboard = nil; liveMessagesByMatch = [:]
        WidgetSnapshotWriter.shared.clearBackendData()
        friendSearchResults = []
        preferences = nil
        preferencesRequestState = .idle
        lastSentMessageAt = nil; lastSentMessageText = nil
        statusMessage = nil; self.errorMessage = errorMessage
        justRegistered = false
        requiresProfileSetup = false
        pendingAppleFullName = nil
        KeychainSessionStore.delete()
        UserDefaults.standard.removeObject(forKey: Self.legacySessionKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        if let uid = outgoingUserId {
            UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
        }
        authRequestState = .idle; habitListRequestState = .idle; dashboardRequestState = .idle
        createHabitRequestState = .idle; updateHabitRequestState = .idle; checkUpdateRequestState = .idle
        deleteHabitRequestState = .idle; mentorRequestState = .idle
        messageRequestState = .idle; friendRequestState = .idle
        friendSearchRequestState = .idle
        streakFreezeRequestState = .idle
        Task { await responseCache.invalidateAll() }
        refreshSyncingState()
    }

    /// Returns the current session, migrating any UserDefaults-era payload into the Keychain.
    private static func loadSession() -> BackendSession? {
        if let keychained = KeychainSessionStore.load() {
            return keychained
        }

        // One-time migration from UserDefaults.
        if
            let data = UserDefaults.standard.data(forKey: legacySessionKey),
            let session = try? JSONDecoder().decode(BackendSession.self, from: data)
        {
            KeychainSessionStore.save(session)
            UserDefaults.standard.removeObject(forKey: legacySessionKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            return session
        }
        if let legacy = UserDefaults.standard.string(forKey: legacyTokenKey) {
            let session = BackendSession.fromLegacyToken(legacy)
            KeychainSessionStore.save(session)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            return session
        }
        return nil
    }
}
