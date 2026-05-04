import Foundation

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

    // MARK: - Reminders

    /// Lists every reminder for a habit. The legacy `reminderWindow`
    /// column on `Habit` stays populated for backward compat, but the
    /// rich per-habit reminder list lives in this separate endpoint.
    func listReminders(habitID: Int64) async throws -> [HabitReminder] {
        try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/reminders",
            method: "GET"
        )
    }

    /// Creates a reminder. Returns the persisted record with its
    /// backend-assigned id, which the caller stores so subsequent
    /// edits hit `PATCH /reminders/{id}` instead of duplicating.
    func createReminder(habitID: Int64, reminder: HabitReminder) async throws -> HabitReminder {
        try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/reminders",
            method: "POST",
            body: ReminderWriteRequest(reminder: reminder)
        )
    }

    func updateReminder(habitID: Int64, reminderID: Int64, reminder: HabitReminder) async throws -> HabitReminder {
        try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/reminders/\(reminderID)",
            method: "PATCH",
            body: ReminderWriteRequest(reminder: reminder)
        )
    }

    func deleteReminder(habitID: Int64, reminderID: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/habits/\(habitID)/reminders/\(reminderID)",
            method: "DELETE"
        )
    }

    private struct ReminderWriteRequest: Encodable {
        let kind: String
        let payload: String?
        let weekdayMask: Int?
        let snoozeMinutes: Int?
        let enabled: Bool

        init(reminder: HabitReminder) {
            self.kind = reminder.kind.rawValue
            self.payload = reminder.payload
            self.weekdayMask = reminder.weekdayMask
            self.snoozeMinutes = reminder.snoozeMinutes
            self.enabled = reminder.enabled
        }
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

/// Networking client for accountability circles (V18). Each method
/// maps 1:1 to a `CircleController` endpoint on the backend.
struct CircleRepository {
    let client: BackendAPIClient

    func listMine() async throws -> [AccountabilityCircle] {
        try await client.authorizedRequest(path: "/api/circles", method: "GET")
    }

    func listPublic() async throws -> [AccountabilityCircle] {
        try await client.authorizedRequest(path: "/api/circles/public", method: "GET")
    }

    func dashboard(circleID: Int64) async throws -> CircleDashboard {
        try await client.authorizedRequest(path: "/api/circles/\(circleID)", method: "GET")
    }

    func create(
        name: String,
        description: String?,
        visibility: AccountabilityCircle.Visibility,
        verifiedOnly: Bool
    ) async throws -> AccountabilityCircle {
        try await client.authorizedRequest(
            path: "/api/circles",
            method: "POST",
            body: CreateCircleRequest(
                name: name,
                description: description,
                visibility: visibility.rawValue,
                verifiedOnly: verifiedOnly
            )
        )
    }

    func join(circleID: Int64, joinCode: String?) async throws -> AccountabilityCircle {
        try await client.authorizedRequest(
            path: "/api/circles/\(circleID)/join",
            method: "POST",
            body: JoinCircleRequest(joinCode: joinCode)
        )
    }

    func leave(circleID: Int64) async throws {
        let _: EmptyResponse = try await client.authorizedRequest(
            path: "/api/circles/\(circleID)/leave",
            method: "POST"
        )
    }

    private struct CreateCircleRequest: Encodable {
        let name: String
        let description: String?
        let visibility: String
        let verifiedOnly: Bool
    }
    private struct JoinCircleRequest: Encodable {
        let joinCode: String?
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

    /// Asks the backend to grant a "rest day" freeze if the caller's
    /// stored sleep snapshot shows enough cumulative debt that the body
    /// is genuinely under-recovered. Idempotent server-side over a 20 h
    /// cooldown — calling this every dashboard refresh is safe and the
    /// expected pattern. Returns the refreshed dashboard either way; the
    /// client compares `freezesAvailable` before/after to decide whether
    /// to surface a "rest day, freeze added" toast.
    func recoveryFreeze() async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(
            path: "/api/accountability/streak-freeze/recovery", method: "POST"
        )
    }

    func sendNudge(matchId: Int64) async throws -> AccountabilityDashboard {
        try await client.authorizedRequest(path: "/api/accountability/matches/\(matchId)/nudge", method: "POST")
    }

    private struct MentorshipMessageRequest: Encodable { let message: String }
    private struct StreakFreezeRequest: Encodable { let dateKey: String }
    private struct EmptyResponse: Decodable {}
}

