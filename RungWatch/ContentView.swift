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
            CalendarTab()
                .tag(1)
            EnergyTab()
                .tag(2)
            StatsTab()
                .tag(3)
            FriendsTab()
                .tag(4)
            MentorTab()
                .tag(5)
            AccountTab()
                .tag(6)
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
    /// Bumped on each Retry tap so the underlying `SignInWithAppleButton`
    /// gets a fresh SwiftUI identity. Without this, watchOS occasionally
    /// holds onto the previous `ASAuthorizationController`'s completed
    /// state and the next tap silently no-ops.
    @State private var appleButtonResetCount: Int = 0
    /// Strong reference to the in-flight `ASAuthorizationController`
    /// triggered programmatically by the Retry button. The coordinator
    /// must outlive `performRequests()` or the system drops the callback
    /// without ever calling our completion handler.
    @State private var pendingAppleCoordinator: AppleSignInCoordinator? = nil
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

                // Retry: when the watch has no token yet, this re-runs
                // Apple sign-in directly so the user doesn't have to hunt
                // for the SignInWithApple button after a failure. Once
                // signed in, it falls back to the WC + backend refresh
                // dual-channel snapshot fetch.
                retryButton
                diagnosticBlock
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

    /// Fires Apple's authorization controller programmatically — used by
    /// the Retry button so a single tap does what the user expects:
    /// re-prompt for Apple sign-in. Also drives the same downstream
    /// success/failure mapping `handleAppleSignIn` runs for the
    /// SignInWithAppleButton path.
    private func triggerAppleSignInProgrammatically() {
        guard !isSigningIn else { return }
        signInError = nil
        let coordinator = AppleSignInCoordinator { result in
            Task { @MainActor in
                handleAppleSignIn(result)
                pendingAppleCoordinator = nil
            }
        }
        pendingAppleCoordinator = coordinator
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        // `presentationContextProvider` is unavailable on watchOS — the
        // system hosts the authorization sheet in the active scene.
        controller.performRequests()
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

    private var headlineStatus: String {
        // Backend channel is the primary path now. If we have a token,
        // surface the network status; otherwise fall back to WC copy.
        if WatchAuthStore.shared.current() == nil {
            return "Open Rung on iPhone once to set up sync"
        }
        if backend.isFetching {
            return "Syncing from backend…"
        }
        if let err = backend.lastError {
            return err
        }
        if !session.diagnostic.isCompanionAppInstalled {
            return "Backend OK · iPhone Rung not detected"
        }
        if session.isReachable {
            return "Paired · waiting for data"
        }
        return "Backend offline · trying again"
    }

    private var headlineColor: Color {
        if backend.lastError == nil { return WatchTheme.inkSoft }
        return WatchTheme.warning
    }

    /// True while the watch hasn't completed Apple sign-in. The Retry
    /// button retargets here: instead of pinging the WC channel (which
    /// can't help when there's no token), it re-runs Apple sign-in.
    private var hasNoAuthToken: Bool {
        WatchAuthStore.shared.current() == nil
    }

    private var retryButton: some View {
        Button {
            if hasNoAuthToken {
                // No session yet — the only thing that can unblock the
                // user is re-running Apple sign-in. Re-arm the system
                // button's identity in case watchOS cached its state,
                // then fire the auth controller directly so a single
                // Retry tap does what the user expects.
                appleButtonResetCount &+= 1
                triggerAppleSignInProgrammatically()
                return
            }
            // Already signed in — race the WC channel + backend channel.
            // The user's tap is registered immediately on the WC
            // counter; backend retry runs in the background.
            session.requestSnapshot()
            Task { await backend.refreshNow() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hasNoAuthToken ? "arrow.clockwise.circle" : "arrow.clockwise")
                    .symbolEffect(.rotate, value: session.retryCount)
                Text(retryButtonLabel)
                    .contentTransition(.numericText())
                    .animation(WatchMotion.micro, value: session.retryCount)
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
        .buttonStyle(WatchPressStyle())
        .disabled(isSigningIn)
        .opacity(isSigningIn ? 0.6 : 1)
        .animation(WatchMotion.snappy, value: isSigningIn)
        .padding(.top, 4)
    }

    private var retryButtonLabel: String {
        if hasNoAuthToken {
            return signInError == nil ? "Try sign-in again" : "Retry sign-in"
        }
        return session.retryCount == 0 ? "Retry" : "Retry · \(session.retryCount)"
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

// MARK: - Apple sign-in coordinator

/// Bridges `ASAuthorizationController` to a Swift closure callback so the
/// Retry button can fire Apple sign-in programmatically (the SwiftUI
/// `SignInWithAppleButton` only triggers on a direct tap of itself). The
/// owning view holds a strong reference until the system delivers either
/// `didCompleteWithAuthorization` or `didCompleteWithError` — releasing
/// the coordinator before that point silently drops the callback.
///
/// `ASAuthorizationControllerPresentationContextProviding` is unavailable
/// on watchOS, so we omit it; the system auto-hosts the authorization
/// sheet in the active scene without one.
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate {

    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        completion(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        completion(.failure(error))
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
