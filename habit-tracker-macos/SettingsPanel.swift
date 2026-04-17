import SwiftUI

struct SettingsPanel: View {
    let metrics: HabitMetrics
    @ObservedObject var backend: HabitBackendStore
    let habits: [Habit]
    @ObservedObject var locationManager: LocationReminderManager
    let onSync: () -> Void
    let onFindMentor: () -> Void

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
                        Text("Friends, consistency, small wins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                BackendConnectionCard(backend: backend, onSync: onSync)

                MentorActionCard(metrics: metrics, dashboard: backend.dashboard, onFindMentor: onFindMentor)

                SocialSummaryCard(metrics: metrics, dashboard: backend.dashboard)

                SocialFeedCard(dashboard: backend.dashboard)

                FriendSuggestionsCard(dashboard: backend.dashboard) { userID in
                    Task {
                        await backend.requestFriend(userID: userID)
                    }
                }

                LocationRemindersCard(habits: habits, locationManager: locationManager)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .elevated,
            shadowRadius: 18
        )
    }
}

struct BackendConnectionCard: View {
    @ObservedObject var backend: HabitBackendStore
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(systemImage: "server.rack", title: "Backend")

            SettingsRow(
                systemImage: backend.errorMessage == nil ? "checkmark.icloud" : "exclamationmark.triangle",
                title: BackendEnvironment.displayHost,
                value: backend.isAuthenticated ? "Connected" : "Signed out"
            )

            if let statusMessage = backend.statusMessage, backend.errorMessage == nil {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = backend.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                SoftActionButton(title: "Sync", systemImage: "arrow.clockwise", action: onSync)
                SoftActionButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", action: backend.signOut)
            }
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

    private var friendCount: Int {
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
            PanelTitle(systemImage: "person.2.fill", title: "Friends")

            HStack(spacing: 8) {
                SocialMetric(value: "\(friendCount)", label: "Friends", tint: CleanShotTheme.accent)
                SocialMetric(value: "\(updateCount)", label: "Updates", tint: CleanShotTheme.success)
                SocialMetric(value: "\(consistencyPercent)%", label: "Your week", tint: CleanShotTheme.gold)
            }

            Text("Share progress as small updates. Friends see consistency and today’s progress, not every habit detail.")
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
            PanelTitle(systemImage: "chart.line.uptrend.xyaxis", title: "Friend updates")

            if !displayUpdates.isEmpty {
                ForEach(displayUpdates) { update in
                    SocialActivityRow(update: update)
                }
            } else if !displayPosts.isEmpty {
                ForEach(displayPosts) { post in
                    SocialPostRow(post: post)
                }
            } else {
                Text("No social updates yet. Add friends to start seeing activity.")
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
    let onFollow: (Int64) -> Void

    private var suggestions: [AccountabilityDashboard.FriendSummary] {
        guard let suggestions = dashboard?.social?.suggestions else { return [] }
        return Array(suggestions.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "person.badge.plus", title: "People to follow")

            if suggestions.isEmpty {
                Text("Friend suggestions appear after more people join or update their profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(suggestions) { friend in
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

// MARK: - Location Reminders Card

struct LocationRemindersCard: View {
    let habits: [Habit]
    @ObservedObject var locationManager: LocationReminderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "location.fill", title: "Location reminders")

            // Current network status
            HStack(spacing: 8) {
                Image(systemName: locationManager.currentContext.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(locationManager.currentContext == .unknown ? .secondary : CleanShotTheme.accent)
                    .frame(width: 26, height: 26)
                    .cleanShotSurface(shape: Circle(), level: .control)

                VStack(alignment: .leading, spacing: 2) {
                    Text(locationManager.currentSSID ?? "Not connected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(locationManager.currentSSID == nil ? .secondary : .primary)
                    Text(locationManager.currentContext == .unknown
                         ? "No location label"
                         : locationManager.currentContext.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Label current network button
                if let ssid = locationManager.currentSSID {
                    Menu {
                        ForEach(LocationContext.allCases.filter { $0 != .unknown }) { context in
                            Button {
                                locationManager.labelSSID(ssid, as: context)
                            } label: {
                                Label(context.rawValue, systemImage: context.systemImage)
                            }
                        }
                    } label: {
                        Text("Label")
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
            }

            // Existing SSID → context labels
            if !locationManager.wifiLabels.isEmpty {
                Divider()

                ForEach(Array(locationManager.wifiLabels.keys.sorted()), id: \.self) { ssid in
                    if let context = locationManager.wifiLabels[ssid] {
                        HStack(spacing: 8) {
                            Image(systemName: context.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CleanShotTheme.accent)
                                .frame(width: 22, height: 22)
                                .cleanShotSurface(shape: Circle(), level: .control)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(ssid)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(context.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    locationManager.removeLabel(for: ssid)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Hint text
            Text("Assign habits to locations below to get reminders when you arrive.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Per-habit location picker
            if !habits.isEmpty {
                Divider()

                ForEach(habits) { habit in
                    HabitLocationRow(habit: habit)
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

private struct HabitLocationRow: View {
    let habit: Habit
    @State private var selectedContext: LocationContext = .unknown

    var body: some View {
        HStack(spacing: 8) {
            Text(habit.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Spacer()

            Picker("", selection: $selectedContext) {
                Text("None").tag(LocationContext.unknown)
                ForEach(LocationContext.allCases.filter { $0 != .unknown }) { ctx in
                    Label(ctx.rawValue, systemImage: ctx.systemImage).tag(ctx)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.caption2)
            .frame(maxWidth: 100)
            .onChange(of: selectedContext) { _, newContext in
                habit.locationContext = newContext == .unknown ? nil : newContext.rawValue
            }
        }
        .onAppear {
            if let raw = habit.locationContext, let ctx = LocationContext(rawValue: raw) {
                selectedContext = ctx
            } else {
                selectedContext = .unknown
            }
        }
    }
}
