import SwiftUI

/// App-launch orchestrator. Owns the floating-pills background for the entire
/// cold-launch experience so the authenticated dashboard never bleeds through
/// during the intro. Runs the icon build, hands off to `AuthGateView` (whose
/// card slot receives the icon via matched geometry), then plays the
/// grid-cascade `FormaTransition` before dismissing to reveal the dashboard
/// underneath.
struct FormaIntroView: View {
    @ObservedObject var backend: HabitBackendStore
    let onReady: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .intro
    @State private var buildStep: Int = 0
    @State private var iconSize: CGFloat = 110
    @State private var titleVisible = false
    @State private var didStart = false
    @Namespace private var loginNamespace

    private enum Phase {
        case intro     // icon is building, centered
        case auth      // AuthGateView visible, icon has flown into the card slot
        case cascade   // grid cascade covers the screen
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
            if isAuth, phase == .auth {
                Task { await beginCascade() }
            } else if !isAuth, phase == .done {
                resetToAuth()
            }
        }
    }

    private func resetToAuth() {
        buildStep = 5
        titleVisible = true
        iconSize = 64
        withAnimation(.smooth(duration: 0.3)) {
            phase = .auth
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            // Pills background — always on while the intro overlay is mounted.
            // It adapts to colorScheme internally and covers whatever sits below
            // (dashboard, onboarding) so nothing leaks through the intro.
            FloatingHabitBackground()
                .ignoresSafeArea()

            // Auth card appears only once we hand off; its internal appIcon
            // carries the matched-geometry counterpart to our centered icon.
            if phase == .auth || phase == .cascade {
                AuthGateView(
                    backend: backend,
                    iconNamespace: loginNamespace,
                    onAuthenticated: {}
                )
                .transition(.opacity)
            }

            // Blue radial glow behind the building icon — only during intro.
            if phase == .intro {
                RadialGradient(
                    colors: [Color.formaBlue.opacity(0.13), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
                .blur(radius: 40)
                .frame(width: 520, height: 520)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // The Forma icon + wordmark. During .intro it lives centered; the
            // wordmark/tagline appear once the icon is fully built. In .auth
            // the icon flies into the card slot via matched geometry and the
            // brand column here hides.
            if phase == .intro {
                brandColumn
                    .transition(.opacity)
            }

            if phase == .cascade {
                FormaTransition {
                    withAnimation(.easeOut(duration: 0.2)) {
                        phase = .done
                    }
                    onReady()
                }
                .transition(.opacity)
            }
        }
    }

    private var brandColumn: some View {
        VStack(spacing: 12) {
            FormaIconView(size: iconSize, buildStep: buildStep)
                .matchedGeometryEffect(id: "auth-app-icon", in: loginNamespace)
                .shadow(color: Color.formaBlue.opacity(0.4), radius: 30, y: 10)
                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: iconSize)

            VStack(spacing: 4) {
                Text("Forma")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(wordmarkColor)

                Text("Form the habits that form you")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(taglineColor)
                    .textCase(.uppercase)
                    .kerning(1.2)
            }
            .opacity(titleVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: titleVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - Colors

    private var wordmarkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.82)
    }

    private var taglineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.48) : Color.black.opacity(0.44)
    }

    // MARK: - Timeline

    @MainActor
    private func runIntro() async {
        if reduceMotion {
            buildStep = 5
            titleVisible = true
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

        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 1
        try? await Task.sleep(nanoseconds: 200_000_000)
        buildStep = 2
        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 3
        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 4
        try? await Task.sleep(nanoseconds: 300_000_000)
        buildStep = 5
        titleVisible = true

        try? await Task.sleep(nanoseconds: 550_000_000)

        if backend.isAuthenticated {
            // Already signed in — cascade directly into dashboard (or onboarding).
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
        withAnimation(.smooth(duration: 0.3)) {
            phase = .cascade
        }
    }
}
