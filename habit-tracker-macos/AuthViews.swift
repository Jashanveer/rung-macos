import SwiftUI

struct HabitChipView: View {
    let label: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            Capsule()
                .fill(colorScheme == .dark ? color.opacity(0.14) : color.opacity(0.10))
                .overlay {
                    Capsule()
                        .strokeBorder(colorScheme == .dark ? color.opacity(0.30) : color.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

struct FloatingHabitBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct HabitItem {
        let label: String
        let icon: String
        let color: Color
        let x: CGFloat     // normalized 0…1
        let y: CGFloat     // normalized 0…1
        let scale: CGFloat
        let opacity: Double
        let phaseOffset: Double
        let amplitude: CGFloat
    }

    private let items: [HabitItem] = [
        // Row 1 — top strip
        .init(label: "Running",       icon: "figure.run",           color: .blue,   x: 0.06, y: 0.10, scale: 1.10, opacity: 0.55, phaseOffset: 0.0,  amplitude: 9),
        .init(label: "Yoga",          icon: "figure.yoga",          color: .teal,   x: 0.28, y: 0.07, scale: 1.00, opacity: 0.48, phaseOffset: 3.0,  amplitude: 6),
        .init(label: "Meditation",    icon: "brain.head.profile",   color: .purple, x: 0.54, y: 0.10, scale: 1.15, opacity: 0.50, phaseOffset: 1.2,  amplitude: 11),
        .init(label: "Walking",       icon: "figure.walk",          color: .teal,   x: 0.76, y: 0.07, scale: 1.00, opacity: 0.55, phaseOffset: 4.5,  amplitude: 9),
        .init(label: "Sleep",         icon: "moon.zzz",             color: .indigo, x: 0.94, y: 0.11, scale: 1.05, opacity: 0.50, phaseOffset: 4.0,  amplitude: 8),
        // Row 2
        .init(label: "Reading",       icon: "book",                 color: .orange, x: 0.04, y: 0.26, scale: 1.00, opacity: 0.60, phaseOffset: 2.1,  amplitude: 7),
        .init(label: "Music",         icon: "music.note",           color: .pink,   x: 0.22, y: 0.23, scale: 1.00, opacity: 0.48, phaseOffset: 1.5,  amplitude: 10),
        .init(label: "Journaling",    icon: "pencil",               color: Color(red: 0.94, green: 0.74, blue: 0.24), x: 0.46, y: 0.26, scale: 1.00, opacity: 0.50, phaseOffset: 1.8, amplitude: 10),
        .init(label: "Stretching",    icon: "figure.flexibility",   color: .pink,   x: 0.70, y: 0.23, scale: 0.95, opacity: 0.50, phaseOffset: 5.0,  amplitude: 7),
        .init(label: "Cycling",       icon: "bicycle",              color: .green,  x: 0.90, y: 0.27, scale: 1.10, opacity: 0.45, phaseOffset: 0.3,  amplitude: 9),
        // Row 3 — middle
        .init(label: "Cold Shower",   icon: "snowflake",            color: .cyan,   x: 0.04, y: 0.44, scale: 0.95, opacity: 0.45, phaseOffset: 6.2,  amplitude: 8),
        .init(label: "Drawing",       icon: "paintbrush",           color: .purple, x: 0.25, y: 0.42, scale: 1.10, opacity: 0.42, phaseOffset: 6.0,  amplitude: 8),
        .init(label: "Vitamins",      icon: "pill",                 color: Color(red: 0.46, green: 0.48, blue: 0.84), x: 0.50, y: 0.45, scale: 0.98, opacity: 0.40, phaseOffset: 5.5, amplitude: 6),
        .init(label: "Cooking",       icon: "fork.knife",           color: .green,  x: 0.74, y: 0.42, scale: 1.10, opacity: 0.55, phaseOffset: 0.7,  amplitude: 9),
        .init(label: "Gratitude",     icon: "heart",                color: .red,    x: 0.94, y: 0.44, scale: 1.05, opacity: 0.50, phaseOffset: 3.5,  amplitude: 8),
        // Row 4
        .init(label: "Study",         icon: "graduationcap",        color: .orange, x: 0.06, y: 0.62, scale: 1.00, opacity: 0.48, phaseOffset: 2.8,  amplitude: 7),
        .init(label: "Hydration",     icon: "drop",                 color: .cyan,   x: 0.26, y: 0.60, scale: 1.00, opacity: 0.55, phaseOffset: 2.5,  amplitude: 7),
        .init(label: "Photography",   icon: "camera",               color: .blue,   x: 0.50, y: 0.63, scale: 0.95, opacity: 0.45, phaseOffset: 3.8,  amplitude: 8),
        .init(label: "Journaling",    icon: "doc.text",             color: Color(red: 0.94, green: 0.74, blue: 0.24), x: 0.73, y: 0.60, scale: 1.00, opacity: 0.42, phaseOffset: 7.0, amplitude: 9),
        .init(label: "Mindfulness",   icon: "sparkles",             color: .purple, x: 0.93, y: 0.62, scale: 1.05, opacity: 0.45, phaseOffset: 2.2,  amplitude: 10),
        // Row 5 — bottom strip
        .init(label: "Strength",      icon: "dumbbell",             color: .red,    x: 0.08, y: 0.80, scale: 1.05, opacity: 0.50, phaseOffset: 0.9,  amplitude: 8),
        .init(label: "Language",      icon: "character.bubble",     color: .green,  x: 0.28, y: 0.83, scale: 0.95, opacity: 0.45, phaseOffset: 4.8,  amplitude: 7),
        .init(label: "Cycling",       icon: "bicycle",              color: .teal,   x: 0.52, y: 0.80, scale: 1.10, opacity: 0.48, phaseOffset: 1.1,  amplitude: 9),
        .init(label: "Breathing",     icon: "wind",                 color: .indigo, x: 0.74, y: 0.84, scale: 1.00, opacity: 0.45, phaseOffset: 5.7,  amplitude: 7),
        .init(label: "Sleep Diary",   icon: "bed.double",           color: .blue,   x: 0.93, y: 0.80, scale: 0.95, opacity: 0.50, phaseOffset: 3.3,  amplitude: 8),
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    if colorScheme == .dark {
                        Color.black
                    } else {
                        Color.white
                    }

                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
                        let yOffset = sin(t * 0.55 + item.phaseOffset) * item.amplitude
                        let xOffset = cos(t * 0.38 + item.phaseOffset) * (item.amplitude * 0.45)

                        HabitChipView(label: item.label, icon: item.icon, color: item.color)
                            .scaleEffect(item.scale)
                            .opacity(item.opacity)
                            .offset(x: xOffset, y: yOffset)
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
}

// MARK: - Auth Gate

struct AuthGateView: View {
    @ObservedObject var backend: HabitBackendStore
    let onAuthenticated: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: AuthMode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var selectedAvatarID = AvatarChoice.options[0].id
    @State private var validationMessage: String?

    var body: some View {
        ZStack {
            FloatingHabitBackground()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(mode.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                HStack(spacing: 6) {
                    AuthModeButton(title: "Sign in", isSelected: mode == .signIn) {
                        switchMode(.signIn)
                    }
                    AuthModeButton(title: "Sign up", isSelected: mode == .signUp) {
                        switchMode(.signUp)
                    }
                }
                .frame(width: 340)
                .padding(4)
                .cleanShotSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), level: .control)

                VStack(spacing: 12) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .cleanShotSurface(shape: Capsule(), level: .control)
                        .onSubmit {
                            submit()
                        }

                    if mode == .signUp {
                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .cleanShotSurface(shape: Capsule(), level: .control)
                            .onSubmit {
                                submit()
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .cleanShotSurface(shape: Capsule(), level: .control)
                        .onSubmit {
                            submit()
                        }

                    if mode == .signUp {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose an avatar")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 10), count: 5), spacing: 10) {
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let message = validationMessage ?? backend.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button {
                            submit()
                        } label: {
                            HStack(spacing: 8) {
                                if backend.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text(mode.primaryActionTitle)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .buttonStyle(PrimaryCapsuleButtonStyle())

                        Button {
                            switchMode(mode == .signIn ? .signUp : .signIn)
                        } label: {
                            Text(mode.secondaryActionTitle)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                        }
                        .buttonStyle(SecondaryCapsuleButtonStyle())
                    }
                    .disabled(backend.isSyncing)
                }
                .frame(width: 400)
            }
            .padding(28)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                level: .elevated,
                shadowRadius: 18
            )
        }
    }

    private enum AuthMode {
        case signIn
        case signUp

        var title: String {
            switch self {
            case .signIn:
                return "Welcome back"
            case .signUp:
                return "Create your profile"
            }
        }

        var subtitle: String {
            switch self {
            case .signIn:
                return "Use your username to sync with localhost:8080."
            case .signUp:
                return "Pick a username and a character for your habit profile."
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .signIn:
                return "Sign in"
            case .signUp:
                return "Create account"
            }
        }

        var secondaryActionTitle: String {
            switch self {
            case .signIn:
                return "Create account"
            case .signUp:
                return "I have an account"
            }
        }
    }

    private var selectedAvatar: AvatarChoice {
        AvatarChoice.options.first { $0.id == selectedAvatarID } ?? AvatarChoice.options[0]
    }

    private func switchMode(_ nextMode: AuthMode) {
        withAnimation(.smooth(duration: 0.2)) {
            mode = nextMode
            validationMessage = nil
            backend.errorMessage = nil
        }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
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

        Task {
            switch mode {
            case .signIn:
                await backend.signIn(username: trimmedUsername, password: password)
            case .signUp:
                await backend.register(
                    username: trimmedUsername,
                    email: trimmedEmail,
                    password: password,
                    avatarURL: selectedAvatar.url
                )
            }

            if backend.isAuthenticated {
                onAuthenticated()
            }
        }
    }

    private func isValidUsername(_ value: String) -> Bool {
        guard (3...30).contains(value.count) else { return false }
        return value.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
    }
}

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

struct AuthModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CleanShotTheme.accent)
                    }
                }
        }
        .buttonStyle(.plain)
    }
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
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(avatar.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54, height: 64)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? CleanShotTheme.accent.opacity(0.16) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? CleanShotTheme.accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

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

        return backend.isAuthenticated ? (backend.statusMessage ?? "Connected to localhost:8080") : "Backend sign in required"
    }
}

