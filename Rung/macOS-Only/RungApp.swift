import SwiftUI
import SwiftData
import UserNotifications

@main
struct RungApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            ForegroundTracker.shared.startListening()
            #if DEBUG
            // Seed the MeetingsPill's demo events at launch instead of
            // only when CenterPanel appears, so the pill shows up
            // regardless of where the user lands first (auth, onboarding,
            // or dashboard).
            CalendarService.shared.loadDemoEventsIfEmpty()
            #endif
        }
    }

    private static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([Habit.self, HabitCompletion.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // First try a normal open; SwiftData handles lightweight migrations automatically.
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        // Migration failed (schema changed incompatibly). Delete the store and start fresh.
        // This only happens during development when the model changes without a migration plan.
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
                .frame(minWidth: 900, minHeight: 600)
                .task { WidgetSnapshotWriter.shared.start(container: Self.sharedModelContainer) }
        }
        .modelContainer(Self.sharedModelContainer)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up the delegate but don't request authorization at launch —
        // onboarding's permissions step owns the prompt so the user sees
        // *why* before being asked. Refresh the APNs device token here
        // for users who already granted in a prior run.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                NSApp.registerForRemoteNotifications()
            }
        }

        // Install the menu-bar focus timer. The status item stays hidden
        // until the user starts a focus session and self-removes when they
        // cancel — no menu-bar clutter for users who never use it.
        FocusStatusBarController.shared.install()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Activating the app counts as "user has seen the notifications" —
        // clear the dock badge and the delivered tray so the icon doesn't
        // accumulate stale counts.
        clearDeliveredNotifications()
    }

    // APNs sends the device token here after successful registration.
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Broadcast via NotificationCenter — ContentView picks this up and registers with the backend.
        NotificationCenter.default.post(name: .apnsTokenReceived, object: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected in Simulator, or when push entitlement isn't provisioned yet.
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }

    // Foreground remote notification (system calls this when app is open).
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

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notification banner even when the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User clicked a notification — treat as read: drop it from the tray
    /// and zero the badge so the dock doesn't keep showing stale counts.
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

/// Cross-platform helper for zeroing the app icon badge. macOS 13+ uses
/// `setBadgeCount` on the notification center; the dock tile label is
/// cleared explicitly as a backstop for older releases that ignore it.
enum BadgeReset {
    @MainActor
    static func clear() {
        if #available(macOS 13.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
        NSApp?.dockTile.badgeLabel = nil
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted with `object: Data` (the APNs device token bytes).
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    /// Posted with `object: String` (the nudge message body) for foreground handling.
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
