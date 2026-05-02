import SwiftUI

/// Leaderboard with the top finisher elevated to a small "podium" card and
/// the rest as compact rows. The user's own row is always visible whether
/// or not they're in the top slice.
struct FriendsTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    private var entries: [WatchSnapshot.WatchLeaderboardEntry] {
        session.snapshot.leaderboard
    }

    var body: some View {
        if entries.isEmpty {
            emptyState
                .containerBackground(WatchTheme.bg.gradient, for: .tabView)
        } else {
            ScrollView {
                VStack(spacing: 5) {
                    if let leader = entries.first {
                        PodiumCard(entry: leader, scale: scale)
                    }
                    ForEach(Array(entries.dropFirst())) { entry in
                        LeaderboardRow(entry: entry, scale: scale)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .containerBackground(WatchTheme.bg.gradient, for: .tabView)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 22 * scale))
                .foregroundStyle(WatchTheme.inkSoft)
            Text("No friends yet")
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
            Text("Invite from\nthe iPhone app")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Podium

private struct PodiumCard: View {
    let entry: WatchSnapshot.WatchLeaderboardEntry
    let scale: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(entry.isCurrentUser ? AnyShapeStyle(WatchTheme.brandGradient)
                                                : AnyShapeStyle(WatchTheme.gold))
                Text(String(entry.displayName.prefix(1)).uppercased())
                    .font(WatchTheme.font(.body, scale: scale, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 32 * scale, height: 32 * scale)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(WatchTheme.gold)
                    Text("#1")
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(WatchTheme.gold)
                }
                Text(entry.displayName)
                    .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
            }
            Spacer()
            Text(formattedScore(entry.score))
                .font(WatchTheme.font(.title, scale: scale, weight: .bold, design: .rounded))
                .foregroundStyle(WatchTheme.gold)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [WatchTheme.gold.opacity(0.18), WatchTheme.gold.opacity(0.04)],
                startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WatchTheme.gold.opacity(0.4), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Compact rows

private struct LeaderboardRow: View {
    let entry: WatchSnapshot.WatchLeaderboardEntry
    let scale: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(WatchTheme.font(.caption, scale: scale, weight: .bold, design: .monospaced))
                .foregroundStyle(rankColor)
                .frame(width: 14, alignment: .leading)
            Circle()
                .fill(avatarFill)
                .frame(width: 14 * scale, height: 14 * scale)
            Text(entry.displayName)
                .font(WatchTheme.font(.body, scale: scale,
                                       weight: entry.isCurrentUser ? .semibold : .regular))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedScore(entry.score))
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium, design: .monospaced))
                .foregroundStyle(WatchTheme.inkSoft)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rankColor: Color {
        switch entry.rank {
        case 2: return Color(white: 0.78)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return WatchTheme.inkSoft
        }
    }

    private var avatarFill: AnyShapeStyle {
        if entry.isCurrentUser { return AnyShapeStyle(WatchTheme.brandGradient) }
        let palette: [Color] = [WatchTheme.danger, WatchTheme.success,
                                WatchTheme.violet, WatchTheme.accent, WatchTheme.warning]
        return AnyShapeStyle(palette[abs(entry.displayName.hashValue) % palette.count])
    }

    @ViewBuilder
    private var rowBackground: some View {
        if entry.isCurrentUser {
            LinearGradient(colors: [WatchTheme.accent.opacity(0.18),
                                    WatchTheme.accent.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WatchTheme.accent.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            Color.clear
        }
    }
}

private func formattedScore(_ score: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: score)) ?? "\(score)"
}

#if DEBUG
#Preview {
    FriendsTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
