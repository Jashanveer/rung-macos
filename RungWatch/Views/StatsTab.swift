import SwiftUI

/// Stats tab — level number filling the screen with an XP progress ring,
/// the level name underneath, and a single XP-to-next-level line. Apple
/// Activity-app vibe: one big number, one secondary metric.
struct StatsTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    private var metrics: WatchSnapshot.Metrics { session.snapshot.metrics }

    var body: some View {
        VStack(spacing: 8) {
            WatchPageTitle("Stats", accent: WatchTheme.cCyan)
            ringHero
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .watchWashBackground(.violet)
    }

    private var ringHero: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 7)
            Circle()
                .trim(from: 0, to: metrics.nextLevelProgress)
                .stroke(WatchTheme.brandGradient,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8),
                           value: metrics.nextLevelProgress)

            VStack(spacing: -2) {
                Text("\(metrics.level)")
                    .font(WatchTheme.font(.hero, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.ink)
                if !metrics.levelName.isEmpty {
                    Text(metrics.levelName.uppercased())
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(WatchTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130 * scale)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            chip(value: "\(formattedXP)", label: "XP", tint: WatchTheme.cCyan)
            chip(value: rankString, label: "RANK", tint: WatchTheme.cAmber)
            chip(value: "\(metrics.freezesAvailable)", label: "FREEZE", tint: WatchTheme.cViolet)
        }
    }

    private func chip(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(WatchTheme.inkSoft)
            Text(value)
                .font(WatchTheme.font(.body, scale: scale, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .liquidGlassSurface(cornerRadius: 9, tint: tint)
    }

    private var formattedXP: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: metrics.xp)) ?? "\(metrics.xp)"
    }

    private var rankString: String {
        metrics.leaderboardRank > 0 ? "#\(metrics.leaderboardRank)" : "—"
    }
}

#if DEBUG
#Preview {
    StatsTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
