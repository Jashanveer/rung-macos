import Combine
import Foundation
@preconcurrency import UserNotifications

enum HabitReminderWindow: String, CaseIterable, Identifiable, Codable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    var hour: Int {
        switch self {
        case .morning: return 9
        case .afternoon: return 14
        case .evening: return 19
        }
    }

    var subtitle: String {
        switch self {
        case .morning: return "9 AM"
        case .afternoon: return "2 PM"
        case .evening: return "7 PM"
        }
    }
}

@MainActor
final class TimeReminderManager: ObservableObject {
    private let identifierPrefix = "time-reminder-"
    private let streakEndingIdentifier = "streak-ending-soon"

    /// Evening warning hour/minute for the streak-ending-soon nudge. Chosen
    /// late enough that the user had a real chance to check in during the day,
    /// early enough that a freeze is still a deliberate choice (not a panic
    /// 11:59 tap).
    private static let streakWarningHour = 21
    private static let streakWarningMinute = 30

    /// Schedules or cancels the single "streak ending soon — use a freeze"
    /// warning for tonight. Conditions: user has a streak to protect, still
    /// has incomplete habits today, owns at least one freeze, and hasn't
    /// already frozen today. Requests notification authorization if the user
    /// has never been asked.
    func refreshStreakEndingReminder(
        currentStreak: Int,
        hasIncompleteHabits: Bool,
        freezesAvailable: Int,
        isFrozenToday: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [streakEndingIdentifier])

        let shouldSchedule = currentStreak >= 1
            && hasIncompleteHabits
            && freezesAvailable >= 1
            && !isFrozenToday
        guard shouldSchedule else { return }

        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Self.streakWarningHour
        components.minute = Self.streakWarningMinute
        guard let trigger = calendar.date(from: components),
              trigger > now.addingTimeInterval(60) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak ending soon"
        content.body = "Your \(currentStreak)-day streak is at risk. Tap to use a freeze and keep it alive."
        content.sound = .default

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)
        let notificationTrigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: streakEndingIdentifier,
            content: content,
            trigger: notificationTrigger
        )

        requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            center.add(request)
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    /// Schedule one notification per pending habit at the slot where the
    /// user's *own* energy curve favours that habit's task shape — workouts
    /// fire 30 min before the next morning peak, chores 30 min before the
    /// post-lunch dip, contemplative wind-down habits 90 min before bed.
    /// Falls back to silently skipping a habit when no good slot is left
    /// today (chip already advised the user).
    ///
    /// Identifier prefix `chrono-reminder-` so the chrono pass never
    /// collides with the legacy fixed-window pass; both can co-exist.
    func refreshChronotypeReminders(
        for habits: [Habit],
        forecast: EnergyForecast?,
        todayKey: String
    ) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let plans: [ChronotypeReminderPlan] = {
            guard let forecast else { return [] }
            return habits.compactMap { habit in
                chronotypePlan(for: habit, forecast: forecast, todayKey: todayKey, now: now)
            }
        }()

        center.getPendingNotificationRequests { [chronotypeIdentifierPrefix, plans] requests in
            let stale = requests.map(\.identifier)
                .filter { $0.hasPrefix(chronotypeIdentifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(chronotypeIdentifierPrefix)\(plan.identifier)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    /// Compute the trigger time and copy for a single habit. Returns nil
    /// when the habit is already done today, archived, or no slot remains
    /// in the day's window.
    private func chronotypePlan(
        for habit: Habit,
        forecast: EnergyForecast,
        todayKey: String,
        now: Date
    ) -> ChronotypeReminderPlan? {
        guard !habit.isArchived,
              habit.entryType == .habit,
              !habit.completedDayKeys.contains(todayKey) else { return nil }

        let shape = HabitTimeSuggestion.TaskShape.classify(
            canonicalKey: habit.canonicalKey,
            title: habit.title
        )

        let endOfDay = Calendar.current.date(
            bySettingHour: 23, minute: 30, second: 0, of: now
        ) ?? now.addingTimeInterval(12 * 3600)

        let band: Date?
        let bandLabel: String
        switch shape {
        case .peak:
            band = forecast.nextPeak(after: now, until: endOfDay)
            bandLabel = "your next energy peak"
        case .dip:
            band = forecast.nextDip(after: now, until: endOfDay)
            bandLabel = "the post-lunch dip"
        case .windDown:
            band = forecast.bedTime.addingTimeInterval(-90 * 60)
            bandLabel = "wind-down window"
        case .flexible:
            // Flexible habits don't get an extra chronotype nudge — the
            // legacy reminderWindow + per-habit chip already cover them
            // and stacking another notification just adds noise.
            return nil
        }

        guard let bandTime = band else { return nil }
        // Fire 30 min before the band so the user has time to start.
        let trigger = bandTime.addingTimeInterval(-30 * 60)
        guard trigger > now.addingTimeInterval(60) else { return nil }

        let stableId: String = {
            if let bid = habit.backendId { return "b\(bid)" }
            return habit.ensureLocalUUID().uuidString
        }()

        let timeStr: String = {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: bandTime)
        }()

        return ChronotypeReminderPlan(
            identifier: stableId,
            title: habit.title,
            body: "\(timeStr) is \(bandLabel) — start now to land it.",
            triggerDate: trigger
        )
    }

    private let chronotypeIdentifierPrefix = "chrono-reminder-"

    func refreshReminders(for habits: [Habit], todayKey: String) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let calendar = Calendar.current
        let plans = reminderPlans(for: habits, todayKey: todayKey, now: now, calendar: calendar)

        center.getPendingNotificationRequests { [identifierPrefix, plans] requests in
            let staleIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }

            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.triggerDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(identifierPrefix)\(plan.windowRawValue)",
                    content: content,
                    trigger: trigger
                )

                center.add(request)
            }
        }
    }

    // MARK: - Task reminders

    private let taskIdentifierPrefix = "task-reminder-"

    /// Schedules due-date reminders for every pending task. Cadence scales
    /// with the user's weekly consistency — flaky users get more nudges
    /// (3/day on the due day) while consistent users get a single morning
    /// heads-up. Cancelled + rescheduled on every habit-list change so a
    /// freshly-checked task doesn't keep buzzing.
    func refreshTaskReminders(
        for habits: [Habit],
        consistencyPercent: Int
    ) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let calendar = Calendar.current

        let pending = habits.filter { task in
            task.entryType == .task
                && !task.isArchived
                && !task.isTaskCompleted
                && task.dueAt != nil
        }

        let plans = pending.flatMap { task in
            taskReminderPlans(
                for: task,
                now: now,
                calendar: calendar,
                consistencyPercent: consistencyPercent
            )
        }

        center.getPendingNotificationRequests { [taskIdentifierPrefix, plans] requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(taskIdentifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default

                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(taskIdentifierPrefix)\(plan.identifier)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    /// Per-task plan list. Cadence rules:
    ///   - <50% consistency  → morning + noon + 1 h before due
    ///   - 50–80%            → morning + 2 h before due
    ///   - >80%              → morning of due day only
    /// Past triggers are silently dropped so the only requests added are
    /// future ones (avoiding "instant fire" on stale due dates).
    private func taskReminderPlans(
        for task: Habit,
        now: Date,
        calendar: Calendar,
        consistencyPercent: Int
    ) -> [TaskReminderPlan] {
        guard let due = task.dueAt else { return [] }

        let stableId: String = {
            if let bid = task.backendId { return "b\(bid)" }
            return task.ensureLocalUUID().uuidString
        }()

        let dueLabel = Self.dueDateLabel(due, calendar: calendar, now: now)
        let bodyText = "Due \(dueLabel): \(task.title)"

        let triggers = Self.taskTriggerDates(
            due: due,
            consistencyPercent: consistencyPercent,
            calendar: calendar
        )

        return triggers
            .filter { $0.date > now.addingTimeInterval(60) }
            .map { trigger in
                TaskReminderPlan(
                    identifier: "\(stableId)-\(trigger.slot)",
                    title: "Task due \(dueLabel)",
                    body: bodyText,
                    triggerDate: trigger.date
                )
            }
    }

    /// Computes the absolute trigger times for a task based on the user's
    /// weekly consistency. Static so it stays trivially testable.
    private static func taskTriggerDates(
        due: Date,
        consistencyPercent: Int,
        calendar: Calendar
    ) -> [(slot: String, date: Date)] {
        let dueDayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
        let dueDayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: due) ?? due
        let oneHourBefore = due.addingTimeInterval(-3600)
        let twoHoursBefore = due.addingTimeInterval(-7200)

        if consistencyPercent < 50 {
            // Lots of safety nets — three nudges before the deadline.
            return [
                ("morning", dueDayMorning),
                ("noon", dueDayNoon),
                ("1hbefore", oneHourBefore)
            ]
        } else if consistencyPercent < 80 {
            return [
                ("morning", dueDayMorning),
                ("2hbefore", twoHoursBefore)
            ]
        } else {
            // High-consistency users barely need reminding.
            return [("morning", dueDayMorning)]
        }
    }

    /// Friendly relative-date copy used in the notification title:
    /// "today", "tomorrow", "Friday", or "Aug 12" depending on distance.
    private static func dueDateLabel(_ date: Date, calendar: Calendar, now: Date) -> String {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        switch days {
        case 0:    return "today"
        case 1:    return "tomorrow"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: date)
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }

    private func reminderPlans(
        for habits: [Habit],
        todayKey: String,
        now: Date,
        calendar: Calendar
    ) -> [ReminderPlan] {
        HabitReminderWindow.allCases.compactMap { window in
            let assigned = habits.filter { habit in
                !habit.isArchived
                    && habit.entryType == .habit
                    && habit.reminderWindow == window.rawValue
            }

            guard !assigned.isEmpty else { return nil }

            let triggerDate = Self.nextTriggerDate(for: window, from: now, calendar: calendar)
            let triggerIsToday = calendar.isDate(triggerDate, inSameDayAs: now)
            let reminderHabits = triggerIsToday
                ? assigned.filter { !$0.completedDayKeys.contains(todayKey) }
                : assigned

            guard !reminderHabits.isEmpty else { return nil }

            return ReminderPlan(
                windowRawValue: window.rawValue,
                title: "\(window.rawValue) habits",
                body: reminderHabits.count == 1
                    ? "Still open: \(reminderHabits[0].title)"
                    : "\(reminderHabits.count) habits are waiting for this window.",
                triggerDate: triggerDate
            )
        }
    }

    private static func nextTriggerDate(
        for window: HabitReminderWindow,
        from now: Date,
        calendar: Calendar
    ) -> Date {
        let today = calendar.date(
            bySettingHour: window.hour,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        if today > now.addingTimeInterval(60) {
            return today
        }

        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

private struct ReminderPlan {
    let windowRawValue: String
    let title: String
    let body: String
    let triggerDate: Date
}

private struct TaskReminderPlan {
    let identifier: String
    let title: String
    let body: String
    let triggerDate: Date
}

private struct ChronotypeReminderPlan {
    let identifier: String
    let title: String
    let body: String
    let triggerDate: Date
}
