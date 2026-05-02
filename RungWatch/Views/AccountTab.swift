import SwiftUI

/// Tab 5 — Account / settings. Avatar, display name, @handle, then three
/// glass rows for Health sync, Notifications, and "iPhone app" (chevron only,
/// since the watch can't actually open the iPhone app — informational).
struct AccountTab: View {
    @EnvironmentObject private var session: WatchSession

    private var account: WatchSnapshot.AccountInfo { session.snapshot.account }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            avatarRow
            settingRows
        }
        .padding(.horizontal, 11)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    private var avatarRow: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(WatchTheme.brandGradient)
                Text(account.avatarInitial)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(account.displayName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                Text(account.handle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(WatchTheme.inkSoft)
            }
            Spacer()
        }
    }

    private var settingRows: some View {
        VStack(spacing: 3) {
            SettingRow(
                icon: "\u{2665}",   // ♥
                title: "Health sync",
                trailing: account.healthKitOn ? .onIndicator : .offIndicator
            )
            SettingRow(
                icon: "\u{1F514}",  // 🔔
                title: "Notifications",
                trailing: account.notificationsOn ? .onIndicator : .offIndicator
            )
            SettingRow(
                icon: "\u{1F4F1}",  // 📱
                title: "iPhone app",
                trailing: .chevron
            )
        }
    }
}

// MARK: - Row

private struct SettingRow: View {
    enum Trailing {
        case onIndicator
        case offIndicator
        case chevron
    }

    let icon: String
    let title: String
    let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(WatchTheme.ink)
            Spacer()
            trailingView
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .watchGlass()
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .onIndicator:
            Text("ON")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(WatchTheme.success)
        case .offIndicator:
            Text("OFF")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(WatchTheme.inkSoft)
        case .chevron:
            Text("\u{203A}")  // ›
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.inkSoft)
        }
    }
}

#Preview {
    AccountTab()
        .environmentObject(WatchSession.shared)
}
