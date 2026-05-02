import SwiftUI

/// Root view for the watchOS Rung companion. Six tabs paged vertically by
/// the Digital Crown — Habits, Calendar, Stats, Friends, Mentor, Account —
/// gated by a "connecting" state until the iPhone has pushed at least one
/// real snapshot. The font scale the user picks in the Account tab is
/// injected into the environment here so every screen below picks it up.
struct ContentView: View {
    @EnvironmentObject private var session: WatchSession
    @AppStorage("watchFontScaleRaw") private var fontScaleRaw: Double = WatchFontScale.default.rawValue
    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if session.hasReceivedRealData {
                tabs
            } else {
                ConnectingView()
            }
        }
        .environment(\.watchFontScale, fontScaleRaw)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // Habits is the only tab that drills into detail screens, so it
            // needs its own NavigationStack. The other tabs are leaf screens.
            NavigationStack {
                HabitsTab()
            }
            .tag(0)
            CalendarTab()
                .tag(1)
            StatsTab()
                .tag(2)
            FriendsTab()
                .tag(3)
            MentorTab()
                .tag(4)
            AccountTab()
                .tag(5)
        }
        .tabViewStyle(.verticalPage)
        .background(WatchTheme.bg.ignoresSafeArea())
    }
}

/// First-launch / disconnected state. Plain centered prompt so the user
/// knows the watch is alive — never any fake data, never a fake leaderboard.
private struct ConnectingView: View {
    @Environment(\.watchFontScale) private var scale: Double

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 28 * scale, weight: .regular))
                .foregroundStyle(WatchTheme.accent)
            Text("Open Rung\non iPhone")
                .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
                .multilineTextAlignment(.center)
            Text("Connecting…")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.bg.ignoresSafeArea())
    }
}

#if DEBUG
#Preview("Loaded") {
    ContentView()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#Preview("Connecting") {
    ContentView()
        .environmentObject(WatchSession.preview(hasRealData: false))
}
#endif
