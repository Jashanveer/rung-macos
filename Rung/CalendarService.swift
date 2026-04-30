import Combine
import EventKit
import Foundation
import SwiftUI

/// Bridges Apple Calendar (via EventKit) into Rung so the app can:
/// - Suggest a streak freeze on days the user has back-to-back meetings.
/// - Surface tasks whose title overlaps with today's meeting titles, so
///   the dashboard can push meeting-related work toward the top.
///
/// Authorization: iOS 17+ / macOS 14+ require `requestFullAccessToEvents`.
/// Older OS versions still call the deprecated `requestAccess(to:)` path.
/// Both paths resolve to the same `isAuthorized` boolean so callers don't
/// need to branch on availability.
///
/// All EKEventStore work runs off the main thread; published state mutates
/// back on the main actor so SwiftUI views can observe without bouncing.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    /// Snapshot of today's events (00:00 → 23:59 local). Refreshed on
    /// `refresh()` and whenever EventKit posts a store-changed notification.
    @Published private(set) var todaysEvents: [CalendarEvent] = []

    /// Whether the user has granted full or write-only access to Calendars.
    /// Read-only access also satisfies our needs (we never write events).
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        observeStoreChanges()
        Task { await refreshIfAuthorized() }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    /// Asks the user to grant Calendar access if they haven't already.
    /// Returns the resulting status. No-op on platforms where Calendar
    /// access is unavailable. Safe to call repeatedly — EventKit coalesces
    /// duplicate prompts when the user has already answered.
    @discardableResult
    func requestAccess() async -> EKAuthorizationStatus {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                    store.requestAccess(to: .event) { granted, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: granted) }
                    }
                }
            }
        } catch {
            // Failure here usually means the user denied or the entitlement
            // is missing. We don't surface the error — the UI just keeps
            // rendering the "connect calendar" call-to-action.
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        if isAuthorized {
            await refresh()
        }
        return status
    }

    /// Pulls today's events and updates `todaysEvents`. No-op when the
    /// user hasn't granted access.
    func refresh() async {
        guard isAuthorized else {
            todaysEvents = []
            return
        }
        let snapshot = await fetchTodaysEvents()
        await MainActor.run { self.todaysEvents = snapshot }
    }

    /// Authorization shorthand. `.fullAccess` (iOS 17+) and the legacy
    /// `.authorized` both grant read+write — read alone (`.writeOnly`) is
    /// not enough for our queries, so we explicitly exclude it.
    var isAuthorized: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return authorizationStatus == .fullAccess
        }
        // On older OSes the only "yes" is the deprecated .authorized case.
        // Use rawValue so the check compiles on iOS 17+/macOS 14+ without
        // emitting a deprecation warning (the symbolic case is removed in
        // future SDK passes; rawValue is stable).
        return authorizationStatus.rawValue == EKAuthorizationStatus.authorized.rawValue
    }

    /// Convenience flag for the "you have meetings today, freeze your
    /// streak?" banner. Filters out all-day events because most all-day
    /// items are reminders/birthdays/holidays — not the kind of thing
    /// that crowds out a habit completion.
    var hasMeetingToday: Bool {
        todaysEvents.contains { !$0.isAllDay }
    }

    /// Total non-all-day meeting minutes scheduled for today. Useful for
    /// the streak-freeze suggestion: a >180 minute day is the threshold
    /// where blocking off habits silently is genuinely more humane than
    /// nagging the user.
    var meetingMinutesToday: Int {
        todaysEvents.reduce(0) { acc, event in
            guard !event.isAllDay else { return acc }
            return acc + max(0, Int(event.duration / 60))
        }
    }

    /// Naive matcher: returns events whose title shares a meaningful word
    /// (≥4 letters) with `taskTitle`. Stop-words ("the", "a", "and", …)
    /// are filtered out so a task called "the report" doesn't match every
    /// event with "the" in it.
    func eventsRelated(to taskTitle: String) -> [CalendarEvent] {
        let taskTokens = significantTokens(taskTitle)
        guard !taskTokens.isEmpty else { return [] }
        return todaysEvents.filter { event in
            let eventTokens = significantTokens(event.title)
            return !eventTokens.isDisjoint(with: taskTokens)
        }
    }

    /// True when at least one of today's events shares a significant token
    /// with `taskTitle`. The dashboard uses this to bump matching tasks
    /// toward the top of the list.
    func isTaskTiedToMeeting(_ taskTitle: String) -> Bool {
        !eventsRelated(to: taskTitle).isEmpty
    }

    // MARK: - Private

    private func observeStoreChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refreshIfAuthorized() }
        }
    }

    private func refreshIfAuthorized() async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else { return }
        await refresh()
    }

    private func fetchTodaysEvents() async -> [CalendarEvent] {
        await Task.detached(priority: .utility) { [store] in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate)
            return events.map(CalendarEvent.init(from:))
        }.value
    }

    private func significantTokens(_ text: String) -> Set<String> {
        let stopwords: Set<String> = [
            "the", "and", "for", "with", "from", "into", "onto",
            "this", "that", "these", "those", "your", "their",
            "about", "after", "before", "between", "during",
            "today", "tomorrow", "yesterday", "tonight",
            "meeting", "call", "sync", "review", "session",
        ]
        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true)
        return Set(
            tokens
                .map(String.init)
                .filter { $0.count >= 4 && !stopwords.contains($0) }
        )
    }
}

/// Plain-old-data snapshot of an EKEvent so SwiftUI views don't depend on
/// EventKit symbols and can be previewed without prompting for access.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColorHex: String?

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    init(from event: EKEvent) {
        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "Untitled event"
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.calendarTitle = event.calendar?.title ?? ""
        if let color = event.calendar?.cgColor {
            self.calendarColorHex = CalendarEvent.hex(from: color)
        } else {
            self.calendarColorHex = nil
        }
    }

    private static func hex(from cgColor: CGColor) -> String? {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - UI

/// Lightweight banner the dashboard shows when the user has meetings
/// scheduled today. Three states:
///
/// 1. Calendar permission not yet asked → "Connect calendar" call-to-action.
/// 2. Authorized + meetings present → meeting count + optional freeze CTA.
/// 3. Authorized + nothing today → renders nothing (don't waste space).
struct CalendarInsightsBanner: View {
    @ObservedObject var service: CalendarService
    /// Whether the user currently has at least one habit/task that hasn't
    /// been checked off today. The freeze CTA only shows when work remains.
    var hasIncompleteHabits: Bool
    /// Whether the user owns at least one freeze. We don't surface the
    /// suggestion when there's nothing to redeem.
    var freezesAvailable: Int
    /// Tapped when the user accepts the freeze suggestion. Caller is
    /// responsible for calling the backend `/freeze/today` route etc.
    var onFreezeToday: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch service.authorizationStatus {
            case .notDetermined:
                connectCTA
            case .denied, .restricted:
                EmptyView()
            default:
                if service.isAuthorized && service.hasMeetingToday {
                    meetingsCard
                } else {
                    EmptyView()
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: service.authorizationStatus)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: service.hasMeetingToday)
    }

    // MARK: - States

    private var connectCTA: some View {
        Button {
            Task { await service.requestAccess() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect your calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Auto-suggest streak freezes on busy days.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 520)
    }

    private var meetingsCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
                .background(Color.purple.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(headlineCopy)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitleCopy)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldOfferFreeze {
                    Button(action: onFreezeToday) {
                        HStack(spacing: 5) {
                            Image(systemName: "snowflake")
                                .font(.system(size: 10, weight: .bold))
                            Text("Freeze today's streak")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.32), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.purple.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.20), lineWidth: 0.5)
        )
        .frame(maxWidth: 520)
    }

    // MARK: - Copy

    private var meetingCount: Int {
        service.todaysEvents.filter { !$0.isAllDay }.count
    }

    private var headlineCopy: String {
        let count = meetingCount
        return count == 1 ? "1 meeting today" : "\(count) meetings today"
    }

    private var subtitleCopy: String {
        let mins = service.meetingMinutesToday
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            if m == 0 { return "About \(h)h scheduled — busy day ahead." }
            return "About \(h)h \(m)m scheduled — busy day ahead."
        }
        return "About \(mins)m scheduled."
    }

    /// Threshold matches the streak-freeze nudge's intent: only suggest
    /// freezing when the day is genuinely busy (>= 3h) AND the user has
    /// real work left AND they own a freeze to spend.
    private var shouldOfferFreeze: Bool {
        hasIncompleteHabits && freezesAvailable >= 1 && service.meetingMinutesToday >= 180
    }
}

