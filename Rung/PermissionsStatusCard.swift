import Combine
import EventKit
import SwiftUI
import UserNotifications

#if os(iOS)
import HealthKit
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Surfaces every system permission Rung relies on so users who skipped
/// (or denied) onboarding prompts can grant them later. Each row knows
/// whether it's already been granted; pending rows route the user into
/// system Settings on tap. The whole card hides itself when every
/// relevant permission is satisfied so a fully-onboarded account never
/// sees it.
///
/// Platform split:
/// - iOS shows Notifications + Apple Health + Calendar.
/// - macOS shows Notifications + Calendar (HealthKit on Mac rarely has data).
struct PermissionsStatusCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var state = PermissionsState()

    var body: some View {
        Group {
            if state.pending.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    VStack(spacing: 6) {
                        ForEach(state.pending) { permission in
                            row(for: permission)
                        }
                    }
                }
                .padding(14)
                .cleanShotSurface(
                    shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    level: .control
                )
            }
        }
        .task { await state.refresh() }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.pending)
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
            Text("Permissions to grant")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Text("\(state.pending.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(for permission: PermissionEntry) -> some View {
        Button {
            Task { await state.handleTap(permission) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(permission.tint)
                    .frame(width: 28, height: 28)
                    .background(
                        permission.tint.opacity(colorScheme == .dark ? 0.18 : 0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(permission.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.025))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(permission.title) — \(permission.subtitle). Tap to open Settings.")
    }
}

// MARK: - State

/// Identifies the permission a row represents. Keeps the view dumb — all
/// behaviour decisions live on `PermissionsState`.
enum PermissionKind: String, CaseIterable, Identifiable {
    case notifications
    case calendar
    #if os(iOS)
    case healthKit
    #endif

    var id: String { rawValue }
}

struct PermissionEntry: Identifiable, Equatable {
    let kind: PermissionKind
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var id: String { kind.id }
}

@MainActor
final class PermissionsState: ObservableObject {
    @Published private(set) var pending: [PermissionEntry] = []

    /// Re-pull every permission status. Cheap — three system queries — so
    /// safe to call on view appear and after `handleTap`.
    func refresh() async {
        var entries: [PermissionEntry] = []

        if await !isNotificationsGranted() {
            entries.append(PermissionEntry(
                kind: .notifications,
                title: "Notifications",
                subtitle: "Rung needs this to send streak warnings, mentor nudges, and habit reminders.",
                systemImage: "bell.badge.fill",
                tint: .orange
            ))
        }

        if !isCalendarGranted() {
            entries.append(PermissionEntry(
                kind: .calendar,
                title: "Calendar",
                subtitle: "Lets Rung suggest a streak freeze on busy days and surface meeting-related tasks.",
                systemImage: "calendar",
                tint: .blue
            ))
        }

        #if os(iOS)
        if !isHealthKitConnected() {
            entries.append(PermissionEntry(
                kind: .healthKit,
                title: "Apple Health",
                subtitle: "Auto-verifies workouts, mindful minutes, sleep, and other quantifiable habits.",
                systemImage: "heart.text.square.fill",
                tint: .pink
            ))
        }
        #endif

        pending = entries
    }

    /// Tapping a row tries the in-app prompt first (only effective when
    /// status is `.notDetermined`); if the user previously denied, it
    /// kicks them out to system Settings where the toggle actually lives.
    func handleTap(_ permission: PermissionEntry) async {
        switch permission.kind {
        case .notifications:
            await requestOrOpenNotifications()
        case .calendar:
            await requestOrOpenCalendar()
        #if os(iOS)
        case .healthKit:
            await requestOrOpenHealthKit()
        #endif
        }
        await refresh()
    }

    // MARK: - Notifications

    private func isNotificationsGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    private func requestOrOpenNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            return
        }
        // Already asked once and denied — only Settings can fix it.
        openSystemSettings(targeting: .notifications)
    }

    // MARK: - Calendar

    private func isCalendarGranted() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == EKAuthorizationStatus.authorized.rawValue
    }

    private func requestOrOpenCalendar() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            await CalendarService.shared.requestAccess()
            return
        }
        openSystemSettings(targeting: .calendar)
    }

    // MARK: - HealthKit (iOS)

    #if os(iOS)
    /// HealthKit deliberately hides read-authorization status to prevent
    /// fingerprinting, so we use a UserDefaults breadcrumb that
    /// VerificationService stamps the first time the prompt is presented.
    /// If the breadcrumb is missing, treat the user as "never asked".
    private static let healthKitAskedKey = "PermissionsStatusCard.healthKitAsked.v1"

    private func isHealthKitConnected() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return true }  // hide the row if HK is missing
        return UserDefaults.standard.bool(forKey: Self.healthKitAskedKey)
    }

    private func requestOrOpenHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !UserDefaults.standard.bool(forKey: Self.healthKitAskedKey) {
            try? await VerificationService.shared.requestAuthorization()
            UserDefaults.standard.set(true, forKey: Self.healthKitAskedKey)
            return
        }
        // Already asked at least once. Apple Health permissions live inside
        // the Health app, not Settings → Rung. Open Settings.app as the
        // best general fallback.
        openSystemSettings(targeting: .health)
    }
    #endif

    // MARK: - System Settings deep links

    private enum SettingsTarget {
        case notifications
        case calendar
        case health
    }

    private func openSystemSettings(targeting: SettingsTarget) {
        #if os(iOS)
        // iOS only exposes a single per-app Settings URL — the OS routes
        // the user to the right toggle based on the entitlement. Deep
        // links into specific privacy panes are private API.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
        #elseif os(macOS)
        let urlString: String
        switch targeting {
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        case .calendar:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .health:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
