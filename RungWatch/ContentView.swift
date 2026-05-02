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

/// First-launch / disconnected state. Shows the live reachability so the
/// user can tell whether their iPhone is awake, plus a Retry button and an
/// auto-retry loop so a brief paired-but-not-yet-pushed window self-heals.
private struct ConnectingView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    @State private var attempts: Int = 0

    var body: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 28 * scale, weight: .regular))
                .foregroundStyle(WatchTheme.accent)
                .symbolEffect(.pulse, options: .repeating)

            Text("Open Rung\non iPhone")
                .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
                .multilineTextAlignment(.center)

            Text(session.isReachable ? "Paired · waiting for data" : "Phone not reachable")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .foregroundStyle(WatchTheme.inkSoft)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                attempts += 1
                session.requestSnapshot()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(WatchTheme.brandGradient)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.bg.ignoresSafeArea())
        .task {
            // Self-healing loop: if the watch was offline when the iPhone
            // pushed and we missed the first snapshot, ask again every few
            // seconds until something arrives or the user taps Retry.
            // Cancellation kicks in automatically when the view disappears
            // (i.e. as soon as `hasReceivedRealData` flips to true).
            for _ in 0..<60 {   // 60 × 3s = 3 min ceiling, then stop
                if session.hasReceivedRealData { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                if session.hasReceivedRealData { return }
                session.requestSnapshot()
            }
        }
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
