import SwiftUI
import SwiftData
import UserNotifications

@main
struct HabitTrackerMacosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Habit.self])
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

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer even after store reset: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                NSApp.registerForRemoteNotifications()
            }
        }
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
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted with `object: Data` (the APNs device token bytes).
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    /// Posted with `object: String` (the nudge message body) for foreground handling.
    static let apnsNudgeReceived = Notification.Name("apnsNudgeReceived")
}
