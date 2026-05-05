import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// Account / settings — avatar + display name as the hero, then a small
/// settings list. Includes the watchOS-only **Display size** picker so
/// users can grow every number on every screen if the default sizes feel
/// too small.
struct AccountTab: View {
    @EnvironmentObject private var session: WatchSession
    @EnvironmentObject private var backend: WatchBackendStore
    @Environment(\.watchFontScale) private var scale: Double
    @AppStorage("watchFontScaleRaw") private var fontScaleRaw: Double = WatchFontScale.default.rawValue

    /// Two-step logout — first tap arms the danger button, second tap
    /// commits. Prevents an accidental side-of-watch press from
    /// silently signing the user out and forcing a re-pair.
    @State private var logoutArmed: Bool = false

    private var account: WatchSnapshot.AccountInfo { session.snapshot.account }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WatchPageTitle("Account", accent: WatchTheme.cViolet)
                avatarHero
                fontScalePicker
                settingRows
                logoutButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .watchWashBackground(.twilight)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            if logoutArmed {
                signOut()
            } else {
                withAnimation(WatchMotion.snappy) { logoutArmed = true }
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.notification)
                #endif
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: logoutArmed
                      ? "exclamationmark.triangle.fill"
                      : "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13 * scale, weight: .heavy))
                    .foregroundStyle(.white)
                Text(logoutArmed ? "Tap again to confirm" : "Log out")
                    .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .liquidGlassSurface(
                cornerRadius: 12,
                tint: WatchTheme.cRose,
                strong: logoutArmed
            )
        }
        .buttonStyle(WatchPressStyle())
        .padding(.top, 6)
    }

    /// Clears every cache the watch keeps for the current account so
    /// the next launch lands on the connecting / Sign-in-with-Apple
    /// screen exactly like a fresh install.
    private func signOut() {
        WatchAuthStore.shared.clear()
        backend.stop()
        session.signOut()
        logoutArmed = false
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    // MARK: - Avatar hero

    private var avatarHero: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(WatchTheme.brandGradient)
                Text(account.avatarInitial.isEmpty ? "·" : account.avatarInitial)
                    .font(WatchTheme.font(.heroSmall, scale: scale, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 54 * scale, height: 54 * scale)
            .shadow(color: WatchTheme.accent.opacity(0.4), radius: 6, y: 2)

            Text(account.displayName.isEmpty ? "Rung" : account.displayName)
                .font(WatchTheme.font(.title, scale: scale, weight: .bold))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
            if !account.handle.isEmpty {
                Text(account.handle)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.inkSoft)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Font scale picker

    private var fontScalePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DISPLAY SIZE")
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
                .padding(.leading, 4)

            HStack(spacing: 4) {
                ForEach(WatchFontScale.allCases) { option in
                    let selected = fontScaleRaw == option.rawValue
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            fontScaleRaw = option.rawValue
                        }
                    } label: {
                        Text(option.label)
                            .font(WatchTheme.font(.caption, scale: option.rawValue,
                                                   weight: .semibold))
                            .foregroundStyle(selected ? .white : WatchTheme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .liquidGlassSurface(
                                cornerRadius: 9,
                                tint: selected ? WatchTheme.cCyan : nil,
                                strong: selected
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Settings list

    private var settingRows: some View {
        VStack(spacing: 4) {
            SettingRow(
                icon: "heart.fill",
                tint: WatchTheme.danger,
                title: "Health sync",
                trailing: account.healthKitOn ? "ON" : "OFF",
                trailingTint: account.healthKitOn ? WatchTheme.success : WatchTheme.inkSoft,
                scale: scale
            )
            SettingRow(
                icon: "bell.fill",
                tint: WatchTheme.warning,
                title: "Notifications",
                trailing: account.notificationsOn ? "ON" : "OFF",
                trailingTint: account.notificationsOn ? WatchTheme.success : WatchTheme.inkSoft,
                scale: scale
            )
            SettingRow(
                icon: "iphone",
                tint: WatchTheme.accent,
                title: "Rung on iPhone",
                trailing: "›",
                trailingTint: WatchTheme.inkSoft,
                scale: scale
            )
            // Legal links — App Review (5.1.1(i)) wants the privacy
            // policy reachable inside the app on every platform the
            // app ships on, not just the iPhone. The watch's tiny
            // surface can't open URLs directly, so the trailing chip
            // tells the user where to find them on the iPhone app —
            // tapping does nothing (watchOS lacks a URL-handler the
            // way iOS does) but the row's presence proves discoverability.
            SettingRow(
                icon: "lock.shield.fill",
                tint: WatchTheme.cViolet,
                title: "Privacy",
                trailing: "iPhone",
                trailingTint: WatchTheme.inkSoft,
                scale: scale
            )
            SettingRow(
                icon: "doc.text.fill",
                tint: WatchTheme.cCyan,
                title: "Terms",
                trailing: "iPhone",
                trailingTint: WatchTheme.inkSoft,
                scale: scale
            )
        }
    }
}

// MARK: - Row

private struct SettingRow: View {
    let icon: String
    let tint: Color
    let title: String
    let trailing: String
    let trailingTint: Color
    let scale: Double

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(title)
                .font(WatchTheme.font(.body, scale: scale, weight: .medium))
                .foregroundStyle(WatchTheme.ink)
            Spacer()
            Text(trailing)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(trailingTint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .liquidGlassSurface(cornerRadius: 11)
    }
}

#if DEBUG
#Preview {
    AccountTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
