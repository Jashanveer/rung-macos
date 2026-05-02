import SwiftUI

/// App-launch orchestrator for the Rung intro sequence on iOS. Owns the warm
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
struct RungIntroView: View {
    @ObservedObject var backend: HabitBackendStore
    let onReady: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .intro
    @State private var introStart: Date = .distantFuture
    @State private var iconSize: CGFloat = 360
    @State private var didStart = false

    /// Flips true to tell the cascading `RungTransition` to fade out. The
    /// cascade fills the screen the moment a login/register button is tapped
    /// and stays covering until this signal arrives.
    @State private var cascadeDismissSignal = false
    /// True when the cascade is covering the screen at the direct request of
    /// a sign-in/register tap (the screen is covering *while* the API call
    /// runs). Drives whether we drop back to auth on failure.
    @State private var cascadeAwaitingAuth = false
    @Namespace private var loginNamespace

    private enum Phase {
        case intro     // RungIconView is building, centered
        case auth      // AuthGateView visible, icon has flown into card slot
        case cascade   // post-login grid cascade covers the screen
        case done      // overlay removed
    }

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
                // Auth finished. If the cascade is already up, drop the hold
                // so the grid fades and the dashboard is revealed.
                if phase == .cascade {
                    cascadeDismissSignal = true
                } else if phase == .auth {
                    raiseCascade(awaitingAuth: false)
                }
            } else if phase == .done {
                resetToAuth()
            }
        }
    }

    private func resetToAuth() {
        iconSize = 64
        cascadeAwaitingAuth = false
        cascadeDismissSignal = false
        withAnimation(.smooth(duration: 0.3)) {
            phase = .auth
        }
    }

    /// Raise the post-login cascade. Call with `awaitingAuth: true` when the
    /// cover must stay up while an API call runs (sign-in / register taps);
    /// `false` for short transitions like a returning user at launch.
    private func raiseCascade(awaitingAuth: Bool) {
        cascadeAwaitingAuth = awaitingAuth
        cascadeDismissSignal = false
        withAnimation(.smooth(duration: 0.12)) {
            phase = .cascade
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
                    onAuthStart: { raiseCascade(awaitingAuth: true) },
                    onAuthFailed: { cascadeDismissSignal = true },
                    onAuthenticated: {}
                )
                .transition(.opacity)
            }

            // Centered Rung icon + wordmark column. Wraps in a TimelineView
            // so the icon's internal staged build (driven by `time:`) ticks
            // at display refresh rate during `.intro` only.
            if phase == .intro {
                brandColumn
                    .transition(.opacity)
            }

            if phase == .cascade {
                RungTransition(
                    awaitDismiss: true,
                    dismiss: cascadeDismissSignal,
                    onCovered: {
                        // If this cascade isn't tied to an in-flight API call
                        // (e.g., returning user whose session was restored at
                        // launch), auto-fade once the grid has fully covered.
                        guard !cascadeAwaitingAuth else { return }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 240_000_000)
                            cascadeDismissSignal = true
                        }
                    },
                    onComplete: {
                        if backend.isAuthenticated {
                            withAnimation(.easeOut(duration: 0.2)) {
                                phase = .done
                            }
                            onReady()
                        } else {
                            // Auth was rejected — drop back to the auth card
                            // with whatever error the backend surfaced.
                            withAnimation(.smooth(duration: 0.3)) {
                                phase = .auth
                            }
                            cascadeAwaitingAuth = false
                            cascadeDismissSignal = false
                        }
                    }
                )
                .transition(.opacity)
            }
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
                raiseCascade(awaitingAuth: false)
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
            raiseCascade(awaitingAuth: false)
            return
        }

        // Hand off to the auth card. The icon flies into the card slot via
        // matched geometry because both sides share id "auth-app-icon".
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            iconSize = 64
            phase = .auth
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
