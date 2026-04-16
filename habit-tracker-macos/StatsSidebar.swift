import SwiftUI

struct StatsSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    let metrics: HabitMetrics
    let dashboard: AccountabilityDashboard?

    private var level: Int { (dashboard?.rewards.xp ?? metrics.totalChecks) / 100 + 1 }
    private var xp: Int { (dashboard?.rewards.xp ?? metrics.totalChecks) % 100 }
    private var percent: Int { Int((metrics.progressToday * 100).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                    StatCard(icon: "bitcoinsign.circle.fill", label: "Coins", value: "\(dashboard?.rewards.coins ?? metrics.coins)", tint: CleanShotTheme.gold)
                    StatCard(icon: "bolt.fill", label: "XP", value: "\(dashboard?.rewards.xp ?? metrics.xp)", tint: CleanShotTheme.violet)
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
        .sidebarSurfaceStyle()
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

            HStack {
                ForEach(displayLeaders) { leader in
                    ChallengeLeader(
                        name: leader.displayName,
                        score: "\(leader.score)/\(dashboard?.weeklyChallenge.targetPerfectDays ?? 5)"
                    )
                }
            }
        }
        .padding(14)
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

        return [
            AccountabilityDashboard.LeaderboardEntry(displayName: "Maya", score: 5, currentUser: false),
            AccountabilityDashboard.LeaderboardEntry(displayName: "You", score: metrics.perfectDaysCount, currentUser: true),
            AccountabilityDashboard.LeaderboardEntry(displayName: "Leo", score: 3, currentUser: false)
        ]
    }
}

struct ChallengeLeader: View {
    let name: String
    let score: String

    var body: some View {
        VStack(spacing: 3) {
            Text(name)
                .font(.caption2.weight(.semibold))
            Text(score)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
        .padding(.vertical, 14)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
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
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            level: .control,
            isActive: medal.unlocked
        )
        .opacity(medal.unlocked ? 1.0 : 0.65)
    }
}
