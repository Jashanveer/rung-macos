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

    @Published var token: String?
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
    @Published var isOnline: Bool = true
    /// One-shot flag set by `requestRecoveryFreezeIfFatigued()` when the
    /// backend grants a recovery freeze for the first time today. The
    /// dashboard observes this and flashes a "rest day, freeze added"
    /// toast, then resets the flag. Idempotent — flipping it back to
    /// false after the toast prevents duplicate banners on re-renders.
    @Published var recoveryFreezeJustGranted: Bool = false

    // Per-endpoint request states — UI can show per-section loading/error indicators
    @Published var authRequestState:        RequestState<Void>                    = .idle
    @Published var habitListRequestState:   RequestState<[BackendHabit]>           = .idle
    @Published var dashboardRequestState:   RequestState<AccountabilityDashboard>  = .idle
    @Published var createHabitRequestState: RequestState<BackendHabit>             = .idle
    @Published var updateHabitRequestState: RequestState<BackendHabit>             = .idle
    @Published var checkUpdateRequestState: RequestState<Void>                    = .idle
    @Published var deleteHabitRequestState: RequestState<Void>                    = .idle
    @Published var mentorRequestState:      RequestState<Void>                    = .idle
    @Published var messageRequestState:     RequestState<Void>                    = .idle
    @Published var friendRequestState:      RequestState<Void>                    = .idle
    @Published var friendSearchRequestState: RequestState<[AccountabilityDashboard.FriendSummary]> = .idle
    @Published var friendSearchResults: [AccountabilityDashboard.FriendSummary] = []
    @Published var streakFreezeRequestState: RequestState<Void>                   = .idle
    @Published var streamRequestState:      RequestState<Void>                    = .idle
    @Published var preferencesRequestState: RequestState<UserPreferences>         = .idle
    @Published var preferences:             UserPreferences?                       = nil
    /// Cross-device-synced source of truth for today's coaching headline,
    /// meeting summary, and per-habit "Try HH:MM" hints. Nil before the
    /// first refresh of the day; once set, the UI binds against this so
    /// every device renders the same payload regardless of which one's
    /// EventKit visibility is the richest. See `HabitBackend+Suggestions`.
    @Published var dailySuggestion:         DailySuggestionPayload?                = nil
    /// In-flight guard so concurrent CenterPanel renders don't fire two
    /// suggestion refreshes at once. Reset to nil when the task ends.
    var dailySuggestionRefreshTask: Task<Void, Never>?
    /// Persisted outbox of mentor messages the user wrote while the
    /// device was offline. Drained by `flushMentorMessageOutbox` on the
    /// next `NetworkMonitor.isOnline` flip. Published so chat bubbles
    /// can render a "queued · will send when online" pill on each
    /// pending entry — see `HabitBackend+MessageOutbox`.
    @Published var outboundMentorMessages: [Int64: [OutboundMentorMessage]] = [:]
    @Published var liveMessagesByMatch:     [Int64: [AccountabilityDashboard.Message]] = [:]
    /// True while we're waiting on the AI mentor to deliver a reply to the
    /// mentee's latest message. Drives the "mentor is typing…" bubble in
    /// MentorChatBubble. Flipped on in `sendMenteeMessage` for AI matches
    /// and cleared the moment a new AI mentor message arrives via SSE (or
    /// after a generous timeout, as a safety net).
    @Published var aiMentorTyping: Bool = false
    var aiMentorTypingTimeoutTask: Task<Void, Never>?

    // MARK: Private

    // Legacy UserDefaults keys — read once at launch and migrated to the Keychain.
    static let legacySessionKey = "habitTracker.localhost.session.v1"
    static let legacyTokenKey   = "habitTracker.localhost.token"

    /// Per-user UserDefaults key for the in-progress profile-setup flag.
    /// Persisting this is what lets a user who quits the app mid-setup
    /// land back on the username/avatar screen on relaunch instead of
    /// the dashboard with the auto-generated placeholder handle.
    static func profileSetupPendingKey(for userId: String) -> String {
        "rung.requiresProfileSetup.\(userId)"
    }
    let apiClient: BackendAPIClient
    let authRepository: AuthRepository
    let habitRepository: HabitRepository
    let accountabilityRepository: AccountabilityRepository
    let deviceRepository: DeviceRepository
    let preferencesRepository: PreferencesRepository
    let dailySuggestionRepository: DailySuggestionRepository
    let sleepSnapshotRepository: SleepSnapshotRepository
    let watchSnapshotRepository: WatchSnapshotRepository
    let circleRepository: CircleRepository
    /// Shared response cache; invalidated by any write that mutates the cached resource.
    let responseCache = ResponseCache()
    var streamTask: Task<Void, Never>?
    var streamingMatchID: Int64?
    var lastStreamEventID: String?
    /// Long-lived per-user SSE task. Connects on authentication,
    /// reconnects with exponential backoff on disconnect, and posts
    /// `.habitsChangedSSE` whenever the server publishes that another
    /// device mutated a habit so ContentView can trigger sync in seconds.
    var userStreamTask: Task<Void, Never>?
    var lastUserStreamEventID: String?
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
    var sseSession: URLSession = HabitBackendStore.makeSseSession()

    static func makeSseSession() -> URLSession {
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
    func resetSseSession() {
        sseSession.invalidateAndCancel()
        sseSession = HabitBackendStore.makeSseSession()
    }

    /// DEBUG-only logger for the per-user SSE channel. The user-stream loop
    /// is chatty (one line per connect / event / disconnect) and the
    /// `habits.changed` payload contains user data — neither belongs in
    /// Release builds where it lands in the device's unified log.
    @inline(__always)
    static func sseLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
    var lastSentMessageAt: Date?
    var lastSentMessageText: String?
    let networkMonitor = NetworkMonitor()
    var networkCancellable: AnyCancellable?

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
        dailySuggestionRepository = DailySuggestionRepository(client: client)
        sleepSnapshotRepository   = SleepSnapshotRepository(client: client)
        watchSnapshotRepository   = WatchSnapshotRepository(client: client)
        circleRepository          = CircleRepository(client: client)

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

        // Hydrate the persisted mentor-message outbox so any messages
        // queued before the previous launch terminated land back in
        // the published map immediately. Drains on the next online flip.
        loadOutboundMentorMessagesFromDisk()

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
                    // Drain any queued mentor messages now that we're
                    // back online. Errors are kept silent — pending
                    // entries stay in the outbox for the next flip.
                    Task { [weak self] in
                        await self?.flushMentorMessageOutbox()
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
    static let offlineStatusMessage = "Offline — changes will sync when you're back online."

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
        let sorted = source.sorted { $0.createdAt < $1.createdAt }
        // 24-hour visibility window — anything older drops out of the
        // chat surface. Server retains the row so search / mentor
        // history endpoints still see it; the UI just doesn't surface
        // stale conversation. Messages without a parseable timestamp
        // are kept (server is authoritative — drop only when we're
        // certain the message is older than 24h).
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return sorted.filter { msg in
            guard let date = ChatMessageRow.parseISO(msg.createdAt) else { return true }
            return date >= cutoff
        }
    }

    // MARK: - Error handling

    func handleAuthenticatedRequestError(_ error: Error) {
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

    func refreshSyncingState() {
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

    func applySession(_ session: BackendSession) {
        token = session.accessToken
        KeychainSessionStore.save(session)
        // Open the per-user SSE stream so cross-device habit writes
        // flow to us in seconds instead of on the next 5-min timer.
        // Idempotent — skipped if a stream is already running.
        startUserStream()
    }

    func syncSessionFromClient() async {
        let session = await apiClient.currentSession()
        token = session?.accessToken
        if let session {
            KeychainSessionStore.save(session)
        } else {
            KeychainSessionStore.delete()
        }
    }

    func clearSession(errorMessage: String? = nil) {
        // Capture the outgoing user id before nil'ing the token so we can
        // clear their persisted profile-setup flag — otherwise a stale
        // entry would survive a sign-out and re-trigger the overlay if
        // someone signed back in to the same account.
        let outgoingUserId = currentUserId
        let wasAuthenticated = token != nil
        stopStream()
        stopUserStream()
        token = nil; dashboard = nil; liveMessagesByMatch = [:]

        // Broadcast session-expired BEFORE the rest of clearSession
        // tears down state — any open sheet picks this up and dismisses
        // cleanly instead of being stranded on top of the auth view.
        // Only fire when we *had* a session; calling clearSession on a
        // brand-new launch shouldn't ping every sheet.
        if wasAuthenticated {
            NotificationCenter.default.post(name: .rungSessionExpired, object: errorMessage)
            #if os(iOS)
            // Push an empty snapshot to the Watch so the wrist falls
            // back to the "Open Rung on iPhone" connecting state. Without
            // this, the Watch would keep rendering the previous user's
            // habits + leaderboard until the next phone-side push.
            WatchConnectivityService.shared.pushSignedOutSnapshot()
            #endif
        }
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
