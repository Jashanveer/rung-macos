import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let quote = "Success is the product of daily habits — not once-in-a-lifetime transformations."
private let quoteAttribution = "— James Clear"
private let bodyText = "The things you do every single day quietly compound into the person you become. Small, consistent habits are the architecture of an extraordinary life."

struct OnboardingView: View {
    let onComplete: ([String]) -> Void

    @State private var displayedQuote = ""
    @State private var quoteComplete = false
    @State private var bodyVisible = false
    @State private var inputVisible = false

    @State private var habitInput = ""
    @State private var stagedHabits: [String] = []
    @State private var isExiting = false
    @State private var pendingHabits: [String] = []
    @FocusState private var fieldFocused: Bool

    @State private var phase: OnboardingPhase = .inputHabits
    @State private var hasRequestedNotifications = false
    @State private var notificationsRequesting = false
    @State private var showVerificationHelp = false
    #if os(iOS)
    @State private var hasRequestedHealthKit = false
    @State private var healthKitRequesting = false
    @State private var hasRequestedScreenTime = false
    @State private var screenTimeRequesting = false
    #endif

    /// Two-step onboarding: first the user stages their habits, then (if any
    /// were staged) we bounce them to a permissions panel so HealthKit /
    /// Family Controls authorization happens before they land on the empty
    /// dashboard. Users who skip habits go straight through without the
    /// permissions step.
    private enum OnboardingPhase { case inputHabits, permissions }

    var body: some View {
        ZStack {
            MinimalBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    VStack(spacing: 40) {
                        quoteSection
                        bodySection
                        Group {
                            switch phase {
                            case .inputHabits: inputSection
                            case .permissions: permissionsSection
                            }
                        }
                        .transition(
                            .opacity.combined(with: .offset(y: 10))
                        )
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, compactHorizontalPadding)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, minHeight: 600)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

            if isExiting {
                RungTransition(
                    onCovered: { onComplete(pendingHabits) },
                    onComplete: {}
                )
                .transition(.opacity)
            }
        }
        .onAppear { startSequence() }
    }

    private var compactHorizontalPadding: CGFloat {
        #if os(iOS)
        24
        #else
        48
        #endif
    }

    private func beginExit() {
        guard !isExiting else { return }
        pendingHabits = stagedHabits
        fieldFocused = false
        withAnimation(.smooth(duration: 0.2)) {
            isExiting = true
        }
    }

    // MARK: - Sections

    private var quoteSection: some View {
        VStack(spacing: 14) {
            // Phantom full text reserves stable layout height from the start.
            // The visible typed text overlays it so the section never reflows.
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)
                .overlay(alignment: .top) {
                    Text("\u{201C}\(displayedQuote)\u{201D}")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(nil, value: displayedQuote)
                }

            Text(quoteAttribution)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .opacity(quoteComplete ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: quoteComplete)
        }
    }

    private var bodySection: some View {
        Text(bodyText)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(5)
            .opacity(bodyVisible ? 1 : 0)
            .offset(y: bodyVisible ? 0 : 10)
            .animation(.easeOut(duration: 0.6), value: bodyVisible)
    }

    private var inputSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("What habits do you want to build?")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("You can always add more later from the dashboard.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)

            permanenceNotice

            HStack(spacing: 8) {
                TextField("E.g. Morning run, read 10 pages...", text: $habitInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.leading, 16)
                    .focused($fieldFocused)
                    .autocorrectionDisabled(false)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .onSubmit(addHabit)

                if !habitInput.isEmpty {
                    Button(action: addHabit) {
                        Text("Add")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(CleanShotTheme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, habitInput.isEmpty ? 16 : 5)
            .frame(height: 46)
            .cleanShotSurface(shape: Capsule(), level: .control, isActive: fieldFocused)
            .animation(.easeOut(duration: 0.15), value: habitInput.isEmpty)
            .frame(maxWidth: 520)

            if !stagedHabits.isEmpty {
                VStack(spacing: 6) {
                    ForEach(stagedHabits, id: \.self) { habit in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CleanShotTheme.accent)
                                .font(.system(size: 15))
                            Text(habit)
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    stagedHabits.removeAll { $0 == habit }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(Color.primary.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .cleanShotSurface(
                            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                            level: .control
                        )
                        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: stagedHabits)
                .frame(maxWidth: 520)
            }

            Button(action: advanceFromInput) {
                Text(stagedHabits.isEmpty ? "Skip for now" : "Let's start →")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .frame(maxWidth: 520)
            .disabled(isExiting)
            .animation(.easeOut(duration: 0.15), value: stagedHabits.isEmpty)
        }
        .opacity(inputVisible ? 1 : 0)
        .offset(y: inputVisible ? 0 : 14)
        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: inputVisible)
    }

    // MARK: - Permissions step

    /// Shown after the user stages at least one habit — asks for the
    /// external-signal permissions Rung needs to back up verified
    /// completions. Skipping is always an option; missing permission
    /// just means future verifications silently fall back to self-report.
    private var permissionsSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Permissions")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("A few system permissions so reminders, verification, and the leaderboard can do their job.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            permissionRow(
                systemImage: "bell.badge.fill",
                tint: .orange,
                title: "Notifications",
                subtitle: "Daily reminders, mentor nudges, and friend updates.",
                granted: hasRequestedNotifications,
                busy: notificationsRequesting,
                action: requestNotifications
            )

            #if os(iOS)
            permissionRow(
                systemImage: "heart.text.square.fill",
                tint: .pink,
                title: "Apple Health",
                subtitle: "Auto-verify workouts, steps, mindful minutes, sleep, and more.",
                granted: hasRequestedHealthKit,
                busy: healthKitRequesting,
                action: requestHealthKit
            )

            permissionRow(
                systemImage: "hourglass",
                tint: .indigo,
                title: "Screen Time",
                subtitle: "Verify social-media limits via Family Controls.",
                granted: hasRequestedScreenTime,
                busy: screenTimeRequesting,
                action: requestScreenTime
            )
            #endif

            Button(action: beginExit) {
                Text("Continue →")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .frame(maxWidth: 520)
            .disabled(isExiting)

            Button(action: beginExit) {
                Text("Maybe later")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isExiting)

            Button {
                showVerificationHelp = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("How does verification work?")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(CleanShotTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .opacity(inputVisible ? 1 : 0)
        .offset(y: inputVisible ? 0 : 14)
        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: inputVisible)
        .sheet(isPresented: $showVerificationHelp) {
            VerificationHelpSheet()
        }
    }

    /// A single permission affordance — icon + copy + an action button that
    /// flips to "Asked" once the OS permission sheet has been shown. We
    /// deliberately do not surface the granted/denied outcome because
    /// HealthKit and Family Controls both hide it from third parties.
    private func permissionRow(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        granted: Bool,
        busy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else if granted {
                        Label("Asked", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("Enable")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(granted ? tint : .white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(granted ? tint.opacity(0.15) : CleanShotTheme.accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(busy || granted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
            level: .control
        )
        .frame(maxWidth: 520)
    }

    private func advanceFromInput() {
        // Always route through the permissions step — even users who
        // skipped staging habits benefit from notifications, and the
        // explicit prompts give system-level permissions context that
        // a launch-time auto-prompt can't provide.
        fieldFocused = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
            phase = .permissions
        }
    }

    #if os(iOS)
    private func requestHealthKit() {
        guard !hasRequestedHealthKit, !healthKitRequesting else { return }
        healthKitRequesting = true
        Task {
            try? await VerificationService.shared.requestAuthorization()
            await MainActor.run {
                hasRequestedHealthKit = true
                healthKitRequesting = false
            }
        }
    }
    #endif

    private func requestNotifications() {
        guard !hasRequestedNotifications, !notificationsRequesting else { return }
        notificationsRequesting = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run {
                if granted {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #elseif os(macOS)
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                hasRequestedNotifications = true
                notificationsRequesting = false
            }
        }
    }

    #if os(iOS)
    private func requestScreenTime() {
        guard !hasRequestedScreenTime, !screenTimeRequesting else { return }
        screenTimeRequesting = true
        Task {
            await ScreenTimeService.shared.requestAuthorization()
            await MainActor.run {
                hasRequestedScreenTime = true
                screenTimeRequesting = false
            }
        }
    }
    #endif

    // MARK: - Sequence

    private func startSequence() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await typeQuote()
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.6)) { bodyVisible = true }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { inputVisible = true }
            try? await Task.sleep(for: .milliseconds(200))
            fieldFocused = true
        }
    }

    private func typeQuote() async {
        for char in quote {
            guard !Task.isCancelled else { return }
            displayedQuote.append(char)
            try? await Task.sleep(for: .milliseconds(28))
        }
        withAnimation { quoteComplete = true }
    }

    private func addHabit() {
        let trimmed = habitInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Case-insensitive so "Run" and "run" don't both land on the list.
        let alreadyStaged = stagedHabits.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !alreadyStaged else {
            habitInput = ""
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            stagedHabits.append(trimmed)
        }
        habitInput = ""
    }

    private var permanenceNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CleanShotTheme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Habits are permanent")
                    .font(.system(size: 13, weight: .semibold))
                Text("Once you commit to a habit it stays on your list — no deleting later. Pick what you'll actually do.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanShotTheme.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CleanShotTheme.accent.opacity(0.22), lineWidth: 0.75)
        )
        .frame(maxWidth: 520)
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: { _ in })
}
