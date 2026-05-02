import SwiftUI

/// Tab 4 — leaderboard. Five rows with rank, avatar dot, display name, score.
/// The current user's row gets the gold "focused" treatment.
struct FriendsTab: View {
    @EnvironmentObject private var session: WatchSession

    private var entries: [WatchSnapshot.WatchLeaderboardEntry] {
        session.snapshot.leaderboard
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2.5) {
                ForEach(entries) { entry in
                    LeaderboardRow(entry: entry)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .watchPageHeader(
            "FRIENDS",
            accent: WatchTheme.accent,
            trailing: youRankLabel
        )
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    private var youRankLabel: String? {
        guard let me = entries.first(where: { $0.isCurrentUser }) else { return nil }
        return "YOU #\(me.rank)"
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let entry: WatchSnapshot.WatchLeaderboardEntry

    var body: some View {
        HStack(spacing: 7) {
            Text("\(entry.rank)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(rankColor)
                .frame(width: 11, alignment: .leading)

            Circle()
                .fill(avatarFill)
                .frame(width: 14, height: 14)

            Text(entry.displayName)
                .font(.system(size: 9.5, weight: entry.isCurrentUser ? .semibold : .regular))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedScore)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(WatchTheme.inkSoft)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3.5)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return WatchTheme.gold
        case 2: return Color(white: 0.75)            // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)  // bronze
        default: return WatchTheme.inkSoft
        }
    }

    private var avatarFill: AnyShapeStyle {
        if entry.isCurrentUser {
            return AnyShapeStyle(WatchTheme.brandGradient)
        }
        // Deterministic per-row colour so the leaderboard isn't a sea of grey.
        let palette: [Color] = [
            WatchTheme.danger, WatchTheme.success, WatchTheme.violet,
            WatchTheme.accent, WatchTheme.gold, WatchTheme.warning
        ]
        let hash = abs(entry.displayName.hashValue) % palette.count
        return AnyShapeStyle(palette[hash])
    }

    private var formattedScore: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: entry.score)) ?? "\(entry.score)"
    }

    @ViewBuilder
    private var rowBackground: some View {
        if entry.isCurrentUser {
            LinearGradient(
                colors: [WatchTheme.gold.opacity(0.16), WatchTheme.gold.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WatchTheme.gold.opacity(0.45), lineWidth: 0.5)
            )
        } else {
            Color.clear
        }
    }
}

#Preview {
    FriendsTab()
        .environmentObject(WatchSession.shared)
}
