import SwiftUI
import SwiftData
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct RungApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    /// Single shared container — created once at static-init time so both
    /// the SwiftUI scene's `.modelContainer` modifier AND the auto-verifier
    /// bootstrap (called from `init` below) reference the exact same store.
    private static let sharedModelContainer: ModelContainer = makeSharedContainer()

    init() {
        // Bootstrap the auto-verification coordinator with the shared
        // model container so HKObserverQuery wake-ups + background
        // delivery work even when the OS launches the app into the
        // background to deliver a new HealthKit sample. App.init runs on
        // the main actor in SwiftUI; assumeIsolated documents that.
        MainActor.assumeIsolated {
            AutoVerificationCoordinator.shared.bootstrap(container: Self.sharedModelContainer)
        }
    }

    private static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([Habit.self, HabitCompletion.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        let storeURL = config.url
        let fm = FileManager.default
        for url in [storeURL,
                    storeURL.appendingPathExtension("shm"),
                    storeURL.appendingPathExtension("wal")] {
            try? fm.removeItem(at: url)
        }

        if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
            return recovered
        }

        // Last resort: fall back to an in-memory container so the app still
        // launches (read-only-ish behaviour, server reconcile re-populates
        // habits on next sync). Crashing here would brick every user with
        // a corrupt sandbox; an empty session lets them sign in and recover.
        print("[RungApp] WARNING: SwiftData container failed; using in-memory fallback.")
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let memContainer = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
            return memContainer
        }
        // If even the in-memory path fails, the runtime is broken — there's
        // nothing the user can do. fatalError is honest at this point.
        fatalError("ModelContainer could not be created with on-disk OR in-memory storage.")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
                .task { WidgetSnapshotWriter.shared.start(container: Self.sharedModelContainer) }
        }
        .modelContainer(Self.sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}

// MARK: - App Delegate

#if os(iOS)

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire up the delegate but don't request authorization at launch —
        // that fires the system prompt before onboarding has a chance to
        // explain *why* we want notifications. Onboarding's permissions
        // step now drives the request and follows up with
        // `registerForRemoteNotifications()` if the user grants.
        UNUserNotificationCenter.current().delegate = self
        // For already-onboarded users who previously granted notifications,
        // ask the system to refresh the APNs device token on every launch
        // so a re-installed backend keeps receiving pushes.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Treat foregrounding the app as "user has seen the notifications".
        // Clear delivered notifications and zero the badge so the icon
        // matches reality instead of accumulating forever.
        clearDeliveredNotifications()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(name: .apnsTokenReceived, object: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }

    // Rung is landscape-only on iPad, portrait-only on iPhone. This enforces
    // the Info.plist settings at runtime so third-party rotation events are
    // also refused.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .landscape
        }
        return .portrait
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if
            let aps = userInfo["aps"] as? [String: Any],
            let alert = aps["alert"] as? [String: Any],
            let body = alert["body"] as? String
        {
            NotificationCenter.default.post(name: .apnsNudgeReceived, object: body)
        }
        completionHandler(.newData)
    }
}

#elseif os(macOS)

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up the delegate but don't request authorization at launch —
        // onboarding's permissions step owns the prompt so the user sees
        // *why* before being asked. Refresh the APNs device token here
        // for users who already granted in a prior run.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                NSApp.registerForRemoteNotifications()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Activating the app counts as "user has seen the notifications" —
        // clear the dock badge and the delivered tray so the icon doesn't
        // accumulate stale counts.
        clearDeliveredNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .apnsTokenReceived, object: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        if
            let aps = userInfo["aps"] as? [String: Any],
            let alert = aps["alert"] as? [String: Any],
            let body = alert["body"] as? String
        {
            NotificationCenter.default.post(name: .apnsNudgeReceived, object: body)
        }
    }
}

#endif

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User tapped a notification — treat as read: drop it from the tray
    /// and zero the badge so the icon doesn't keep showing stale counts.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        Task { @MainActor in
            BadgeReset.clear()
        }
        completionHandler()
    }

    fileprivate func clearDeliveredNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        Task { @MainActor in
            BadgeReset.clear()
        }
    }
}

/// Cross-platform helper for zeroing the app icon badge. iOS 16+ uses
/// `setBadgeCount` on the notification center; macOS clears the dock tile
/// label directly. Falls back to the deprecated `applicationIconBadgeNumber`
/// path on older iOS so older devices still get reset.
enum BadgeReset {
    @MainActor
    static func clear() {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
        NSApp?.dockTile.badgeLabel = nil
        #endif
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    static let apnsNudgeReceived = Notification.Name("apnsNudgeReceived")
    /// Fired when the per-user SSE stream reports another device just
    /// wrote a habit — ContentView reacts by triggering syncWithBackend
    /// so the change lands within seconds instead of on the next timer.
    static let habitsChangedSSE = Notification.Name("habitsChangedSSE")
    /// Fired when the backend hard-deletes the current user's account
    /// (locally via the deleteAccount API call, or remotely via the
    /// `session.revoked` SSE event broadcast to all of the user's
    /// connected devices). ContentView observes this to wipe local
    /// SwiftData habits + completion records so a subsequent sign-in
    /// can never resurrect ghost data from the previous account.
    static let rungAccountDeleted = Notification.Name("rungAccountDeleted")
}
