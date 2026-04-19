import SwiftUI

struct SettingsPanel: View {
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore
    let habits: [Habit]
    let onSync: () -> Void
    let onFindMentor: () -> Void
    let onReminderChange: (Habit, HabitReminderWindow?) -> Void

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
                }

                AccountActionsCard(backend: backend, onSync: onSync, showDeleteConfirm: $showDeleteConfirm)

                MentorActionCard(metrics: metrics, dashboard: backend.dashboard, onFindMentor: onFindMentor)

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
    let onSync: () -> Void
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
                SoftActionButton(title: "Sync", systemImage: "arrow.clockwise", action: onSync)
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

struct MentorActionCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?
    let onFindMentor: () -> Void

    private var status: AccountabilityDashboard.MentorshipStatus? {
        dashboard?.mentorship
    }

    private var mentorName: String? {
        dashboard?.match?.mentor.displayName
    }

    private var canFindMentor: Bool {
        status?.canFindMentor ?? (metrics.totalHabits > 0 && metrics.daysUntilMentor == 0)
    }

    private var canChangeMentor: Bool {
        status?.canChangeMentor ?? false
    }

    private var message: String {
        if let message = status?.message {
            return message
        }

        if canFindMentor {
            return "Find a mentor when you want extra accountability."
        }

        return "Mentor matching unlocks after 7 days of habit data."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "person.crop.circle.badge.checkmark", title: "Mentor")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mentorName == nil ? "person.badge.plus" : "checkmark.seal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mentorName == nil ? CleanShotTheme.accent : CleanShotTheme.success)
                    .frame(width: 30, height: 30)
                    .cleanShotSurface(shape: Circle(), level: .control)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if shouldShowButton {
                SoftActionButton(title: buttonTitle, systemImage: buttonIcon, action: onFindMentor)
                    .disabled(!buttonEnabled)
                    .opacity(buttonEnabled ? 1 : 0.55)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }

    private var title: String {
        if let mentorName {
            return "Matched with \(mentorName)"
        }

        return canFindMentor ? "Mentor available" : "Mentor locked"
    }

    private var shouldShowButton: Bool {
        mentorName == nil ? canFindMentor : true
    }

    private var buttonTitle: String {
        mentorName == nil ? "Find mentor" : "Change mentor"
    }

    private var buttonIcon: String {
        mentorName == nil ? "person.badge.plus" : "arrow.triangle.2.circlepath"
    }

    private var buttonEnabled: Bool {
        mentorName == nil ? canFindMentor : canChangeMentor
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

    private var reminderCount: Int {
        habits.filter { $0.reminderWindow != nil }.count
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
                    ForEach(habits) { habit in
                        HabitTimeReminderRow(
                            habit: habit,
                            onReminderChange: onReminderChange
                        )
                    }
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
