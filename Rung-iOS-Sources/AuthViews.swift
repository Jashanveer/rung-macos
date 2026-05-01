import AuthenticationServices
import SwiftUI

// MARK: - App icon motion

struct AuthExperienceOverlay: View {
    @ObservedObject var backend: HabitBackendStore
    let onAuthenticated: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var iconNamespace
    @State private var hasRunIntro = false
    @State private var showLogin = false
    @State private var introIconVisible = false
    @State private var introProgress: CGFloat = 0
    @State private var introIsReady = false

    private var shouldShowOverlay: Bool {
        !backend.isAuthenticated
    }

    var body: some View {
        Group {
            if shouldShowOverlay {
                ZStack {
                    if showLogin {
                        AuthGateView(backend: backend, iconNamespace: iconNamespace) {
                            onAuthenticated()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if !showLogin && !backend.isAuthenticated {
                        LaunchIconIntroView(
                            iconVisible: introIconVisible,
                            progress: introProgress,
                            isReady: introIsReady,
                            iconNamespace: iconNamespace
                        )
                        .transition(.opacity)
                    }
                }
                .background {
                    CleanShotTheme.canvas(for: colorScheme)
                        .ignoresSafeArea()
                        .opacity(showLogin ? 0 : 1)
                }
                .task { await runIntroIfNeeded() }
                .onChange(of: backend.isAuthenticated) { _, isAuthenticated in
                    guard !isAuthenticated else { return }
                    if hasRunIntro {
                        showLogin = true
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.24), value: shouldShowOverlay)
    }

    @MainActor
    private func runIntroIfNeeded() async {
        guard !hasRunIntro, !backend.isAuthenticated else {
            if !backend.isAuthenticated {
                showLogin = true
            }
            return
        }

        hasRunIntro = true
        showLogin = false
        introIconVisible = false
        introProgress = 0
        introIsReady = false

        try? await Task.sleep(nanoseconds: 140_000_000)
        withAnimation(.spring(response: 0.54, dampingFraction: 0.76)) {
            introIconVisible = true
        }

        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.linear(duration: 1.05)) {
            introProgress = 1
        }

        try? await Task.sleep(nanoseconds: 1_110_000_000)
        withAnimation(.easeInOut(duration: 0.28)) {
            introIsReady = true
        }

        try? await Task.sleep(nanoseconds: 260_000_000)
        withAnimation(.smooth(duration: 0.78)) {
            showLogin = true
        }
    }
}

private struct LaunchIconIntroView: View {
    let iconVisible: Bool
    let progress: CGFloat
    let isReady: Bool
    let iconNamespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            FloatingHabitBackground()
                .opacity(iconVisible ? 1 : 0.86)

            VStack(spacing: 18) {
                ConstructingAppIconView(progress: progress)
                    .frame(width: 214, height: 214)
                    .matchedGeometryEffect(id: "auth-app-icon", in: iconNamespace)
                    .shadow(
                        color: CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.34 : 0.22),
                        radius: iconVisible ? 34 : 12,
                        y: iconVisible ? 18 : 8
                    )
                    .scaleEffect(iconVisible ? 1 : 0.72)

                VStack(spacing: 7) {
                    Text(isReady ? "Ready." : "Building your day.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.82))
                        .contentTransition(.opacity)

                    Text("Blue by blue, one checked square at a time.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.48) : Color.black.opacity(0.44))
                }
                .opacity(iconVisible ? 1 : 0)
                .offset(y: iconVisible ? 0 : 12)
            }
            .animation(.spring(response: 0.56, dampingFraction: 0.8), value: iconVisible)
            .animation(.easeInOut(duration: 0.28), value: isReady)
        }
    }
}

private struct ConstructingAppIconView: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cornerRadius = side * 0.23
            let cellSize = side * 0.084
            let xStart = side * 0.25
            let yStart = side * 0.252
            let step = side * 0.134

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.067, blue: 0.088))

                ForEach(0..<16, id: \.self) { index in
                    let row = index / 4
                    let column = index % 4
                    let threshold = CGFloat(index + 1) / 16
                    let visible = min(max((progress - threshold + 0.11) / 0.11, 0), 1)

                    RoundedRectangle(cornerRadius: cellSize * 0.22, style: .continuous)
                        .fill(cellColor(for: index, progress: progress))
                        .frame(width: cellSize, height: cellSize)
                        .scaleEffect(0.58 + visible * 0.42)
                        .opacity(visible)
                        .position(
                            x: xStart + CGFloat(column) * step,
                            y: yStart + CGFloat(row) * step
                        )
                }

                CheckStroke(progress: max(0, min((progress - 0.82) / 0.16, 1)))
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: side * 0.09, height: side * 0.07)
                    .position(x: side * 0.667, y: side * 0.294)
                    .opacity(progress > 0.80 ? 1 : 0)

            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cellColor(for index: Int, progress: CGFloat) -> Color {
        let blue = Color(red: 0.18, green: 0.58, blue: 0.86)
        let dark = Color(red: 0.105, green: 0.126, blue: 0.160)

        if progress < 0.88 {
            return index < 12 ? blue : dark
        }

        switch index {
        case 10:
            return CleanShotTheme.gold
        case 11...15:
            return dark
        default:
            return blue
        }
    }
}

private struct CheckStroke: Shape {
    let progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set {}
    }

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.minX, y: rect.midY * 1.04),
            CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.minY)
        ]
        let segments: [(CGPoint, CGPoint)] = [
            (points[0], points[1]),
            (points[1], points[2])
        ]

        var path = Path()
        path.move(to: points[0])

        let firstSegmentLimit: CGFloat = 0.42
        if progress <= firstSegmentLimit {
            let local = progress / firstSegmentLimit
            path.addLine(to: interpolate(from: segments[0].0, to: segments[0].1, fraction: local))
            return path
        }

        path.addLine(to: segments[0].1)
        let local = (progress - firstSegmentLimit) / (1 - firstSegmentLimit)
        path.addLine(to: interpolate(from: segments[1].0, to: segments[1].1, fraction: local))
        return path
    }

    private func interpolate(from start: CGPoint, to end: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }
}

// MARK: - Background pills

private struct AuthPill: View {
    let label: String
    let dotColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor.opacity(0.75))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .kerning(-0.1)
                .foregroundStyle(
                    colorScheme == .dark
                        ? Color.white.opacity(0.55)
                        : Color.black.opacity(0.55)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.05)
                                : Color.white.opacity(0.55)
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.09)
                                : Color.black.opacity(0.07),
                            lineWidth: 0.75
                        )
                }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08),
            radius: 8, y: 2
        )
    }
}

struct FloatingHabitBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct HabitItem {
        let label: String
        let hue: Double  // 0…360
        let x: CGFloat   // normalized 0…1
        let y: CGFloat   // normalized 0…1
        let amplitudeX: CGFloat
        let amplitudeY: CGFloat
        let rotate: Double  // degrees
        let speed: Double   // cycles per second
        let phase: Double
    }

    // Positions from the design's POSITIONS array, each with a per-pill motion profile.
    private let items: [HabitItem] = [
        .init(label: "Running",      hue: 15,  x: 0.04, y: 0.07, amplitudeX: 13, amplitudeY: 16, rotate: 1.0,  speed: 0.11, phase: 0.0),
        .init(label: "Yoga",         hue: 280, x: 0.22, y: 0.05, amplitudeX: -12, amplitudeY: 19, rotate: -1.2, speed: 0.09, phase: 1.2),
        .init(label: "Meditation",   hue: 195, x: 0.44, y: 0.04, amplitudeX: 17, amplitudeY: 14, rotate: 1.6,  speed: 0.12, phase: 2.0),
        .init(label: "Walking",      hue: 145, x: 0.62, y: 0.06, amplitudeX: 11, amplitudeY: 17, rotate: 0.8,  speed: 0.08, phase: 2.9),
        .init(label: "Sleep",        hue: 245, x: 0.80, y: 0.04, amplitudeX: -13, amplitudeY: 19, rotate: -1.0, speed: 0.10, phase: 3.7),
        .init(label: "Reading",      hue: 45,  x: 0.02, y: 0.20, amplitudeX: 9,  amplitudeY: 15, rotate: 1.2,  speed: 0.09, phase: 4.3),
        .init(label: "Music",        hue: 305, x: 0.14, y: 0.32, amplitudeX: 13, amplitudeY: 16, rotate: 1.0,  speed: 0.11, phase: 0.7),
        .init(label: "Journaling",   hue: 65,  x: 0.34, y: 0.18, amplitudeX: -12, amplitudeY: 19, rotate: -1.5, speed: 0.09, phase: 1.6),
        .init(label: "Stretching",   hue: 165, x: 0.60, y: 0.23, amplitudeX: 15, amplitudeY: 12, rotate: 1.4,  speed: 0.12, phase: 2.4),
        .init(label: "Cycling",      hue: 200, x: 0.78, y: 0.17, amplitudeX: 11, amplitudeY: 17, rotate: 0.8,  speed: 0.07, phase: 3.3),
        .init(label: "Cold Shower",  hue: 215, x: 0.90, y: 0.30, amplitudeX: -12, amplitudeY: 19, rotate: -1.1, speed: 0.09, phase: 4.0),
        .init(label: "Hydration",    hue: 210, x: 0.00, y: 0.46, amplitudeX: 14, amplitudeY: 13, rotate: 1.3,  speed: 0.08, phase: 0.3),
        .init(label: "Study",        hue: 40,  x: 0.17, y: 0.54, amplitudeX: 13, amplitudeY: 16, rotate: 1.0,  speed: 0.11, phase: 1.1),
        .init(label: "Cooking",      hue: 55,  x: 0.73, y: 0.47, amplitudeX: -12, amplitudeY: 19, rotate: -1.2, speed: 0.09, phase: 1.8),
        .init(label: "Gratitude",    hue: 350, x: 0.88, y: 0.56, amplitudeX: 15, amplitudeY: 12, rotate: 1.4,  speed: 0.07, phase: 2.5),
        .init(label: "Strength",     hue: 10,  x: 0.04, y: 0.70, amplitudeX: 11, amplitudeY: 17, rotate: 0.8,  speed: 0.11, phase: 3.2),
        .init(label: "Mindfulness",  hue: 270, x: 0.15, y: 0.77, amplitudeX: -12, amplitudeY: 19, rotate: -1.3, speed: 0.12, phase: 3.9),
        .init(label: "Breathing",    hue: 185, x: 0.76, y: 0.71, amplitudeX: 15, amplitudeY: 12, rotate: 1.4,  speed: 0.08, phase: 0.2),
        .init(label: "Language",     hue: 100, x: 0.58, y: 0.82, amplitudeX: 13, amplitudeY: 16, rotate: 1.0,  speed: 0.10, phase: 0.9),
        .init(label: "Sleep Diary",  hue: 240, x: 0.90, y: 0.82, amplitudeX: -12, amplitudeY: 19, rotate: -1.2, speed: 0.09, phase: 1.7),
        .init(label: "Nutrition",    hue: 80,  x: 0.32, y: 0.90, amplitudeX: 15, amplitudeY: 12, rotate: 1.4,  speed: 0.11, phase: 2.4),
        .init(label: "Focus",        hue: 325, x: 0.54, y: 0.93, amplitudeX: 13, amplitudeY: 16, rotate: 1.0,  speed: 0.09, phase: 3.0)
    ]

    var body: some View {
        GeometryReader { geo in
            // On iPhone the login form occupies the center — keep pills to the
            // top/bottom strips only and thin them so the screen isn't crowded.
            // iPad stays with the full set.
            let narrow = geo.size.width < 500
            let displayItems: [HabitItem] = narrow
                ? items
                    .filter { $0.y < 0.30 || $0.y > 0.65 }
                    .enumerated()
                    .compactMap { idx, item in idx % 3 == 0 ? nil : item }
                : items

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    baseBackground

                    ForEach(displayItems.indices, id: \.self) { i in
                        let item = displayItems[i]
                        let theta = t * item.speed * 2 * .pi + item.phase
                        let offsetX = cos(theta) * item.amplitudeX
                        let offsetY = sin(theta) * item.amplitudeY
                        let rotation = sin(theta * 0.5) * item.rotate

                        AuthPill(label: item.label, dotColor: pillDot(hue: item.hue))
                            .rotationEffect(.degrees(rotation))
                            .offset(x: offsetX, y: offsetY)
                            .position(
                                x: item.x * geo.size.width,
                                y: item.y * geo.size.height
                            )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // Two radial washes over a dark or light base, matching the design's bg-canvas.
    private var baseBackground: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                (colorScheme == .dark
                    ? Color(red: 0.067, green: 0.067, blue: 0.075)
                    : Color(red: 0.941, green: 0.941, blue: 0.949)
                )

                // Top-left wash (periwinkle/blue)
                RadialGradient(
                    colors: [
                        colorScheme == .dark
                            ? Color(red: 0.15, green: 0.17, blue: 0.28).opacity(0.82)
                            : Color(red: 0.83, green: 0.85, blue: 0.95).opacity(0.78),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.15, y: 0.12),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.55
                )

                // Bottom-right wash (mauve)
                RadialGradient(
                    colors: [
                        colorScheme == .dark
                            ? Color(red: 0.19, green: 0.14, blue: 0.24).opacity(0.62)
                            : Color(red: 0.90, green: 0.86, blue: 0.94).opacity(0.55),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.85, y: 0.82),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.50
                )
            }
        }
    }

    private func pillDot(hue: Double) -> Color {
        // Approximates the design's oklch(0.58 0.09 H) dot colour.
        Color(hue: hue / 360.0, saturation: 0.55, brightness: 0.72)
    }
}

// MARK: - Auth Gate

struct AuthGateView: View {
    enum Step: Equatable {
        case signIn
        case signUp
        case verify
    }

    @ObservedObject var backend: HabitBackendStore
    let iconNamespace: Namespace.ID
    /// Called the instant the user taps a sign-in / register / send-code
    /// button — BEFORE the network call is issued. The intro orchestrator
    /// uses this to raise the yellow/blue cascade immediately so the grid
    /// hides the auth card while the API round-trip is in flight.
    var onAuthStart: (() -> Void)? = nil
    /// Called when an auth attempt finishes unsuccessfully (validation miss
    /// or server rejection). Lets the intro orchestrator pull the cascade
    /// back down and return focus to the auth card with the error shown.
    var onAuthFailed: (() -> Void)? = nil
    let onAuthenticated: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Step = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var selectedAvatarID = AvatarChoice.options[0].id
    @State private var validationMessage: String?
    @State private var successMessage: String?

    var body: some View {
        ZStack {
            CleanShotTheme.canvas(for: colorScheme)
                .ignoresSafeArea()

            FloatingHabitBackground()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.bottom, 22)

                        switch step {
                        case .signIn: signInContent
                        case .signUp: signUpContent
                        case .verify: verifyContent
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 460, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .center)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            }
        }
        .onChange(of: step) { _, _ in
            validationMessage = nil
            successMessage = nil
            backend.errorMessage = nil
        }
    }

    // MARK: Top bar (logo + toggle)

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 10) {
            if step == .verify {
                Button {
                    withAnimation(.smooth(duration: 0.24)) { step = .signUp }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CleanShotTheme.controlFill(for: colorScheme))
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            } else {
                HStack(spacing: 10) {
                    RungIconView(size: 34)
                        .matchedGeometryEffect(id: "auth-app-icon", in: iconNamespace)
                        .shadow(color: CleanShotTheme.accent.opacity(0.22), radius: 10, y: 4)
                    Text("Rung")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Apple-only sign-in surfaces no Sign Up tab — the
                // email/verification step machine + backend endpoints
                // are intentionally kept intact in case we ever want
                // to flip this back on, but the toggle is hidden.
                if false {
                Button {
                    withAnimation(.smooth(duration: 0.24)) {
                        step = (step == .signIn) ? .signUp : .signIn
                    }
                } label: {
                    HStack(spacing: 6) {
                        if step == .signUp {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(step == .signIn ? "Sign up" : "Sign in")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        if step == .signIn {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(CleanShotTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CleanShotTheme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                } // end if false
            }
        }
    }

    // MARK: Sign In

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to Rung.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("One-tap sign in or sign up with Apple — Hide My Email is supported.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Apple-only sign-in. Email/password code paths in
            // BackendAPIClient + AuthService stay intact for future use,
            // but the UI surfaces only the one-tap Apple flow per the
            // product decision to avoid the password-recovery / email-
            // verification surface area entirely.
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    Task { await handleAppleAuthorization(result) }
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.18),
                radius: 14, y: 6
            )
            .disabled(backend.isSyncing)

            messageBanner

            Text("By continuing you agree to our Terms & Privacy.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: Sign Up

    private var signUpContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let’s build something lasting.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("One daily habit at a time.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                AuthTextField(placeholder: "Username", text: $username, isSecure: false, colorScheme: colorScheme, autoFocus: true)
                AuthTextField(placeholder: "Email", text: $email, isSecure: false, colorScheme: colorScheme)
                AuthTextField(placeholder: "Password (8+ characters)", text: $password, isSecure: true, colorScheme: colorScheme)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("CHOOSE AN AVATAR")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(AvatarChoice.options.prefix(5)) { avatar in
                        AuthAvatarTile(
                            avatar: avatar,
                            isSelected: avatar.id == selectedAvatarID,
                            colorScheme: colorScheme
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                selectedAvatarID = avatar.id
                            }
                        }
                    }
                }
            }

            messageBanner

            AuthPrimaryButton(title: "Send verification code", isLoading: backend.isSyncing, action: requestVerificationCode)

            HStack(spacing: 6) {
                Text("Already have one?")
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.smooth(duration: 0.24)) { step = .signIn }
                } label: {
                    Text("Sign in")
                        .foregroundStyle(CleanShotTheme.accent)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    // MARK: Verify email

    private var verifyContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Verify your email.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                (
                    Text("We sent a code to ")
                        .foregroundStyle(.secondary)
                    + Text(email.isEmpty ? "your inbox" : email)
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                    + Text(".")
                        .foregroundStyle(.secondary)
                )
                .font(.system(size: 15, weight: .medium))
            }

            AuthCodeField(code: $verificationCode, colorScheme: colorScheme)

            messageBanner

            AuthPrimaryButton(title: "Verify", isLoading: backend.isSyncing, action: performRegistration)

            HStack(spacing: 6) {
                Text("Didn’t get it?")
                    .foregroundStyle(.secondary)
                Button(action: requestVerificationCode) {
                    Text("Resend")
                        .foregroundStyle(CleanShotTheme.accent)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .disabled(backend.isSyncing)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared chrome

    private var authDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(CleanShotTheme.stroke(for: colorScheme))
            .frame(height: 1)
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let message = validationMessage ?? backend.errorMessage {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CleanShotTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let successMessage {
            Text(successMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CleanShotTheme.success)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var selectedAvatar: AvatarChoice {
        AvatarChoice.options.first { $0.id == selectedAvatarID } ?? AvatarChoice.options[0]
    }

    private func performSignIn() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        successMessage = nil
        backend.errorMessage = nil

        guard isValidUsername(trimmedUsername) else {
            validationMessage = "Use 3-30 letters, numbers, or underscores for your username."
            return
        }
        guard !password.isEmpty else {
            validationMessage = "Enter your password."
            return
        }

        onAuthStart?()
        Task {
            await backend.signIn(username: trimmedUsername, password: password)
            if backend.isAuthenticated {
                onAuthenticated()
            } else {
                onAuthFailed?()
            }
        }
    }

    private func requestVerificationCode() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        successMessage = nil
        backend.errorMessage = nil

        guard isValidUsername(trimmedUsername) else {
            validationMessage = "Use 3-30 letters, numbers, or underscores for your username."
            return
        }
        guard trimmedEmail.contains("@") else {
            validationMessage = "Enter a valid email address."
            return
        }
        guard password.count >= 8 else {
            validationMessage = "Password must be at least 8 characters."
            return
        }

        Task {
            await backend.requestEmailVerification(email: trimmedEmail)
            if backend.errorMessage == nil {
                withAnimation(.smooth(duration: 0.24)) {
                    step = .verify
                    successMessage = "Check \(trimmedEmail) for your verification code."
                }
            }
        }
    }

    /// Handles the result of Apple's authorization sheet. On success we
    /// pass the verified identityToken straight to the backend, which
    /// validates it against Apple's JWKS and either links or provisions
    /// the account. Cancellations are silent — the user already signaled
    /// "no, not now" by dismissing the sheet, no error toast needed.
    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            backend.errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                backend.errorMessage = "Apple didn't return an identity token"
                return
            }
            let displayName: String? = {
                guard let components = credential.fullName else { return nil }
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
                return formatted.isEmpty ? nil : formatted
            }()
            onAuthStart?()
            await backend.signInWithApple(identityToken: token, displayName: displayName)
            if backend.isAuthenticated {
                onAuthenticated()
            } else {
                onAuthFailed?()
            }
        }
    }

    private func performRegistration() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        successMessage = nil
        backend.errorMessage = nil

        guard isValidVerificationCode(trimmedCode) else {
            validationMessage = "Enter the 6-digit code from your email."
            return
        }

        onAuthStart?()
        Task {
            await backend.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                avatarURL: selectedAvatar.url,
                verificationCode: trimmedCode
            )
            if backend.isAuthenticated {
                onAuthenticated()
            } else {
                onAuthFailed?()
            }
        }
    }

    private func isValidUsername(_ value: String) -> Bool {
        guard (3...30).contains(value.count) else { return false }
        return value.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
    }

    private func isValidVerificationCode(_ value: String) -> Bool {
        value.range(of: "^\\d{6}$", options: .regularExpression) != nil
    }
}

// MARK: - Field

private struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let colorScheme: ColorScheme
    var autoFocus: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        field
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(
                Capsule(style: .continuous)
                    .fill(CleanShotTheme.surface(for: colorScheme))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? CleanShotTheme.accent
                            : CleanShotTheme.stroke(for: colorScheme),
                        lineWidth: isFocused ? 1.6 : 1
                    )
            )
            .focused($isFocused)
            .animation(.smooth(duration: 0.14), value: isFocused)
            .contentShape(Capsule())
            .onTapGesture { isFocused = true }
            .onAppear {
                guard autoFocus else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isFocused = true
                }
            }
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
        }
    }
}

// MARK: - Primary button

private struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CleanShotTheme.accent)
            )
            .shadow(color: CleanShotTheme.accent.opacity(0.32), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct AuthAppleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 6-cell code field

private struct AuthCodeField: View {
    @Binding var code: String
    let colorScheme: ColorScheme

    @FocusState private var isFocused: Bool
    private let cellCount = 6

    var body: some View {
        ZStack {
            // Invisible backing TextField that actually captures input (incl. paste).
            TextField("", text: boundProxy)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled(true)
                .opacity(0.001)
                .frame(height: 52)
                .accessibilityLabel("Verification code")

            HStack(spacing: 10) {
                ForEach(0..<cellCount, id: \.self) { index in
                    cell(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isFocused = true }
        }
    }

    private var boundProxy: Binding<String> {
        Binding(
            get: { code },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                code = String(digitsOnly.prefix(cellCount))
            }
        )
    }

    private func cell(at index: Int) -> some View {
        let chars = Array(code)
        let filled = index < chars.count
        let isCurrent = index == chars.count && isFocused
        return Text(filled ? String(chars[index]) : " ")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CleanShotTheme.surface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isCurrent || filled
                            ? CleanShotTheme.accent
                            : CleanShotTheme.stroke(for: colorScheme),
                        lineWidth: (isCurrent || filled) ? 1.8 : 1
                    )
            )
    }
}

// MARK: - Avatar tile

private struct AuthAvatarTile: View {
    let avatar: AvatarChoice
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AsyncImage(url: URL(string: avatar.url)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CleanShotTheme.accent.opacity(0.6))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CleanShotTheme.surface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? CleanShotTheme.accent
                            : CleanShotTheme.stroke(for: colorScheme),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatar picker

struct AvatarChoice: Identifiable {
    let id: String
    let name: String
    let url: String

    static let options: [AvatarChoice] = [
        .init(id: "nova", name: "Nova", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Nova&size=96"),
        .init(id: "milo", name: "Milo", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Milo&size=96"),
        .init(id: "luna", name: "Luna", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Luna&size=96"),
        .init(id: "kai", name: "Kai", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Kai&size=96"),
        .init(id: "sage", name: "Sage", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Sage&size=96"),
        .init(id: "zara", name: "Zara", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Zara&size=96"),
        .init(id: "rio", name: "Rio", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Rio&size=96"),
        .init(id: "ivy", name: "Ivy", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Ivy&size=96"),
        .init(id: "leo", name: "Leo", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Leo&size=96"),
        .init(id: "maya", name: "Maya", url: "https://api.dicebear.com/9.x/adventurer/png?seed=Maya&size=96")
    ]
}

struct AvatarChoiceButton: View {
    let avatar: AvatarChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                AsyncImage(url: URL(string: avatar.url)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(avatar.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 60)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? CleanShotTheme.accent.opacity(0.16) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? CleanShotTheme.accent : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rung quotes

/// Rotating quotes shown on the auth screen. The metaphor is climbing a ladder —
/// each habit is a rung; each day is one step. Lines emphasize incremental
/// ascent, footing, and the slow accumulation that compounds into altitude.
enum RungQuotes {
    struct Quote {
        let line: String
        let attribution: String
    }

    static let all: [Quote] = [
        .init(line: "We are what we repeatedly do.", attribution: "Will Durant"),
        .init(line: "First we shape our habits, then our habits shape us.", attribution: "John Dryden"),
        .init(line: "Habits are the compound interest of self-improvement.", attribution: "James Clear"),
        .init(line: "You fall to the level of your systems.", attribution: "James Clear"),
        .init(line: "Discipline is destiny.", attribution: "Ryan Holiday"),
        .init(line: "What you do every day matters more than what you do once in a while.", attribution: "Gretchen Rubin"),
        .init(line: "One rung at a time.", attribution: "Rung"),
        .init(line: "Climb steady. Climb daily.", attribution: "Rung"),
        .init(line: "Each day is a rung.", attribution: "Rung"),
        .init(line: "Altitude is just consistency, stacked.", attribution: "Rung"),
        .init(line: "Skip a rung and the ladder still ends in the same place \u{2014} you just don't know how to get back.", attribution: "Rung"),
        .init(line: "Footing first. Then the next step.", attribution: "Rung")
    ]
}

// MARK: - Connection status icon

/// Minimal online/offline indicator. Blue cloud when connected, struck-through
/// grey cloud when the device has no route to the backend. The sync itself is
/// automatic (flushOutbox fires on reconnect) so there's no manual button.
struct ConnectionStatusIcon: View {
    @ObservedObject var backend: HabitBackendStore

    var body: some View {
        Image(systemName: backend.isOnline ? "icloud.fill" : "icloud.slash")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(backend.isOnline ? Color.blue : Color.secondary)
            .opacity(backend.isOnline ? 1 : 0.6)
            .accessibilityLabel(backend.isOnline ? "Online" : "Offline")
            .animation(.easeInOut(duration: 0.2), value: backend.isOnline)
    }
}
