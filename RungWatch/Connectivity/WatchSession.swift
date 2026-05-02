import Foundation
import WatchConnectivity
import Combine

/// Owns the `WCSession` lifecycle on the Watch side. Receives `WatchSnapshot`
/// payloads from the iPhone via `updateApplicationContext` and exposes them
/// through an `@Published` property so SwiftUI views update automatically.
///
/// All work happens on the main actor — Watch screens are tiny, the snapshot
/// is small, and `WCSessionDelegate` callbacks come on a background queue
/// that we hop off immediately.
@MainActor
final class WatchSession: NSObject, ObservableObject {

    static let shared = WatchSession()

    /// Latest snapshot the iPhone pushed. Starts at the placeholder so the
    /// UI has something to render before the first message arrives.
    @Published private(set) var snapshot: WatchSnapshot = .placeholder()

    /// `true` once we've received at least one real snapshot from the phone.
    /// UI uses this to dim "stale" placeholder data so users know the phone
    /// hasn't connected yet.
    @Published private(set) var hasReceivedRealData: Bool = false

    /// `true` while WCSession is activated and the phone is reachable for
    /// `sendMessage`. We don't hard-block sends on this — application context
    /// queues automatically when the phone is asleep.
    @Published private(set) var isReachable: Bool = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Outbound messages

    /// Tell the iPhone to log a +N count delta against a manual habit.
    /// Used by `HabitDetailView` when the user rotates the crown.
    func logHabit(id: String, delta: Int) {
        send([
            WatchMessageKey.action: WatchMessageAction.logHabit,
            WatchMessageKey.habitId: id,
            WatchMessageKey.delta: delta
        ])
    }

    /// Tell the iPhone to flip a binary habit's done-state for today.
    func toggleHabit(id: String) {
        send([
            WatchMessageKey.action: WatchMessageAction.toggleHabit,
            WatchMessageKey.habitId: id
        ])
    }

    /// Ask the iPhone to push a fresh snapshot — used on first launch so the
    /// Watch isn't stuck on `placeholder()` until the user does something on
    /// the phone.
    func requestSnapshot() {
        send([WatchMessageKey.action: WatchMessageAction.requestSnapshot])
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            // Live phone: best-effort. We don't block the UI on the reply —
            // the iPhone re-broadcasts a fresh snapshot via application
            // context after applying the change.
            session.sendMessage(payload, replyHandler: nil) { _ in }
        } else {
            // Phone asleep / unreachable: queue via transferUserInfo so the
            // change isn't dropped. iPhone delivers it on next wake.
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Snapshot ingestion

    /// Decode a payload the phone sent and update `snapshot` if it parses.
    /// Centralised so application-context, user-info, and message payloads
    /// all funnel through one path.
    fileprivate func ingest(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(WatchSnapshot.self, from: data)
            self.snapshot = snap
            self.hasReceivedRealData = true
        } catch {
            // Malformed payload — keep the existing snapshot so the UI
            // doesn't flash empty. Log so a paired test surfaces the
            // mismatch.
            print("[WatchSession] decode failed: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSession: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith state: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            // Kick the phone for a fresh snapshot the first time we activate.
            if state == .activated {
                self.requestSnapshot()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.ingest(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.ingest(message)
        }
    }

    nonisolated func session(_ session: WCSession,
                              didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.ingest(userInfo)
        }
    }
}
