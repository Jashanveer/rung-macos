import SwiftUI

/// App-launch orchestrator for the Rung intro sequence. Owns the warm
/// vignette backdrop for the entire cold-launch experience so the
/// authenticated dashboard never bleeds through during the intro.
///
/// Timeline (mirrors the design handoff `Rung Launch Animation.html`):
///
/// - `0.0–3.5s` — `RungIconView` builds piece-by-piece (tile fade,
///   ground draw, rails rise, ghost rungs, main rung drops with glow).
///   Wordmark "Rung" rises in at `2.5s`; tagline "One rung at a time"
///   follows at `2.85s`.
/// - `3.5–4.0s` — brief settle pause.
/// - `4.0s →` — icon shrinks and flies into the auth card slot via
///   `matchedGeometryEffect`, AuthGateView fades in.
///
/// On a successful sign-in the orchestrator hands off to `RungTransition`
/// (the post-login cascade), which acts as a loading cover for the
/// auth → dashboard swap. On failure the cascade fades back to the auth
/// card so the error stays visible.
struct RungIntroView: View {
    @ObservedObject var backend: HabitBackendStore
    let onReady: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .intro
    @State private var introStart: Date = .distantFuture
    @State private var iconSize: CGFloat = 360
    @State private var didStart = false

    /// True while the cascade is acting as a loading cover for a pending
    /// sign-in / register request. Drives failure recovery when the sync
    /// ends without a successful authentication.
    @State private var pendingAuthSubmission = false
    /// Passed to `RungTransition.readyToReveal`. Flips to `true` once the
    /// in-flight auth request has settled (success → dashboard, failure
    /// → back to the auth card). For the already-signed-in cold-launch
    /// path this is set true the moment we enter `.cascade`.
    @State private var cascadeShouldReveal = false
    @Namespace private var loginNamespace

    private enum Phase {
        case intro     // RungIconView is building, centered
        case auth      // AuthGateView visible, icon has flown into card slot
        case cascade   // post-login grid cascade covers the screen
        case done      // overlay removed, dashboard takes the screen
    }

    /// Once the orchestrator hits `.done`, the overlay only remounts if the
    /// user signs out (`isAuthenticated` flips back). Stay mounted otherwise
    /// so a stale rung icon never reappears over the dashboard.
    private var isVisible: Bool {
        if phase == .done { return !backend.isAuthenticated }
        return true
    }

    var body: some View {
        Group {
            if isVisible {
                content
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(phase != .done)
        .task {
            guard !didStart else { return }
            didStart = true
            await runIntro()
        }
        .onChange(of: backend.isAuthenticated) { _, isAuth in
            if isAuth {
                if phase == .cascade {
                    cascadeShouldReveal = true
                } else if phase == .auth {
                    Task { await beginCascade() }
                }
            } else if phase == .done {
                resetToAuth()
            }
        }
        .onChange(of: backend.isSyncing) { wasSyncing, isSyncing in
            // Auth attempt failed: the request ended (isSyncing true → false)
            // while we're covering the screen but still unauthenticated.
            // Let the cascade fade out so the auth card (with its error
            // message) is revealed underneath.
            guard wasSyncing, !isSyncing,
                  phase == .cascade,
                  pendingAuthSubmission,
                  !backend.isAuthenticated
            else { return }
            pendingAuthSubmission = false
            cascadeShouldReveal = true
        }
    }

    private func resetToAuth() {
        iconSize = 64
        pendingAuthSubmission = false
        cascadeShouldReveal = false
        withAnimation(.smooth(duration: 0.3)) {
            phase = .auth
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            // Warm vignette backdrop. Dark scheme matches the design's
            // `radial-gradient(ellipse at center, #221f1a 0%, #14110e 70%)`;
            // light scheme inverts to a warm cream → beige vignette.
            RadialGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0x22/255, green: 0x1F/255, blue: 0x1A/255),
                        Color.rungBg
                      ]
                    : [
                        Color(red: 0xFA/255, green: 0xF6/255, blue: 0xEC/255),
                        Color(red: 0xE8/255, green: 0xDF/255, blue: 0xC8/255)
                      ],
                center: .center,
                startRadius: 0,
                endRadius: 800
            )
            .ignoresSafeArea()

            // Auth card appears once we hand off; its internal appIcon slot
            // carries the matched-geometry counterpart to the centered icon.
            if phase == .auth || phase == .cascade {
                AuthGateView(
                    backend: backend,
                    iconNamespace: loginNamespace,
                    onAuthSubmit: handleAuthSubmit,
                    onAuthFailed: { cascadeShouldReveal = true },
                    onAuthenticated: {}
                )
                .transition(.opacity)
            }

            // The Rung icon + wordmark column. During `.intro` it lives
            // centered; the wordmark/tagline crossfade in mid-build (per the
            // design's 2.5–3.5s window). In `.auth` the icon flies into the
            // auth card slot via matched geometry and the brand column hides.
            if phase == .intro {
                brandColumn
                    .transition(.opacity)
            }

            if phase == .cascade {
                RungTransition(readyToReveal: cascadeShouldReveal) {
                    handleCascadeComplete()
                }
                .transition(.opacity)
            }
        }
    }

    /// Cascade has fully faded out — route to `.done` on a successful auth
    /// or back to `.auth` if the cascade was a loading cover for a request
    /// that failed.
    @MainActor
    private func handleCascadeComplete() {
        if backend.isAuthenticated {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .done
            }
            onReady()
        } else {
            pendingAuthSubmission = false
            cascadeShouldReveal = false
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .auth
            }
        }
    }

    /// Triggered by `AuthGateView` the moment a sign-in / final-register
    /// request is about to fire. Drops the cascade over the screen so the
    /// user sees a cover instead of a spinner-on-card while the backend works.
    @MainActor
    private func handleAuthSubmit() {
        guard phase == .auth else { return }
        pendingAuthSubmission = true
        cascadeShouldReveal = false
        withAnimation(.smooth(duration: 0.25)) {
            phase = .cascade
        }
    }

    // MARK: - Brand column

    private var brandColumn: some View {
        TimelineView(.animation) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(introStart))
            let t = min(elapsed, 3.5)

            VStack(spacing: 64) {
                RungIconView(size: iconSize, time: t)
                    .matchedGeometryEffect(id: "auth-app-icon", in: loginNamespace)
                    .shadow(color: Color.black.opacity(0.45), radius: 25, y: 30)
                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                    .animation(.spring(response: 0.6, dampingFraction: 0.82), value: iconSize)

                wordmarkBlock(elapsed: elapsed)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
        }
    }

    /// Wordmark + tagline. Both fade/slide in late in the launch (2.5s and
    /// 2.85s respectively per the design handoff), so we read elapsed and
    /// derive opacity / y-offset from it.
    @ViewBuilder
    private func wordmarkBlock(elapsed: Double) -> some View {
        let wordmarkOpacity = Self.tween(from: 0, to: 1, start: 2.50, end: 3.10, t: elapsed)
        let wordmarkY       = Self.tween(from: 18, to: 0, start: 2.50, end: 3.10, t: elapsed)
        let taglineOpacity  = Self.tween(from: 0, to: 0.7, start: 2.85, end: 3.45, t: elapsed)
        let taglineY        = Self.tween(from: 10, to: 0, start: 2.85, end: 3.45, t: elapsed)

        VStack(spacing: 18) {
            Text("Rung")
                .font(.system(size: 84, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.rungText : Color.rungRail)
                .kerning(-1.6)
                .opacity(wordmarkOpacity)
                .offset(y: wordmarkY)

            Text("ONE RUNG AT A TIME")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.rungAccent)
                .kerning(4.2)
                .opacity(taglineOpacity)
                .offset(y: taglineY)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Timeline

    @MainActor
    private func runIntro() async {
        if reduceMotion {
            iconSize = 64
            if backend.isAuthenticated {
                await beginCascade()
            } else {
                withAnimation(.smooth(duration: 0.3)) {
                    phase = .auth
                }
            }
            return
        }

        introStart = Date()

        // Let the launch animation run end-to-end (3.5s) plus a brief
        // half-second settle pause so the wordmark holds before we shrink.
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        if backend.isAuthenticated {
            // Already signed in — cascade directly into dashboard / onboarding.
            await beginCascade()
            return
        }

        // Hand off to the auth card. The icon flies into the card slot via
        // matched geometry because both sides share id "auth-app-icon".
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            iconSize = 64
            phase = .auth
        }
    }

    @MainActor
    private func beginCascade() async {
        // Already-authenticated path: backend has a valid session, so the
        // cascade plays its full cascade-in → hold → fade timeline without
        // waiting. Clear the submission flag so the failure handler in
        // onChange(isSyncing) doesn't misfire during this cascade.
        pendingAuthSubmission = false
        cascadeShouldReveal = true
        withAnimation(.smooth(duration: 0.3)) {
            phase = .cascade
        }
    }

    // MARK: - Easing for wordmark / tagline reveals

    private static func tween(from a: Double, to b: Double, start: Double, end: Double, t: Double) -> Double {
        if t <= start { return a }
        if t >= end { return b }
        let local = (t - start) / (end - start)
        // easeOutCubic
        let eased = 1 - pow(1 - local, 3)
        return a + (b - a) * eased
    }
}
