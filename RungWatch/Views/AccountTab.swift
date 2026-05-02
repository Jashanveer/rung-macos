import SwiftUI

/// Account / settings — avatar + display name as the hero, then a small
/// settings list. Includes the watchOS-only **Display size** picker so
/// users can grow every number on every screen if the default sizes feel
/// too small.
struct AccountTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double
    @AppStorage("watchFontScaleRaw") private var fontScaleRaw: Double = WatchFontScale.default.rawValue

    private var account: WatchSnapshot.AccountInfo { session.snapshot.account }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                avatarHero
                fontScalePicker
                settingRows
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
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
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            fontScaleRaw = option.rawValue
                        }
                    } label: {
                        Text(option.label)
                            .font(WatchTheme.font(.caption, scale: option.rawValue,
                                                   weight: .semibold))
                            .foregroundStyle(fontScaleRaw == option.rawValue
                                              ? .white : WatchTheme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(fontScaleRaw == option.rawValue
                                          ? AnyShapeStyle(WatchTheme.brandGradient)
                                          : AnyShapeStyle(Color.white.opacity(0.07)))
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
                title: "iPhone app",
                trailing: "›",
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
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.06),
                                              Color.white.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

#if DEBUG
#Preview {
    AccountTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
