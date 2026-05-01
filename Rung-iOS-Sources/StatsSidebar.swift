import SwiftUI

struct StatsSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?
    @ObservedObject var backend: HabitBackendStore
    let todayKey: String
    var onClose: (() -> Void)? = nil

    private var rawXP: Int { dashboard?.rewards.xp ?? metrics.totalChecks }
    private var adjustedXP: Int {
        OverduePenaltyStore.adjustedXP(rawXP, for: backend.currentUserId)
    }
    private var level: Int { adjustedXP / 100 + 1 }
    private var xp: Int { adjustedXP % 100 }
    private var percent: Int { Int((metrics.progressToday * 100).rounded()) }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let onClose {
                    HStack {
                        Spacer()
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

                // Profile identity (avatar + display name) is intentionally
                // hidden on the iPhone Stats tab — the user lives in the
                // app, they don't need their own card to greet them. The
                // macOS / iPad sidebar still shows it because that surface
                // doubles as a roster / dashboard alongside other people's
                // profiles, where self-identification adds context.
                if !isCompact {
                    ProfileIdentityCard(metrics: metrics, dashboard: dashboard)
                }

                LevelHeroCard(metrics: metrics, dashboard: dashboard)

                // MARK: - Hero Streak Ring
                ZStack {
                    Circle()
                        .stroke(CleanShotTheme.controlFill(for: colorScheme), lineWidth: 10)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: metrics.progressToday)
                        .stroke(
                            CleanShotTheme.success,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: metrics.progressToday)

                    VStack(spacing: 2) {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("today")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                // MARK: - Streak Highlight
                HStack(spacing: 14) {
                    StreakPill(
                        icon: "flame.fill",
                        value: "\(metrics.currentPerfectStreak)",
                        unit: "day streak",
                        color: CleanShotTheme.warning
                    )
                    StreakPill(
                        icon: "trophy.fill",
                        value: "\(metrics.bestPerfectStreak)",
                        unit: "best",
                        color: CleanShotTheme.gold
                    )
                }

                // MARK: - Stats Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatCard(icon: "checklist", label: "Habits", value: "\(metrics.totalHabits)", tint: CleanShotTheme.accent)
                    StatCard(icon: "checkmark.circle.fill", label: "Done", value: "\(metrics.doneToday)", tint: CleanShotTheme.success)
                    StatCard(icon: "bolt.fill", label: "XP", value: "\(OverduePenaltyStore.adjustedXP(dashboard?.rewards.xp ?? metrics.xp, for: backend.currentUserId))", tint: CleanShotTheme.violet)
                    StatCard(icon: "shield.fill", label: "Freezes", value: "\(dashboard?.rewards.freezesAvailable ?? 0)", tint: Color.cyan)
                }

                // MARK: - Level & XP
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CleanShotTheme.controlFill(for: colorScheme, active: true))
                            Text("\(level)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(CleanShotTheme.accent)
                        }
                        .frame(width: 44, height: 44)
                        .cleanShotSurface(shape: Circle(), level: .control)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(level)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(xp)/100 XP to next level")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(CleanShotTheme.controlFill(for: colorScheme))
                                .overlay(
                                    Capsule()
                                        .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 0.5)
                                )

                            Capsule()
                                .fill(CleanShotTheme.accent)
                                .frame(width: max(geo.size.width * CGFloat(xp) / 100.0, 6))
                                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: xp)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(14)
                .cleanShotSurface(
                    shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    level: .control
                )

                WeeklyChallengeCard(metrics: metrics, dashboard: dashboard)

                HabitClusterSummaryCard(clusters: dashboard?.habitClusters ?? [])

                // MARK: - Reward Eligibility
                if let rewards = dashboard?.rewards {
                    RewardEligibilityCard(rewards: rewards)

                    StreakFreezeCard(
                        rewards: rewards,
                        todayKey: todayKey,
                        isSyncing: backend.isSyncing,
                        onUseFreeze: { await backend.useStreakFreeze(dateKey: todayKey) },
                        onUndoFreeze: { await backend.undoStreakFreeze() }
                    )
                }

                // MARK: - Achievements
                VStack(alignment: .leading, spacing: 10) {
                    Text("Achievements")
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 4)

                    ForEach(metrics.medals) { medal in
                        AchievementRow(medal: medal)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .modifier(OptionalSidebarSurface(isEnabled: !isCompact))
    }
}

private struct OptionalSidebarSurface: ViewModifier {
    let isEnabled: Bool
    func body(content: Content) -> some View {
        if isEnabled {
            content.sidebarSurfaceStyle()
        } else {
            content
        }
    }
}

struct ProfileIdentityCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var username: String {
        if let user = dashboard?.profile.username?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            return user
        }
        if let email = dashboard?.profile.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "habit.user"
    }

    private var badgeTitle: String {
        let levelName = dashboard?.level.name ?? metrics.level.rawValue
        switch levelName.lowercased() {
        case "master mentor":
            return "Master Mentor"
        case "mentor":
            return "Mentor"
        case "elite":
            return "Elite"
        case "consistent":
            return "Consistent"
        case "rising":
            return "Rising"
        default:
            return "Beginner"
        }
    }

    private var avatarURL: URL? {
        if
            let raw = dashboard?.profile.avatarUrl,
            let parsed = URL(string: raw),
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return parsed
        }

        let seed = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "habit-user"
        return URL(string: "https://api.dicebear.com/9.x/adventurer/png?seed=\(seed)&size=96")
    }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(CleanShotTheme.accent)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                BadgeChip(title: badgeTitle)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

private struct BadgeChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CleanShotTheme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CleanShotTheme.gold.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.gold.opacity(0.35), lineWidth: 0.8)
            )
    }
}

struct LevelHeroCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var levelName: String {
        dashboard?.level.name ?? metrics.level.rawValue
    }

    private var level: UserLevel {
        UserLevel(rawValue: levelName) ?? metrics.level
    }

    private var consistencyPercent: Int {
        dashboard?.level.weeklyConsistencyPercent ?? metrics.weeklyConsistencyPercent
    }

    private var note: String {
        dashboard?.level.note ?? metrics.levelNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: level.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(level.tint)
                    .frame(width: 42, height: 42)
                    .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), level: .control)

                VStack(alignment: .leading, spacing: 2) {
                    Text(levelName)
                        .font(.headline)
                    Text("\(consistencyPercent)% weekly consistency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: metrics.nextLevelProgress)
                .tint(level.tint)

            Text(note)
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

struct WeeklyChallengeCard: View {
    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelTitle(systemImage: "flag.checkered", title: "Weekly challenge")
                Spacer()
                Text("#\(dashboard?.weeklyChallenge.rank ?? metrics.challengeRank)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(CleanShotTheme.accent)
            }

            Text(dashboard?.weeklyChallenge.title ?? "Complete 5 focused days")
                .font(.subheadline.weight(.semibold))

            ProgressView(value: challengeProgress)
                .tint(CleanShotTheme.accent)

            if !displayLeaders.isEmpty {
                HStack {
                    ForEach(displayLeaders) { leader in
                        ChallengeLeader(
                            name: leader.displayName,
                            score: "\(leader.score)/\(dashboard?.weeklyChallenge.targetPerfectDays ?? 5)"
                        )
                    }
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

    private var challengeProgress: Double {
        guard let weeklyChallenge = dashboard?.weeklyChallenge, weeklyChallenge.targetPerfectDays > 0 else {
            return metrics.challengeProgress
        }

        return min(Double(weeklyChallenge.completedPerfectDays) / Double(weeklyChallenge.targetPerfectDays), 1)
    }

    private var displayLeaders: [AccountabilityDashboard.LeaderboardEntry] {
        if let leaderboard = dashboard?.weeklyChallenge.leaderboard, !leaderboard.isEmpty {
            return Array(leaderboard.prefix(3))
        }

        return []
    }
}

struct ChallengeLeader: View {
    let name: String
    let score: String

    var body: some View {
        VStack(spacing: 3) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(score)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 38)
        .padding(.vertical, 7)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 9, style: .continuous),
            level: .control
        )
    }
}

struct StreakPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 64)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 118)
        .padding(.vertical, 14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .pressHover($isHovered)
    }
}


// MARK: - RewardEligibilityCard

/// Shows today's reward progress — XP cap status and a clear
/// "cap reached" warning so users understand why additional checks earn 0 XP.
struct RewardEligibilityCard: View {
    let rewards: AccountabilityDashboard.Rewards

    private var capFraction: Double {
        guard rewards.dailyCap > 0 else { return 1 }
        return min(Double(rewards.checksToday) / Double(rewards.dailyCap), 1)
    }

    private var barColor: Color {
        rewards.rewardEligible ? CleanShotTheme.violet : CleanShotTheme.warning
    }

    private var statusText: String {
        if rewards.rewardEligible {
            let remaining = rewards.dailyCap - rewards.checksToday
            return "\(remaining) reward-eligible check\(remaining == 1 ? "" : "s") left today"
        }
        return "Daily XP cap reached — habits still track"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelTitle(systemImage: "star.circle.fill", title: "Reward eligibility")
                Spacer()
                if !rewards.rewardEligible {
                    Text("CAP REACHED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CleanShotTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CleanShotTheme.warning.opacity(0.14), in: Capsule())
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(barColor.opacity(0.15))

                    Capsule()
                        .fill(barColor)
                        .frame(width: max(geo.size.width * capFraction, rewards.checksToday > 0 ? 6 : 0))
                        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: capFraction)
                }
            }
            .frame(height: 8)

            HStack {
                Label("\(rewards.checksToday)/\(rewards.dailyCap) today", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(barColor)

                Spacer()

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if rewards.badges.count > 0 {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(rewards.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(CleanShotTheme.gold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(CleanShotTheme.gold.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(CleanShotTheme.gold.opacity(0.3), lineWidth: 0.8))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
    }
}

struct AchievementRow: View {
    let medal: Medal

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(medal.unlocked ? CleanShotTheme.success.opacity(0.14) : Color.secondary.opacity(0.10))
                Image(systemName: medal.unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(medal.unlocked ? CleanShotTheme.success : .secondary.opacity(0.5))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(medal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medal.unlocked ? .primary : .secondary)
                Text(medal.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            level: .control,
            isActive: medal.unlocked
        )
        .opacity(medal.unlocked ? 1.0 : 0.65)
    }
}

// MARK: - StreakFreezeCard

private struct StreakFreezeCard: View {
    let rewards: AccountabilityDashboard.Rewards
    let todayKey: String
    let isSyncing: Bool
    let onUseFreeze: () async -> Void
    let onUndoFreeze: () async -> Void

    @State private var pendingUndo: Bool = false
    @State private var showUndoBanner: Bool = false
    @State private var undoDismissTask: Task<Void, Never>?

    private var alreadyFrozenToday: Bool { rewards.frozenDates.contains(todayKey) }
    private var canUse: Bool { rewards.freezesAvailable > 0 && !alreadyFrozenToday }
    private var hasTokens: Bool { rewards.freezesAvailable > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "shield.fill", title: "Streak freeze")

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(hasTokens ? 0.14 : 0.08))
                    Image(systemName: "snowflake")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(hasTokens ? 1.0 : 0.55))
                }
                .frame(width: 48, height: 48)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: rewards.freezesAvailable)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(rewards.freezesAvailable)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: rewards.freezesAvailable)
                        Text(rewards.freezesAvailable == 1 ? "token" : "tokens")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Complete every habit every day for a week to earn 1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streak freeze: \(rewards.freezesAvailable) \(rewards.freezesAvailable == 1 ? "token" : "tokens"). Earn one by completing every habit every day for a week. Never expires.")

            HStack(spacing: 6) {
                Image(systemName: "infinity")
                    .font(.caption2.weight(.semibold))
                Text("Never expires · use manually to protect today")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            if !rewards.frozenDates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protected days")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(rewards.frozenDates.suffix(3), id: \.self) { date in
                        HStack(spacing: 6) {
                            Image(systemName: "snowflake")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.cyan)
                            Text(date)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            actionArea

            if showUndoBanner {
                undoBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            level: .control
        )
        .onChange(of: alreadyFrozenToday) { _, newValue in
            guard pendingUndo else { return }
            pendingUndo = false
            if newValue { presentUndoBanner() }
        }
        .onDisappear {
            undoDismissTask?.cancel()
            undoDismissTask = nil
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if alreadyFrozenToday {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                Text("Today is frozen")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Color.cyan.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(Color.cyan)
            .accessibilityLabel("Today is frozen")
        } else if canUse {
            Button {
                pendingUndo = true
                Task { await onUseFreeze() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                    Text("Use today")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Color.cyan.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
            .accessibilityLabel("Use a streak freeze to protect today")
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: canUse)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cyan.opacity(0.8))
                Text("0 tokens — finish a perfect week to earn your first freeze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                Color.cyan.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityLabel("Zero tokens. Finish a perfect week to earn your first freeze.")
        }
    }

    private var undoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.cyan)
            Text("Today protected")
                .font(.caption.weight(.semibold))
            Spacer()
            Button {
                undoDismissTask?.cancel()
                undoDismissTask = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showUndoBanner = false
                }
                Task { await onUndoFreeze() }
            } label: {
                Text("Undo")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo freeze")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Color.cyan.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func presentUndoBanner() {
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showUndoBanner = true
        }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showUndoBanner = false
                }
            }
        }
    }
}

// MARK: - HabitClusterBadge

struct HabitClusterBadge: View {
    let timeSlot: String

    private var icon: String? {
        switch timeSlot.uppercased() {
        case "MORNING":   return "sunrise.fill"
        case "AFTERNOON": return "sun.max.fill"
        case "EVENING":   return "sunset.fill"
        case "NIGHT":     return "moon.stars.fill"
        case "MIXED":     return "clock.arrow.2.circlepath"
        default:          return nil
        }
    }

    private var tint: Color {
        switch timeSlot.uppercased() {
        case "MORNING":   return .yellow
        case "AFTERNOON": return .orange
        case "EVENING":   return .orange
        case "NIGHT":     return Color.indigo
        case "MIXED":     return Color.secondary
        default:          return Color.secondary
        }
    }

    private var label: String {
        timeSlot.prefix(1).uppercased() + timeSlot.dropFirst().lowercased()
    }

    var body: some View {
        if let icon {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.6))
        }
    }
}

// MARK: - HabitClusterSummaryCard

private struct HabitClusterSummaryCard: View {
    let clusters: [AccountabilityDashboard.HabitTimeCluster]

    private var qualifiedClusters: [AccountabilityDashboard.HabitTimeCluster] {
        clusters.filter { $0.sampleSize >= 3 && $0.timeSlot.uppercased() != "UNKNOWN" }
    }

    private var summaryText: String {
        let groupedBySlot = Dictionary(grouping: qualifiedClusters) { $0.timeSlot.uppercased() }
        guard
            let strongestSlot = groupedBySlot.max(by: { lhs, rhs in
                if lhs.value.count == rhs.value.count {
                    return slotRank(lhs.key) > slotRank(rhs.key)
                }
                return lhs.value.count < rhs.value.count
            })
        else {
            return "Keep checking off habits to reveal when your routines naturally click."
        }

        let slotName = displayName(for: strongestSlot.key)
        let habitNames = strongestSlot.value
            .sorted { $0.sampleSize > $1.sampleSize }
            .prefix(2)
            .map(\.habitTitle)
        let habitSummary = formattedList(Array(habitNames))

        if qualifiedClusters.count == strongestSlot.value.count {
            return "Your strongest rhythm is \(slotName.lowercased()), especially for \(habitSummary)."
        }

        return "\(slotName) is your clearest habit window, led by \(habitSummary)."
    }

    private func displayName(for timeSlot: String) -> String {
        timeSlot.prefix(1).uppercased() + timeSlot.dropFirst().lowercased()
    }

    private func formattedList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return "your tracked habits"
        case 1:
            return items[0]
        default:
            return "\(items[0]) and \(items[1])"
        }
    }

    private func slotRank(_ timeSlot: String) -> Int {
        switch timeSlot {
        case "MORNING":   return 0
        case "AFTERNOON": return 1
        case "EVENING":   return 2
        case "NIGHT":     return 3
        case "MIXED":     return 4
        default:          return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(systemImage: "clock.fill", title: "Your habit rhythm")

            if qualifiedClusters.count < 2 {
                Text("Complete habits for 3+ days to reveal your patterns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(qualifiedClusters.prefix(4)) { cluster in
                        HStack(spacing: 8) {
                            HabitClusterBadge(timeSlot: cluster.timeSlot)

                            Text(cluster.habitTitle)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)

                            Spacer()
                        }
                    }
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
