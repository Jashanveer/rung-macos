import Foundation
import SwiftUI

enum UserLevel: String {
    case beginner = "Beginner"
    case rising = "Rising"
    case consistent = "Consistent"
    case elite = "Elite"
    case mentor = "Mentor"
    case masterMentor = "Master Mentor"

    var systemImage: String {
        switch self {
        case .beginner:
            return "leaf"
        case .rising:
            return "arrow.up.forward"
        case .consistent:
            return "checkmark.seal"
        case .elite:
            return "star"
        case .mentor:
            return "person.2"
        case .masterMentor:
            return "crown"
        }
    }

    var tint: Color {
        switch self {
        case .beginner:
            return .secondary
        case .rising:
            return CleanShotTheme.accent
        case .consistent:
            return CleanShotTheme.success
        case .elite:
            return CleanShotTheme.violet
        case .mentor:
            return CleanShotTheme.gold
        case .masterMentor:
            return CleanShotTheme.warning
        }
    }
}

struct MentorCandidate: Identifiable {
    let id = UUID()
    let name: String
    let focus: String
    let timezone: String
    let language: String
    let consistency: Int
}

struct FeedPost: Identifiable {
    let id = UUID()
    let author: String
    let message: String
    let meta: String
    let systemImage: String
}

struct HabitMetrics {
    let totalHabits: Int
    let totalChecks: Int
    let doneToday: Int
    let progressToday: Double
    let perfectDays: [String]
    let perfectDaysCount: Int
    let bestPerfectStreak: Int
    let currentPerfectStreak: Int
    let medals: [Medal]
    let level: UserLevel
    let xp: Int
    let coins: Int
    let weeklyConsistency: Double
    let weeklyConsistencyPercent: Int
    let nextLevelProgress: Double
    let mentorEligible: Bool
    let needsMentor: Bool
    let accountabilityScore: Int
    let missedToday: Int
    let mentorCandidate: MentorCandidate
    let mentorTip: String
    let feedPosts: [FeedPost]
    let challengeProgress: Double
    let challengeRank: Int
    let daysUntilMentor: Int
    let levelNote: String

    static func compute(for habits: [Habit], todayKey: String) -> HabitMetrics {
        let totalHabits = habits.count
        let totalChecks = habits.reduce(0) { $0 + Set($1.completedDayKeys).count }
        let doneToday = habits.filter { $0.completedDayKeys.contains(todayKey) }.count
        let progressToday = totalHabits > 0 ? Double(doneToday) / Double(totalHabits) : 0
        let perfectDays = perfectDayKeys(for: habits)
        let bestPerfectStreak = bestStreak(for: perfectDays)
        let currentPerfectStreak = perfectDays.contains(todayKey) ? currentStreak(for: perfectDays, endingAt: todayKey) : 0
        let medals = achievementMedals(for: habits, perfectDays: perfectDays, totalChecks: totalChecks, bestPerfectStreak: bestPerfectStreak)
        let weeklyConsistency = weeklyConsistency(for: habits, todayKey: todayKey)
        let weeklyConsistencyPercent = Int((weeklyConsistency * 100).rounded())
        let historyDays = habitHistoryDays(for: habits, todayKey: todayKey)
        let hasSevenDayHistory = historyDays >= 7 || Set(habits.flatMap(\.completedDayKeys)).count >= 7
        let level = userLevel(
            totalChecks: totalChecks,
            weeklyConsistency: weeklyConsistency,
            bestPerfectStreak: bestPerfectStreak,
            hasSevenDayHistory: hasSevenDayHistory
        )
        let xp = totalChecks * 12 + perfectDays.count * 35 + bestPerfectStreak * 20
        let coins = totalChecks * 3 + perfectDays.count * 25
        let mentorEligible = hasSevenDayHistory && totalHabits > 0 && weeklyConsistency >= 0.82
        let needsMentor = hasSevenDayHistory && totalHabits > 0 && weeklyConsistency < 0.58
        let missedToday = max(totalHabits - doneToday, 0)
        let accountabilityScore = min(100, Int((weeklyConsistency * 70 + progressToday * 30).rounded()))
        let recentPerfectDays = recentPerfectDaysCount(perfectDays: perfectDays)
        let challengeProgress = min(Double(recentPerfectDays) / 5.0, 1.0)
        let challengeRank = max(1, 4 - min(recentPerfectDays, 3))
        let daysUntilMentor = mentorEligible ? 0 : max(0, 7 - historyDays)
        let nextLevelProgress = nextLevelProgress(for: level, weeklyConsistency: weeklyConsistency, totalChecks: totalChecks)
        let mentorCandidate = mentorCandidate(for: habits, needsMentor: needsMentor)
        let mentorTip = mentorTip(missedToday: missedToday, progressToday: progressToday, currentPerfectStreak: currentPerfectStreak)
        let feedPosts = feedPosts(currentPerfectStreak: currentPerfectStreak, weeklyConsistencyPercent: weeklyConsistencyPercent)
        let levelNote = levelNote(for: level, mentorEligible: mentorEligible, needsMentor: needsMentor, daysUntilMentor: daysUntilMentor)

        return HabitMetrics(
            totalHabits: totalHabits,
            totalChecks: totalChecks,
            doneToday: doneToday,
            progressToday: progressToday,
            perfectDays: perfectDays,
            perfectDaysCount: perfectDays.count,
            bestPerfectStreak: bestPerfectStreak,
            currentPerfectStreak: currentPerfectStreak,
            medals: medals,
            level: level,
            xp: xp,
            coins: coins,
            weeklyConsistency: weeklyConsistency,
            weeklyConsistencyPercent: weeklyConsistencyPercent,
            nextLevelProgress: nextLevelProgress,
            mentorEligible: mentorEligible,
            needsMentor: needsMentor,
            accountabilityScore: accountabilityScore,
            missedToday: missedToday,
            mentorCandidate: mentorCandidate,
            mentorTip: mentorTip,
            feedPosts: feedPosts,
            challengeProgress: challengeProgress,
            challengeRank: challengeRank,
            daysUntilMentor: daysUntilMentor,
            levelNote: levelNote
        )
    }

    private static func weeklyConsistency(for habits: [Habit], todayKey: String) -> Double {
        guard !habits.isEmpty else { return 0 }

        let recentKeys = DateKey.recentDays(count: 7, endingAt: DateKey.date(from: todayKey)).map(\.key)
        let completed = recentKeys.reduce(0) { total, key in
            total + habits.filter { $0.completedDayKeys.contains(key) }.count
        }
        return min(Double(completed) / Double(habits.count * recentKeys.count), 1)
    }

    private static func habitHistoryDays(for habits: [Habit], todayKey: String) -> Int {
        guard let firstDate = habits.map(\.createdAt).min() else { return 0 }

        let start = Calendar.current.startOfDay(for: firstDate)
        let end = Calendar.current.startOfDay(for: DateKey.date(from: todayKey))
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(days + 1, 0)
    }

    private static func userLevel(
        totalChecks: Int,
        weeklyConsistency: Double,
        bestPerfectStreak: Int,
        hasSevenDayHistory: Bool
    ) -> UserLevel {
        guard hasSevenDayHistory else { return totalChecks > 8 ? .rising : .beginner }
        if weeklyConsistency >= 0.92 && bestPerfectStreak >= 21 { return .masterMentor }
        if weeklyConsistency >= 0.82 && totalChecks >= 30 { return .mentor }
        if weeklyConsistency >= 0.78 { return .elite }
        if weeklyConsistency >= 0.62 { return .consistent }
        if weeklyConsistency >= 0.34 { return .rising }
        return .beginner
    }

    private static func nextLevelProgress(for level: UserLevel, weeklyConsistency: Double, totalChecks: Int) -> Double {
        switch level {
        case .beginner:
            return min(Double(totalChecks) / 10.0, 1)
        case .rising:
            return min(weeklyConsistency / 0.62, 1)
        case .consistent:
            return min(weeklyConsistency / 0.78, 1)
        case .elite:
            return min(weeklyConsistency / 0.82, 1)
        case .mentor:
            return min(weeklyConsistency / 0.92, 1)
        case .masterMentor:
            return 1
        }
    }

    private static func recentPerfectDaysCount(perfectDays: [String]) -> Int {
        let perfectSet = Set(perfectDays)
        return DateKey.recentDays(count: 7).filter { perfectSet.contains($0.key) }.count
    }

    private static func mentorCandidate(for habits: [Habit], needsMentor: Bool) -> MentorCandidate {
        let focus = habits.first?.title ?? "Daily consistency"
        return MentorCandidate(
            name: needsMentor ? "Maya" : "Leo",
            focus: focus,
            timezone: TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "),
            language: Locale.current.identifier.split(separator: "_").first.map { String($0).uppercased() } ?? "EN",
            consistency: needsMentor ? 91 : 86
        )
    }

    private static func mentorTip(missedToday: Int, progressToday: Double, currentPerfectStreak: Int) -> String {
        if missedToday > 0 {
            return "Pick the smallest remaining habit and send your mentor a check-in after it is done."
        }
        if progressToday == 1 {
            return "Today is complete. Share one sentence about what made it easier."
        }
        if currentPerfectStreak > 0 {
            return "Protect the streak with one low-friction habit before the day gets busy."
        }
        return "Start with one habit. Accountability works best when the next step is obvious."
    }

    private static func feedPosts(currentPerfectStreak: Int, weeklyConsistencyPercent: Int) -> [FeedPost] {
        [
            FeedPost(author: "Maya", message: "Finished a 7-day morning routine streak.", meta: "Friend update", systemImage: "flame"),
            FeedPost(author: "Noor", message: "Hit 80% consistency after a rough start.", meta: "Progress update", systemImage: "chart.line.uptrend.xyaxis"),
            FeedPost(author: "You", message: currentPerfectStreak > 0 ? "\(currentPerfectStreak)-day streak is active." : "\(weeklyConsistencyPercent)% consistency this week.", meta: "Progress update", systemImage: "chart.line.uptrend.xyaxis")
        ]
    }

    private static func levelNote(for level: UserLevel, mentorEligible: Bool, needsMentor: Bool, daysUntilMentor: Int) -> String {
        if needsMentor {
            return "A mentor match is ready. The goal is support, not pressure."
        }
        if mentorEligible {
            return "You can mentor another user with gentle nudges and encouragement."
        }
        if daysUntilMentor > 0 {
            return "Keep tracking for \(daysUntilMentor) more \(daysUntilMentor == 1 ? "day" : "days") to unlock mentor review."
        }
        return "Current rank: \(level.rawValue). Build consistency before chasing intensity."
    }

    static func currentStreak(for keys: [String], endingAt endKey: String) -> Int {
        let dateKeys = Set(keys)
        var streak = 0
        var cursor = DateKey.date(from: endKey)

        while dateKeys.contains(DateKey.key(for: cursor)) {
            streak += 1
            cursor = DateKey.addDays(cursor, -1)
        }

        return streak
    }

    static func bestStreak(for keys: [String]) -> Int {
        let sorted = Array(Set(keys)).sorted()
        guard !sorted.isEmpty else { return 0 }

        var best = 1
        var current = 1

        for index in sorted.indices.dropFirst() {
            let previous = DateKey.date(from: sorted[index - 1])
            let currentDate = DateKey.date(from: sorted[index])
            if Calendar.current.dateComponents([.day], from: previous, to: currentDate).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
        }

        return best
    }

    private static func perfectDayKeys(for habits: [Habit]) -> [String] {
        guard !habits.isEmpty else { return [] }

        let allKeys = Set(habits.flatMap(\.completedDayKeys))
        return allKeys
            .filter { key in habits.allSatisfy { $0.completedDayKeys.contains(key) } }
            .sorted()
    }

    private static func achievementMedals(for habits: [Habit], perfectDays: [String], totalChecks: Int, bestPerfectStreak: Int) -> [Medal] {
        [
            Medal(id: "first-perfect", title: "First Perfect Day", unlocked: !perfectDays.isEmpty, dateKey: perfectDays.first),
            Medal(id: "streak-7", title: "Streak 7", unlocked: bestPerfectStreak >= 7, dateKey: milestoneDate(in: perfectDays, threshold: 7)),
            Medal(id: "streak-21", title: "Streak 21", unlocked: bestPerfectStreak >= 21, dateKey: milestoneDate(in: perfectDays, threshold: 21)),
            Medal(id: "streak-50", title: "Streak 50", unlocked: bestPerfectStreak >= 50, dateKey: milestoneDate(in: perfectDays, threshold: 50)),
            Medal(id: "checks-100", title: "100 Checks", unlocked: totalChecks >= 100, dateKey: checksMilestoneDate(for: habits, threshold: 100)),
            Medal(id: "checks-500", title: "500 Checks", unlocked: totalChecks >= 500, dateKey: checksMilestoneDate(for: habits, threshold: 500))
        ]
    }

    private static func milestoneDate(in keys: [String], threshold: Int) -> String? {
        guard threshold > 0 else { return nil }

        var current = 0
        for index in keys.indices {
            if index == keys.startIndex {
                current = 1
            } else {
                let previous = DateKey.date(from: keys[index - 1])
                let currentDate = DateKey.date(from: keys[index])
                current = Calendar.current.dateComponents([.day], from: previous, to: currentDate).day == 1 ? current + 1 : 1
            }

            if current >= threshold {
                return keys[index]
            }
        }

        return nil
    }

    private static func checksMilestoneDate(for habits: [Habit], threshold: Int) -> String? {
        var countsByDate: [String: Int] = [:]
        for habit in habits {
            for key in Set(habit.completedDayKeys) {
                countsByDate[key, default: 0] += 1
            }
        }

        var total = 0
        for key in countsByDate.keys.sorted() {
            total += countsByDate[key, default: 0]
            if total >= threshold {
                return key
            }
        }

        return nil
    }
}

struct Medal: Identifiable {
    let id: String
    let title: String
    let unlocked: Bool
    let dateKey: String?

    var subtitle: String {
        guard unlocked else { return "Locked" }
        guard let dateKey else { return "Unlocked" }
        return "Unlocked on \(DateKey.date(from: dateKey).formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

struct DayInfo: Identifiable {
    let key: String
    let shortLabel: String

    var id: String { key }
}

enum SmartGreeting {
    static func generate(habits: [Habit], todayKey: String, doneToday: Int, totalHabits: Int, currentStreak: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"

        guard totalHabits > 0 else { return timeGreeting }

        let completedHabits = habits.filter { $0.completedDayKeys.contains(todayKey) }
        let remaining = totalHabits - doneToday

        if doneToday == totalHabits {
            let celebrations = [
                "All done! You crushed it today",
                "Perfect day! Nothing left to do",
                "Everything checked off. Well done!",
                "100% complete. Take a well-deserved break",
                "All habits done! You're on fire"
            ]
            if currentStreak > 1 {
                return "\(currentStreak)-day perfect streak! Keep going"
            }
            return celebrations[stableIndex(for: todayKey, count: celebrations.count)]
        }

        if doneToday > 0 {
            let lastDone = completedHabits.last
            if let title = lastDone?.title {
                let prompts = [
                    "\(title) done — \(remaining) more to go!",
                    "Nice, \(title) is checked off! What's next?",
                    "\(title) complete! \(remaining) \(remaining == 1 ? "habit" : "habits") left",
                    "Knocked out \(title)! Keep the momentum"
                ]
                return prompts[stableIndex(for: todayKey + title, count: prompts.count)]
            }
            return "\(doneToday) of \(totalHabits) done — keep going!"
        }

        if currentStreak > 0 {
            return "\(timeGreeting) — \(currentStreak)-day streak on the line!"
        }

        let motivations = [
            "\(timeGreeting) — \(remaining) \(remaining == 1 ? "habit" : "habits") waiting for you",
            "\(timeGreeting)! Ready to start today?",
            "\(timeGreeting) — let's make today count",
            "Fresh day, \(remaining) \(remaining == 1 ? "habit" : "habits") to tackle"
        ]
        return motivations[stableIndex(for: todayKey, count: motivations.count)]
    }

    private static func stableIndex(for seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(count))
    }
}

enum DateKey {
    static func key(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Calendar.current.startOfDay(for: Date()) }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Calendar.current.startOfDay(for: Date())
    }

    static func addDays(_ date: Date, _ amount: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: amount, to: date) ?? date
    }

    static func recentDays(count: Int, endingAt endDate: Date = Date()) -> [DayInfo] {
        let end = Calendar.current.startOfDay(for: endDate)
        return (0..<count).map { index in
            let date = addDays(end, index - (count - 1))
            return DayInfo(
                key: key(for: date),
                shortLabel: String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
            )
        }
    }

    static func days(inMonth month: Int, year: Int) -> [DayInfo] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: date(from: String(format: "%04d-%02d-01", year, month))) else {
            return []
        }

        return range.compactMap { day in
            guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) else {
                return nil
            }
            return DayInfo(key: key(for: date), shortLabel: "")
        }
    }
}
