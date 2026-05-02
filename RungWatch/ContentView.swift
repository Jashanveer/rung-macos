import SwiftUI

/// Root view for the watchOS Rung companion. Six tabs paged vertically by
/// the Digital Crown — Habits, Calendar, Stats, Friends, Mentor, Account.
/// Mirrors the iOS structure plus a recent-mentor-conversations tab so the
/// user can glance at the latest nudge from their wrist.
struct ContentView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var selectedTab: Int = 0

    var body: some View {
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

#Preview {
    ContentView()
        .environmentObject(WatchSession.shared)
}
