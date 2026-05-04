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
    @EnvironmentObject private var backend: WatchBackendStore
    @Environment(\.watchFontScale) private var scale: Double

    @State private var signInError: String? = nil
    @State private var isSigningIn: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 26 * scale, weight: .regular))
                    .foregroundStyle(WatchTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                    .padding(.top, 4)

                Text("Set up Rung")
                    .font(WatchTheme.font(.title, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .multilineTextAlignment(.center)

                Text(headlineStatus)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(headlineColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

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

                // Secondary path: legacy WC retry (for when iPhone IS
                // reachable and you'd rather wait than sign in again).
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
                } catch {
                    signInError = "Backend rejected sign-in. Check your connection."
                    print("[Watch] Backend Apple auth failed: \(error)")
                }
            }
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

    private var retryButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            // Race the WC channel + the backend channel — whichever
            // comes back first wins. The user's tap is registered
            // immediately on the WC counter; backend retry runs in the
            // background.
            session.requestSnapshot()
            Task { await backend.refreshNow() }
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
        .environmentObject(WatchBackendStore.shared)
}
#Preview("Connecting") {
    ContentView()
        .environmentObject(WatchSession.preview(hasRealData: false))
        .environmentObject(WatchBackendStore.shared)
}
#endif
