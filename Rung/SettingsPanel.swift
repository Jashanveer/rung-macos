import SwiftUI

struct SettingsPanel: View {
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore
    let habits: [Habit]
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void
    var onClose: (() -> Void)? = nil

    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                        .frame(width: 30, height: 30)
                        .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), level: .control)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Social Circle")
                            .font(.headline)
                        Text("Following, consistency, small wins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .cleanShotSurface(shape: Circle(), level: .control)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                }

                PermissionsStatusCard()

                ProfileEditCard(backend: backend)

                AccountActionsCard(backend: backend, showDeleteConfirm: $showDeleteConfirm)

                VerificationHelpCard()

                EmailPreferencesCard(backend: backend)

                AcknowledgmentsCard()

                SocialSummaryCard(metrics: metrics, dashboard: backend.dashboard)

                SocialFeedCard(dashboard: backend.dashboard)

                FriendSuggestionsCard(
                    dashboard: backend.dashboard,
                    searchResults: backend.friendSearchResults,
                    isSearching: backend.friendSearchRequestState.isLoading,
                    onSearch: { query in
                        await backend.searchFriends(query: query)
                    }
                ) { userID in
                    Task {
                        await backend.requestFriend(userID: userID)
                    }
                }

                TimeRemindersCard(
                    habits: habits,
                    onReminderChange: onReminderChange
                )
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .elevated,
            shadowRadius: 18
        )
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete my account", role: .destructive) {
                Task { await backend.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, all habits, and streak history. This cannot be undone.")
        }
    }
}

struct AccountActionsCard: View {
    @ObservedObject var backend: HabitBackendStore
    @Binding var showDeleteConfirm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "person.crop.circle", title: "Account")

            if let error = backend.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let status = backend.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SoftActionButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", action: backend.signOut)
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Label("Delete account", systemImage: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                level: .control
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

/// Re-uses `AppleProfileSetupView` in its edit-mode init to let the
/// user rename their handle or pick a different character at any
/// time. Pre-fills the current username + avatar from the dashboard
/// so an avatar-only change doesn't force a username re-pick. Hidden
/// when there's no dashboard yet (pre-auth or first-load) — falling
/// back to a "loading…" state would just confuse users since the rest
/// of Settings is also blank in that case.
struct ProfileEditCard: View {
    @ObservedObject var backend: HabitBackendStore
    @State private var showSheet = false

    private var profile: AccountabilityDashboard.Profile? {
        backend.dashboard?.profile
    }

    var body: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(systemImage: "person.crop.square", title: "Profile")

                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: profile.avatarUrl ?? "")) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(CleanShotTheme.accent.opacity(0.35), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName.isEmpty ? "—" : profile.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let username = profile.username, !username.isEmpty {
                            Text("@\(username.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                Button {
                    showSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Edit profile")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(CleanShotTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .cleanShotSurface(
                    shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                    level: .control
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                level: .control
            )
            .sheet(isPresented: $showSheet) {
                AppleProfileSetupView(
                    backend: backend,
                    initialUsername: profile.username ?? "",
                    initialAvatarURL: profile.avatarUrl,
                    initialDisplayName: profile.displayName,
                    onComplete: {
                        showSheet = false
                        Task { await backend.refreshDashboard() }
                    }
                )
                .frame(minWidth: 460, minHeight: 600)
            }
        }
    }
}

/// Surfaces the same `VerificationHelpSheet` that's reachable from
/// onboarding, so users who skipped onboarding (or want a refresher
/// later) can still see which habits auto-verify and what their
/// leaderboard-tier weights are.
struct VerificationHelpCard: View {
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "checkmark.shield.fill", title: "Verification")
            Text("Which habits auto-verify against Apple Health, which stay honor-system, and how the leaderboard weighs them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("How verification works")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(CleanShotTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                level: .control
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
        .sheet(isPresented: $showSheet) {
            VerificationHelpSheet()
        }
    }
}

/// Single-toggle email preferences tile. Today only the Sunday weekly report
/// is gated by this flag — additional channels can be split into rows here as
/// the backend grows new preference fields.
struct EmailPreferencesCard: View {
    @ObservedObject var backend: HabitBackendStore

    private var isOn: Binding<Bool> {
        Binding(
            get: { backend.preferences?.emailOptIn ?? true },
            set: { newValue in Task { await backend.setEmailOptIn(newValue) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "envelope", title: "Email")

            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly report")
                        .font(.subheadline.weight(.semibold))
                    Text("Sunday recap of your consistency, perfect days, and best streak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(MinimalToggleStyle())
            .disabled(backend.preferencesRequestState.isLoading && backend.preferences == nil)

            if case .failure(let message) = backend.preferencesRequestState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
        .task {
            // Lazy-load on first appearance so the toggle reflects the
            // server-side state without forcing a fetch on app launch.
            if backend.preferences == nil {
                await backend.loadPreferences()
            }
        }
    }
}

struct SocialSummaryCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var followingCount: Int {
        dashboard?.social?.friendCount ?? 0
    }

    private var updateCount: Int {
        dashboard?.social?.updates.count ?? 0
    }

    private var consistencyPercent: Int {
        dashboard?.level.weeklyConsistencyPercent ?? metrics.weeklyConsistencyPercent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "person.2.fill", title: "Following")

            HStack(spacing: 8) {
                SocialMetric(value: "\(followingCount)", label: "Following", tint: CleanShotTheme.accent)
                SocialMetric(value: "\(updateCount)", label: "Updates", tint: CleanShotTheme.success)
                SocialMetric(value: "\(consistencyPercent)%", label: "Your week", tint: CleanShotTheme.gold)
            }

            Text("Follow open profiles to see consistency and today’s progress, not every habit detail.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

struct SocialMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .padding(9)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }
}

struct SocialFeedCard: View {
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "chart.line.uptrend.xyaxis", title: "Following updates")

            if !displayUpdates.isEmpty {
                ForEach(displayUpdates) { update in
                    SocialActivityRow(update: update)
                }
            } else if !displayPosts.isEmpty {
                ForEach(displayPosts) { post in
                    SocialPostRow(post: post)
                }
            } else {
                Text("No social updates yet. Follow people to start seeing activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }

    private var displayUpdates: [AccountabilityDashboard.SocialActivity] {
        guard let updates = dashboard?.social?.updates else { return [] }
        return Array(updates.prefix(4))
    }

    private var displayPosts: [AccountabilityDashboard.SocialPost] {
        guard let remotePosts = dashboard?.feed, !remotePosts.isEmpty else { return [] }
        return Array(remotePosts.prefix(3))
    }
}

struct SocialActivityRow: View {
    let update: AccountabilityDashboard.SocialActivity

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .cleanShotSurface(shape: Circle(), level: .control)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(update.displayName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(update.weeklyConsistencyPercent)% week")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(update.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ProgressView(value: Double(update.progressPercent), total: 100)
                    .tint(tint)
            }
        }
        .frame(minHeight: 70)
    }

    private var icon: String {
        switch update.kind {
        case "PERFECT_DAY":
            return "checkmark.seal"
        case "CONSISTENCY":
            return "flame"
        default:
            return "chart.line.uptrend.xyaxis"
        }
    }

    private var tint: Color {
        update.progressPercent >= 100 ? CleanShotTheme.success : CleanShotTheme.accent
    }
}

struct SocialPostRow: View {
    let post: AccountabilityDashboard.SocialPost

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: post.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CleanShotTheme.accent)
                .frame(width: 26, height: 26)
                .cleanShotSurface(shape: Circle(), level: .control)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.author)
                    .font(.caption.weight(.semibold))
                Text(post.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Community update")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 70)
    }
}

private extension AccountabilityDashboard.SocialPost {
    var systemImage: String {
        "quote.bubble"
    }
}

struct FriendSuggestionsCard: View {
    let dashboard: AccountabilityDashboard?
    let searchResults: [AccountabilityDashboard.FriendSummary]
    let isSearching: Bool
    let onSearch: (String) async -> Void
    let onFollow: (Int64) -> Void
    @State private var searchText = ""

    private var suggestions: [AccountabilityDashboard.FriendSummary] {
        guard let suggestions = dashboard?.social?.suggestions else { return [] }
        return Array(suggestions.prefix(3))
    }

    private var displayPeople: [AccountabilityDashboard.FriendSummary] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return suggestions
        }
        return searchResults
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "person.badge.plus", title: "People to follow")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search people", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit {
                        Task { await onSearch(searchText) }
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                level: .control
            )
            .task(id: searchText) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard query.count >= 2 || query.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await onSearch(query)
            }

            if displayPeople.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(displayPeople) { friend in
                    FriendSuggestionRow(friend: friend, onFollow: onFollow)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }

    private var emptyMessage: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Suggestions use shared goals, consistency, people followed by your follows, and recent progress."
            : "No open profiles match that search."
    }
}

struct FriendSuggestionRow: View {
    let friend: AccountabilityDashboard.FriendSummary
    let onFollow: (Int64) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CleanShotTheme.violet)
                .frame(width: 28, height: 28)
                .cleanShotSurface(shape: Circle(), level: .control)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.caption.weight(.semibold))
                Text(friend.goals)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onFollow(friend.userId)
            } label: {
                Text("Follow")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                level: .control
            )
        }
        .frame(minHeight: 50)
    }
}

struct PanelTitle: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct SoftActionButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? CleanShotTheme.accent : .primary)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .onHover { isHovered = $0 }
    }
}

struct SettingsRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }
}

struct SettingsMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }
}

// MARK: - Time Reminders Card

struct TimeRemindersCard: View {
    let habits: [Habit]
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void

    @State private var isExpanded = false

    private static let collapsedLimit = 3

    private var reminderCount: Int {
        habits.filter { $0.reminderWindow != nil }.count
    }

    private var hasMoreThanLimit: Bool {
        habits.count > Self.collapsedLimit
    }

    private var visibleHabits: [Habit] {
        guard hasMoreThanLimit, !isExpanded else { return habits }
        return Array(habits.prefix(Self.collapsedLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "clock.badge.checkmark", title: "Time reminders")

            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CleanShotTheme.accent)
                    .frame(width: 26, height: 26)
                    .cleanShotSurface(shape: Circle(), level: .control)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminderCount == 0 ? "No reminder windows" : "\(reminderCount) reminder window\(reminderCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                    Text("Morning 9 AM · Afternoon 2 PM · Evening 7 PM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Pick a gentle window for habits that need a nudge. Notifications are scheduled only for unfinished habits.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !habits.isEmpty {
                Divider()

                VStack(spacing: 10) {
                    ForEach(visibleHabits) { habit in
                        HabitTimeReminderRow(
                            habit: habit,
                            onReminderChange: onReminderChange
                        )
                    }
                }

                if hasMoreThanLimit {
                    Button {
                        withAnimation(.smooth(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isExpanded
                                 ? "Show fewer"
                                 : "Show \(habits.count - Self.collapsedLimit) more")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .foregroundStyle(CleanShotTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .cleanShotSurface(
                        shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                        level: .control
                    )
                }
            }
        }
        .padding(12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .control
        )
    }
}

private struct HabitTimeReminderRow: View {
    let habit: Habit
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void

    @State private var selectedWindow: HabitReminderWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(habit.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 6) {
                TimeReminderOptionButton(
                    title: "None",
                    subtitle: "",
                    systemImage: "bell.slash",
                    isSelected: selectedWindow == nil
                ) {
                    selectedWindow = nil
                    onReminderChange(habit, nil)
                }

                ForEach(HabitReminderWindow.allCases) { window in
                    TimeReminderOptionButton(
                        title: window.rawValue,
                        subtitle: window.subtitle,
                        systemImage: window.systemImage,
                        isSelected: selectedWindow == window
                    ) {
                        selectedWindow = window
                        onReminderChange(habit, window)
                    }
                }
            }
        }
        .onAppear {
            if let raw = habit.reminderWindow {
                selectedWindow = HabitReminderWindow(rawValue: raw)
            } else {
                selectedWindow = nil
            }
        }
    }
}

private struct TimeReminderOptionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? CleanShotTheme.accent : isHovered ? .primary : .secondary)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
            level: .control,
            isActive: isSelected || isHovered
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Acknowledgments

/// Required by the MIT license terms of the lil-agents project
/// (github.com/ryanstephen/lil-agents) — Bruce/Jazz character animations
/// and the looping-video character system in `RiveCharacterView` /
/// `LoopingVideoView` are derived from that work.
struct AcknowledgmentsCard: View {
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "heart.text.square", title: "Acknowledgments")
            Text("Open-source projects and creators whose work helps make Rung what it is.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                    Text("View licenses & credits")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(CleanShotTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                level: .control
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
        .sheet(isPresented: $showSheet) {
            AcknowledgmentsSheet()
        }
    }
}

struct AcknowledgmentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Acknowledgments")
                            .font(.title2.weight(.bold))
                        Text("Rung stands on the shoulders of others.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .cleanShotSurface(shape: Circle(), level: .control)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("lil agents")
                        .font(.headline)
                    Text("Character animations Bruce and Jazz, and the looping-video character system, are derived from lil-agents by Ryan Stephen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("github.com/ryanstephen/lil-agents",
                         destination: URL(string: "https://github.com/ryanstephen/lil-agents")!)
                        .font(.caption.weight(.semibold))

                    Text(AcknowledgmentsSheet.lilAgentsLicense)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .cleanShotSurface(
                            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                            level: .control
                        )
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cleanShotSurface(
                    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    level: .control
                )
            }
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 540, idealHeight: 640)
    }

    static let lilAgentsLicense = """
        MIT License

        Copyright (c) 2026 Ryan Stephen

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
