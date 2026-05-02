import SwiftUI

/// Root view for the watchOS Rung companion. Five tabs paged vertically by
/// the Digital Crown — Habits, Calendar, Stats, Friends, Account — exactly
/// matching the iOS structure.
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
            AccountTab()
                .tag(4)
        }
        .tabViewStyle(.verticalPage)
        .background(WatchTheme.bg.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchSession.shared)
}
