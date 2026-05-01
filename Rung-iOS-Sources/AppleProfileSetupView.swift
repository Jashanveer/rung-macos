import SwiftUI

/// Profile setup / edit screen — shown both immediately after a fresh
/// Sign in with Apple sign-up (when Apple's identity token only carries
/// the user's email + optional name on the very first auth) and again
/// from Settings when the user wants to rename their handle or pick a
/// new avatar.
///
/// Two presentation modes:
///   - **Setup** (default init): full-screen overlay above
///     `ContentViewScaffold` while `requiresProfileSetup == true`. On
///     submit the flag clears and the user falls through to onboarding.
///   - **Edit** (`initialUsername` / `initialAvatarURL` non-nil): pushed
///     as a sheet from `SettingsPanel`. Pre-fills the current values so
///     the user can keep their avatar and only rename, etc.
struct AppleProfileSetupView: View {
    @ObservedObject var backend: HabitBackendStore
    let onComplete: () -> Void
    let initialUsername: String?
    let initialAvatarURL: String?
    let initialDisplayName: String?
    let isEditing: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var displayName: String
    @State private var selectedAvatarID: String
    @State private var availability: AvailabilityState
    @State private var lastCheckedUsername: String = ""
    @State private var checkTask: Task<Void, Never>?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field { case displayName, username }

    /// Setup-mode initialiser used by the post-signup overlay.
    /// `prefilledDisplayName` carries whatever Apple's identity token
    /// returned in `fullName` on the very first authorization. Apple
    /// drops it on every subsequent sign-in, so this is empty for
    /// private-relay accounts after the first time — and the screen
    /// requires the user to type a name themselves.
    init(
        backend: HabitBackendStore,
        prefilledDisplayName: String? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.backend = backend
        self.onComplete = onComplete
        self.initialUsername = nil
        self.initialAvatarURL = nil
        self.initialDisplayName = prefilledDisplayName
        self.isEditing = false
        _username = State(initialValue: "")
        _displayName = State(initialValue: prefilledDisplayName ?? "")
        _selectedAvatarID = State(initialValue: AvatarChoice.options.randomElement()?.id ?? AvatarChoice.options[0].id)
        _availability = State(initialValue: .untouched)
    }

    /// Edit-mode initialiser used by SettingsPanel. Pre-fills both the
    /// username and the currently-selected avatar so a user who only
    /// wants to rename doesn't have to re-pick their character.
    init(
        backend: HabitBackendStore,
        initialUsername: String,
        initialAvatarURL: String?,
        initialDisplayName: String? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.backend = backend
        self.onComplete = onComplete
        self.initialUsername = initialUsername
        self.initialAvatarURL = initialAvatarURL
        self.initialDisplayName = initialDisplayName
        self.isEditing = true
        _username = State(initialValue: initialUsername)
        _displayName = State(initialValue: initialDisplayName ?? "")
        let matchedID = AvatarChoice.options.first { $0.url == initialAvatarURL }?.id
            ?? AvatarChoice.options.randomElement()?.id
            ?? AvatarChoice.options[0].id
        _selectedAvatarID = State(initialValue: matchedID)
        // The pre-filled username is by definition already this user's
        // own handle on the server, so seed availability as `.available`
        // — the backend treats unchanged-username as a no-op rename.
        _availability = State(initialValue: .available)
    }

    private enum AvailabilityState {
        case untouched
        case checking
        case available
        case taken
        case invalid
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespaces)
    }

    private var isUsernameFormatValid: Bool {
        let pattern = "^[A-Za-z0-9_]{3,30}$"
        return trimmedUsername.range(of: pattern, options: .regularExpression) != nil
    }

    private var isDisplayNameValid: Bool {
        let count = trimmedDisplayName.count
        return count >= 1 && count <= 50
    }

    private var canSubmit: Bool {
        isUsernameFormatValid
            && isDisplayNameValid
            && availability == .available
            && !isSubmitting
    }

    private var selectedAvatar: AvatarChoice {
        AvatarChoice.options.first { $0.id == selectedAvatarID } ?? AvatarChoice.options[0]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MinimalBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: isEditing ? 24 : 60)

                    header

                    avatarPreview

                    displayNameField

                    usernameField

                    avatarGrid

                    continueButton

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            // In edit mode the screen is a sheet — give the user an
            // unambiguous way out. The setup-mode flow is gated by
            // requiresProfileSetup so we deliberately omit it there.
            if isEditing {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            // In setup mode, focus the name field first when it's
            // empty — that's the case Apple didn't return fullName
            // (every sign-in after the first one for private-relay
            // accounts), so getting the name is the new requirement.
            // Otherwise jump straight to username.
            if isEditing {
                focusedField = nil
            } else if trimmedDisplayName.isEmpty {
                focusedField = .displayName
            } else {
                focusedField = .username
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: isEditing ? "pencil.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(CleanShotTheme.accent)

            Text(isEditing ? "Edit your profile." : "Welcome to Rung.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(isEditing
                 ? "Update your username or character — these show up on the leaderboard and in friend feeds."
                 : "Pick a username and a character — these show up on the leaderboard.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var avatarPreview: some View {
        VStack(spacing: 10) {
            AsyncImage(url: URL(string: selectedAvatar.url)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 120, height: 120)
            .background(
                Circle().fill(CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                Circle().strokeBorder(CleanShotTheme.accent.opacity(0.45), lineWidth: 2)
            )
            .clipShape(Circle())
            Text(trimmedUsername.isEmpty ? "your name here" : "@\(trimmedUsername.lowercased())")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trimmedUsername.isEmpty ? .tertiary : .primary)
                .animation(.smooth(duration: 0.18), value: trimmedUsername)
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR NAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)

            TextField("e.g. Jashan", text: $displayName)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($focusedField, equals: .displayName)
                .onSubmit { focusedField = .username }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 1)
                )

            Text(displayNameHelperText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var displayNameHelperText: String {
        if let initial = initialDisplayName, !initial.isEmpty, isEditing == false {
            return "Apple shared this — change it if you want."
        }
        return "Shown on your habit cards and to friends. Up to 50 characters."
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USERNAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)

            HStack(spacing: 10) {
                Text("@")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. jashan", text: $username)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($focusedField, equals: .username)
                    .autocorrectionDisabled(true)
                    .onSubmit(submit)
                    .onChange(of: username) { _, _ in
                        scheduleAvailabilityCheck()
                    }
                availabilityBadge
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            Text(helperText)
                .font(.system(size: 12))
                .foregroundStyle(helperColor)
                .animation(.smooth(duration: 0.16), value: availability)
                .animation(.smooth(duration: 0.16), value: isUsernameFormatValid)
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .transition(.scale.combined(with: .opacity))
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CleanShotTheme.danger)
                .transition(.scale.combined(with: .opacity))
        case .untouched:
            EmptyView()
        }
    }

    private var avatarGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHARACTER")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(AvatarChoice.options) { avatar in
                    AvatarChoiceButton(
                        avatar: avatar,
                        isSelected: avatar.id == selectedAvatarID,
                        action: { selectedAvatarID = avatar.id }
                    )
                }
            }
        }
    }

    private var continueButton: some View {
        VStack(spacing: 10) {
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(isEditing ? "Save changes" : "Continue →")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.6)
            .animation(.smooth(duration: 0.16), value: canSubmit)

            if let err = backend.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(CleanShotTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch availability {
        case .available: return Color.green.opacity(0.7)
        case .taken, .invalid: return CleanShotTheme.danger.opacity(0.7)
        case .checking, .untouched: return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)
        }
    }

    private var helperColor: Color {
        switch availability {
        case .available: return Color.green
        case .taken, .invalid: return CleanShotTheme.danger
        default: return .secondary
        }
    }

    private var helperText: String {
        if !isUsernameFormatValid && !trimmedUsername.isEmpty {
            return "Use 3-30 letters, numbers, or underscores."
        }
        switch availability {
        case .checking:    return "Checking availability…"
        case .available:   return "@\(trimmedUsername.lowercased()) is available."
        case .taken:       return "Sorry, that's taken — try another."
        case .invalid:     return "Use 3-30 letters, numbers, or underscores."
        case .untouched:   return "Letters, numbers, or underscores. 3-30 characters."
        }
    }

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        backend.errorMessage = nil
        guard !trimmedUsername.isEmpty else {
            availability = .untouched
            return
        }
        guard isUsernameFormatValid else {
            availability = .invalid
            return
        }
        availability = .checking
        let candidate = trimmedUsername
        checkTask = Task {
            // Debounce — let typing settle before hitting the network.
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let available = await backend.isUsernameAvailable(candidate)
            if Task.isCancelled { return }
            await MainActor.run {
                guard candidate == trimmedUsername else { return }
                availability = available ? .available : .taken
                lastCheckedUsername = candidate
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let chosenUsername = trimmedUsername
        let chosenAvatar = selectedAvatar.url
        let chosenDisplayName = trimmedDisplayName
        Task {
            let success = await backend.setupAppleProfile(
                username: chosenUsername,
                avatarURL: chosenAvatar,
                displayName: chosenDisplayName.isEmpty ? nil : chosenDisplayName
            )
            await MainActor.run {
                isSubmitting = false
                if success {
                    onComplete()
                } else {
                    // Backend returned a 4xx (likely "username taken" if
                    // someone grabbed it between availability check and
                    // submit). Reset the badge so the inline copy
                    // matches.
                    availability = .taken
                }
            }
        }
    }
}
