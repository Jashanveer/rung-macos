import SwiftUI
import WatchKit

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

/// First-launch / disconnected state. Shows the live WCSession diagnostic
/// so the user can tell exactly why nothing's loading — activation pending,
/// phone asleep, or watch app not installed on the iPhone's companion
/// store. Retry button does belt-and-suspenders sending and bumps an
/// attempt counter so even if delivery silently fails, the tap is visibly
/// registered.
private struct ConnectingView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 28 * scale, weight: .regular))
                    .foregroundStyle(WatchTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                    .padding(.top, 4)

                Text("Open Rung\non iPhone")
                    .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .multilineTextAlignment(.center)

                Text(headlineStatus)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(headlineColor)
                    .multilineTextAlignment(.center)

                retryButton

                diagnosticBlock
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .background(WatchTheme.bg.ignoresSafeArea())
        .task {
            // Self-healing loop: if the watch was offline when the iPhone
            // pushed and we missed the first snapshot, ask again every few
            // seconds until something arrives. Cancellation kicks in
            // automatically when the view disappears (i.e. as soon as
            // `hasReceivedRealData` flips to true).
            for _ in 0..<60 {
                if session.hasReceivedRealData { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                if session.hasReceivedRealData { return }
                session.requestSnapshot()
            }
        }
    }

    private var headlineStatus: String {
        if !session.diagnostic.isCompanionAppInstalled {
            return "iPhone Rung not detected"
        }
        if session.isReachable {
            return "Paired · waiting for data"
        }
        return "Phone unreachable · queuing"
    }

    private var headlineColor: Color {
        session.isReachable ? WatchTheme.inkSoft : WatchTheme.warning
    }

    private var retryButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            session.requestSnapshot()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                Text(session.retryCount == 0 ? "Retry" : "Retry · \(session.retryCount)")
            }
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
        .padding(.top, 4)
    }

    private var diagnosticBlock: some View {
        VStack(spacing: 2) {
            row(label: "STATE", value: session.diagnostic.activationState,
                ok: session.diagnostic.activationState == "activated")
            row(label: "REACH", value: session.isReachable ? "yes" : "no",
                ok: session.isReachable)
            row(label: "PAIR",  value: session.diagnostic.isCompanionAppInstalled ? "yes" : "no",
                ok: session.diagnostic.isCompanionAppInstalled)
            if let err = session.lastSendError {
                Text(err)
                    .font(WatchTheme.font(.label, scale: scale, weight: .regular))
                    .foregroundStyle(WatchTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 6)
    }

    private func row(label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.inkSoft)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(WatchTheme.font(.label, scale: scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(ok ? WatchTheme.success : WatchTheme.warning)
            Spacer()
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
