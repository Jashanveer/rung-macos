import SwiftUI

/// Tab 3 — Level + XP bar + 4-stat grid (DONE / BEST / RANK / FREEZE).
struct StatsTab: View {
    @EnvironmentObject private var session: WatchSession

    private var metrics: WatchSnapshot.Metrics { session.snapshot.metrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            levelRow
            xpBar
            statGrid
        }
        .padding(.horizontal, 11)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .watchPageHeader("STATS", accent: WatchTheme.violet, trailing: metrics.levelName.uppercased())
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    // MARK: - Level row

    private var levelRow: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(WatchTheme.brandGradient)
                Text("\(metrics.level)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text("Level \(metrics.level)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                Text("\(formattedXP) XP")
                    .font(.system(size: 8.5))
                    .foregroundStyle(WatchTheme.inkSoft)
            }
            Spacer()
            Text("\u{1F525}\(metrics.currentStreak)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WatchTheme.gold)
        }
    }

    private var formattedXP: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: metrics.xp)) ?? "\(metrics.xp)"
    }

    // MARK: - XP bar

    private var xpBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(WatchTheme.progressGradient)
                    .frame(width: max(0, proxy.size.width * metrics.nextLevelProgress))
            }
        }
        .frame(height: 2.5)
    }

    // MARK: - Grid

    private var statGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]
        return LazyVGrid(columns: columns, spacing: 3) {
            StatTile(label: "DONE", value: "\(metrics.doneToday)", color: WatchTheme.success)
            StatTile(label: "BEST", value: "\(metrics.bestStreak)", color: WatchTheme.gold)
            StatTile(label: "RANK", value: rankString, color: WatchTheme.accent)
            StatTile(label: "FREEZE", value: "\(metrics.freezesAvailable)", color: WatchTheme.violet)
        }
    }

    private var rankString: String {
        metrics.leaderboardRank > 0 ? "#\(metrics.leaderboardRank)" : "—"
    }
}

// MARK: - Tile

private struct StatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.inkSoft)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .watchGlass(cornerRadius: 8)
    }
}

#Preview {
    StatsTab()
        .environmentObject(WatchSession.shared)
}
