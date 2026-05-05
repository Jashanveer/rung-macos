import SwiftUI
import WatchKit
import AuthenticationServices

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
            // Show tabs the moment we have *any* data — cached from a
            // prior session, freshly pushed via WC, or (future) fetched
            // straight from the backend. The "Open Rung on iPhone" view
            // only renders for the first-ever cold launch when nothing
            // has ever been received, so a paired-but-unreachable phone
            // doesn't leave the watch staring at a stuck screen.
            if session.hasReceivedRealData, !session.snapshot.account.handle.isEmpty {
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
            // Add tab — second from the top so users find it on the
            // first crown turn. Tiny floating mic was hard to tap (per
            // user feedback); this is a full surface with a big mic.
            AddEntryView()
                .tag(1)
            CalendarTab()
                .tag(2)
            EnergyTab()
                .tag(3)
            StatsTab()
                .tag(4)
            FriendsTab()
                .tag(5)
            MentorTab()
                .tag(6)
            AccountTab()
                .tag(7)
        }
        .tabViewStyle(.verticalPage)
        .background(Color(hex: 0x06070B).ignoresSafeArea())
        .onChange(of: selectedTab) { _, _ in
            // Light tap-feedback on tab change so the user feels the
            // page commit, matching the haptics on the iOS app's tab bar.
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.click)
            #endif
        }
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
    @EnvironmentObject private var backend: WatchBackendStore
    @Environment(\.watchFontScale) private var scale: Double

    @State private var signInError: String? = nil
    @State private var isSigningIn: Bool = false
    /// Bumped on each fresh-launch / sign-in attempt so the underlying
    /// `SignInWithAppleButton` gets a new SwiftUI identity. watchOS
    /// occasionally holds onto a previous `ASAuthorizationController`'s
    /// completed state, which silently no-ops the next tap.
    @State private var appleButtonResetCount: Int = 0
    /// Drives the entrance animation — flipped to true a few frames
    /// after onAppear so the hero spring-scales into place. Without
    /// this the screen pops in flat and feels cheap.
    @State private var hasAppeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 26 * scale, weight: .regular))
                    .foregroundStyle(WatchTheme.accent)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    .padding(.top, 4)
                    .scaleEffect(hasAppeared ? 1.0 : 0.7)
                    .opacity(hasAppeared ? 1 : 0)

                Text("Set up Rung")
                    .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 6)

                Text(headlineStatus)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(headlineColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(WatchMotion.smooth, value: headlineStatus)

                // Primary path: sign in directly on the watch with Apple.
                // No iPhone reachability required, no WC handshake — the
                // watch authenticates standalone and starts pulling data
                // from the backend immediately.
                signInWithAppleButton

                if let signInError {
                    Text(signInError)
                        .font(WatchTheme.font(.label, scale: scale, weight: .medium))
                        .foregroundStyle(WatchTheme.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                // The Sign-in-with-Apple button + headline status are
                // the only controls the user needs here. Retry / WC
                // diagnostic block were removed once the watch became
                // a standalone backend client — neither was actionable
                // for end users and they cluttered the cold-launch.
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .background(WatchWashBackground(wash: .violet))
        .onAppear {
            // Spring the hero in once per fresh view appearance.
            // Disabling-then-enabling is jitter-free because withAnimation
            // wraps the state change rather than the view body.
            withAnimation(WatchMotion.smooth.delay(0.05)) {
                hasAppeared = true
            }
        }
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

    private var signInWithAppleButton: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                handleAppleSignIn(result)
            }
        )
        .signInWithAppleButtonStyle(.white)
        .frame(height: 44)
        .clipShape(Capsule(style: .continuous))
        .disabled(isSigningIn)
        // Force a fresh button identity after each Retry so the next tap
        // doesn't hit a watchOS-stale `ASAuthorizationController`.
        .id(appleButtonResetCount)
        .padding(.top, 6)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            signInError = "Sign-in failed. Try again."
            print("[Watch] Apple sign-in failed: \(error)")
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                signInError = "Apple didn't return a token."
                return
            }
            let displayName: String? = {
                guard let components = credential.fullName else { return nil }
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
                return formatted.isEmpty ? nil : formatted
            }()
            isSigningIn = true
            signInError = nil
            Task {
                defer { isSigningIn = false }
                do {
                    let client = WatchBackendClient()
                    let auth = try await client.exchangeAppleToken(
                        identityToken: identityToken,
                        displayName: displayName
                    )
                    await backend.acceptAuthResult(auth)
                    WKInterfaceDevice.current().play(.success)
                } catch let backendError as WatchBackendClient.Error {
                    signInError = Self.errorMessage(for: backendError)
                    print("[Watch] Backend Apple auth failed: \(backendError)")
                } catch {
                    signInError = "Couldn't reach the server. Try again when you're back online."
                    print("[Watch] Backend Apple auth failed: \(error)")
                }
            }
        }
    }

    /// Map `WatchBackendClient.Error` to actionable, distinguishable
    /// copy. The previous "Backend rejected sign-in. Check your
    /// connection." conflated server-side rejects (HTTP 4xx) with
    /// transport failures — users couldn't tell which to fix, and the
    /// iCloud-token path almost never throws "rejected" without a
    /// real cause.
    private static func errorMessage(for error: WatchBackendClient.Error) -> String {
        switch error {
        case .transport:
            return "Couldn't reach the server. Try again when you're back online."
        case .unauthorized:
            return "Backend rejected this Apple ID. Try again or sign in on iPhone."
        case .http(let code):
            if (500...599).contains(code) {
                return "Server is having trouble (\(code)). Try again in a minute."
            }
            if (400...499).contains(code) {
                return "Backend rejected sign-in (\(code)). Try again."
            }
            return "Sign-in failed (\(code)). Try again."
        case .decode:
            return "Couldn't read the server's response. Try again."
        case .noToken, .noSnapshotYet:
            // These shouldn't surface from sign-in — they're snapshot-fetch
            // states. Fall back to the generic copy if they do.
            return "Sign-in failed. Try again."
        }
    }

    /// One-line copy under "Set up Rung" — describes what the user
    /// should do next. WC reachability isn't surfaced here anymore;
    /// the watch is a standalone backend client and a flaky WC link
    /// no longer blocks sync.
    private var headlineStatus: String {
        if WatchAuthStore.shared.current() == nil {
            return "Sign in with Apple to start syncing"
        }
        if backend.isFetching {
            return "Syncing…"
        }
        if let err = backend.lastError {
            return err
        }
        return "Connecting to Rung"
    }

    private var headlineColor: Color {
        if backend.lastError == nil { return WatchTheme.inkSoft }
        return WatchTheme.warning
    }
}

#if DEBUG
#Preview("Loaded") {
    ContentView()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
        .environmentObject(WatchBackendStore.shared)
}
#Preview("Connecting") {
    ContentView()
        .environmentObject(WatchSession.preview(hasRealData: false))
        .environmentObject(WatchBackendStore.shared)
}
#endif
