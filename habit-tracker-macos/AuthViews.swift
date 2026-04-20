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
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    baseBackground

                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
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
    @ObservedObject var backend: HabitBackendStore
    let iconNamespace: Namespace.ID
    let onAuthenticated: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: AuthMode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var isVerificationCodeSent = false
    @State private var successMessage: String?
    @State private var selectedAvatarID = AvatarChoice.options[0].id
    @State private var validationMessage: String?
    @State private var quoteIndex: Int = Int.random(in: 0..<FormaQuotes.all.count)

    private let cardWidth: CGFloat = 368

    var body: some View {
        ZStack {
            cardView
                .frame(width: cardWidth)
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 32)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.118, green: 0.118, blue: 0.133).opacity(0.82)
                                    : Color.white.opacity(0.72)
                            )
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.09)
                                    : Color.white.opacity(0.9),
                                lineWidth: 1
                            )
                    }
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.18),
                    radius: 32, y: 18
                )
        }
    }

    // MARK: Card

    private var cardView: some View {
        VStack(spacing: 0) {
            appIcon
                .padding(.bottom, 18)

            Text(headlineTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(titleColor)
                .padding(.bottom, 6)

            VStack(spacing: 3) {
                Text("\u{201C}\(FormaQuotes.all[quoteIndex].line)\u{201D}")
                    .font(.system(size: 12.5, weight: .medium, design: .serif))
                    .italic()
                    .kerning(-0.1)
                    .foregroundStyle(subtitleColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(FormaQuotes.all[quoteIndex].attribution)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(termsColor)
                    .kerning(0.3)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.bottom, 20)
            .contentTransition(.opacity)
            .id(quoteIndex)
            .onTapGesture { shuffleQuote() }
            .help("Tap for another")

            tabSwitcher
                .padding(.bottom, 16)

            VStack(spacing: 10) {
                authInput(placeholder: "Username", text: $username, isSecure: false)
                    .onSubmit { submit() }

                if mode == .signUp {
                    authInput(placeholder: "Email", text: $email, isSecure: false)
                        .onChange(of: email) { _, _ in
                            isVerificationCodeSent = false
                            verificationCode = ""
                            successMessage = nil
                        }
                        .onSubmit { submit() }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                authInput(placeholder: "Password", text: $password, isSecure: true)
                    .onSubmit { submit() }

                if mode == .signUp && isVerificationCodeSent {
                    authInput(placeholder: "6-digit verification code",
                              text: $verificationCode, isSecure: false)
                        .onSubmit { submit() }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if mode == .signUp {
                avatarGrid
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let message = validationMessage ?? backend.errorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0.84, green: 0.30, blue: 0.30))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let successMessage {
                Text(successMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0.28, green: 0.66, blue: 0.36))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if backend.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(primaryActionTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(GradientPrimaryButtonStyle())
            .disabled(backend.isSyncing)
            .padding(.top, 14)

            if mode == .signUp && isVerificationCodeSent {
                Button("Resend code", action: resendVerificationCode)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(subtitleColor)
                    .disabled(backend.isSyncing)
                    .padding(.top, 10)
            }

            Text(mode == .signIn
                 ? "Forgot password?"
                 : "By continuing you agree to our Terms & Privacy")
                .font(.system(size: 11.5))
                .foregroundStyle(termsColor)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }

    // MARK: Sub-components

    private var appIcon: some View {
        FormaIconView(size: 60)
            .matchedGeometryEffect(id: "auth-app-icon", in: iconNamespace)
            .shadow(color: Color.formaBlue.opacity(colorScheme == .dark ? 0.45 : 0.28), radius: 18, y: 8)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 2) {
            tabButton(title: "Sign In", active: mode == .signIn) { switchMode(.signIn) }
            tabButton(title: "Sign Up", active: mode == .signUp) { switchMode(.signUp) }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.05)
                        : Color.black.opacity(0.05)
                )
        }
    }

    private func tabButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .kerning(-0.1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(
                    active
                        ? (colorScheme == .dark
                           ? Color.white.opacity(0.92)
                           : Color.black.opacity(0.85))
                        : (colorScheme == .dark
                           ? Color.white.opacity(0.35)
                           : Color.black.opacity(0.35))
                )
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.10)
                                    : Color.white.opacity(0.85)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func authInput(placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        AuthInputField(
            placeholder: placeholder,
            text: text,
            isSecure: isSecure,
            colorScheme: colorScheme
        )
    }

    private var avatarGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose an avatar")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(subtitleColor)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 8), count: 5), spacing: 8) {
                ForEach(AvatarChoice.options) { avatar in
                    AvatarChoiceButton(
                        avatar: avatar,
                        isSelected: avatar.id == selectedAvatarID
                    ) {
                        selectedAvatarID = avatar.id
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Colours

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.36) : Color.black.opacity(0.38)
    }

    private var termsColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.28)
    }

    // MARK: Modes + flow

    private enum AuthMode {
        case signIn
        case signUp

        var primaryActionTitle: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            }
        }
    }

    private var headlineTitle: String {
        switch mode {
        case .signIn: return "Back in form."
        case .signUp: return "Find your form."
        }
    }

    private var selectedAvatar: AvatarChoice {
        AvatarChoice.options.first { $0.id == selectedAvatarID } ?? AvatarChoice.options[0]
    }

    private var primaryActionTitle: String {
        if mode == .signUp && !isVerificationCodeSent {
            return "Send verification code"
        }
        return mode.primaryActionTitle
    }

    private func switchMode(_ nextMode: AuthMode) {
        withAnimation(.smooth(duration: 0.22)) {
            mode = nextMode
            validationMessage = nil
            successMessage = nil
            backend.errorMessage = nil
            shuffleQuote(animated: false)
        }
    }

    private func shuffleQuote(animated: Bool = true) {
        let next: Int = {
            guard FormaQuotes.all.count > 1 else { return 0 }
            var candidate = Int.random(in: 0..<FormaQuotes.all.count)
            while candidate == quoteIndex {
                candidate = Int.random(in: 0..<FormaQuotes.all.count)
            }
            return candidate
        }()
        if animated {
            withAnimation(.smooth(duration: 0.28)) { quoteIndex = next }
        } else {
            quoteIndex = next
        }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVerificationCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        successMessage = nil
        backend.errorMessage = nil

        guard isValidUsername(trimmedUsername) else {
            validationMessage = "Use 3-30 letters, numbers, or underscores for username."
            return
        }

        if mode == .signUp && !trimmedEmail.contains("@") {
            validationMessage = "Enter a valid email address."
            return
        }

        guard mode == .signIn ? !password.isEmpty : password.count >= 8 else {
            validationMessage = "Password must be at least 8 characters."
            return
        }

        if mode == .signUp && isVerificationCodeSent && !isValidVerificationCode(trimmedVerificationCode) {
            validationMessage = "Enter the 6-digit verification code from your email."
            return
        }

        Task {
            switch mode {
            case .signIn:
                await backend.signIn(username: trimmedUsername, password: password)
            case .signUp:
                if !isVerificationCodeSent {
                    await backend.requestEmailVerification(email: trimmedEmail)
                    if backend.errorMessage == nil {
                        isVerificationCodeSent = true
                        successMessage = "Check \(trimmedEmail) for your verification code."
                    }
                    return
                }

                await backend.register(
                    username: trimmedUsername,
                    email: trimmedEmail,
                    password: password,
                    avatarURL: selectedAvatar.url,
                    verificationCode: trimmedVerificationCode
                )
            }

            if backend.isAuthenticated {
                onAuthenticated()
            }
        }
    }

    private func resendVerificationCode() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        successMessage = nil
        backend.errorMessage = nil

        guard trimmedEmail.contains("@") else {
            validationMessage = "Enter a valid email address."
            return
        }

        Task {
            await backend.requestEmailVerification(email: trimmedEmail)
            if backend.errorMessage == nil {
                verificationCode = ""
                successMessage = "A new code was sent to \(trimmedEmail)."
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

// MARK: - Input field

private struct AuthInputField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let colorScheme: ColorScheme

    @FocusState private var isFocused: Bool

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    private var strokeColor: Color {
        if isFocused { return CleanShotTheme.accent }
        return colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.09)
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.85)
    }

    var body: some View {
        rawField
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .kerning(-0.1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(fieldFill, in: fieldShape)
            .overlay {
                fieldShape.strokeBorder(strokeColor, lineWidth: 1)
            }
            .overlay {
                if isFocused {
                    fieldShape
                        .strokeBorder(CleanShotTheme.accent.opacity(0.25), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .focused($isFocused)
            .animation(.smooth(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var rawField: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

// MARK: - Primary button

private struct GradientPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .kerning(-0.1)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CleanShotTheme.accent.opacity(0.96),
                                CleanShotTheme.accent.opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: CleanShotTheme.accent.opacity(isEnabled ? 0.35 : 0),
                radius: configuration.isPressed ? 6 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .opacity(isEnabled ? 1 : 0.45)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

// MARK: - Forma quotes

/// Rotating quotes shown on the auth screen. Riffs on "forma" — Latin for
/// form, shape, figure, beauty — and its pull toward repetition and habit.
enum FormaQuotes {
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
        .init(line: "Form the habits that form you.", attribution: "Forma"),
        .init(line: "Small things, done daily, take shape.", attribution: "Forma"),
        .init(line: "Repetition is the mother of form.", attribution: "Forma"),
        .init(line: "Forma \u{2014} Latin. Form. Shape. The figure you become.", attribution: "Etymology"),
        .init(line: "Motion, repeated, becomes form.", attribution: "Forma"),
        .init(line: "The shape of your life is the sum of your days.", attribution: "Forma")
    ]
}

// MARK: - Connection status pill (unchanged)

struct ConnectionStatusPill: View {
    @ObservedObject var backend: HabitBackendStore
    let onSync: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: backend.isAuthenticated ? "server.rack" : "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(backend.errorMessage == nil ? CleanShotTheme.success : CleanShotTheme.warning)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if backend.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            } else if backend.isAuthenticated {
                Button(action: onSync) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .cleanShotSurface(shape: Capsule(), level: .control, isActive: isHovered)
        .onHover { isHovered = $0 }
    }

    private var statusText: String {
        if let errorMessage = backend.errorMessage {
            return errorMessage
        }

        if backend.isSyncing {
            return "Syncing..."
        }

        return backend.isAuthenticated
            ? (backend.statusMessage ?? "Connected to \(BackendEnvironment.displayHost)")
            : "Backend sign in required"
    }
}
