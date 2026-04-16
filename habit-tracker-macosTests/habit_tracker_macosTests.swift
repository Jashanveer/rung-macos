//
//  habit_tracker_macosTests.swift
//  habit-tracker-macosTests
//
//  Created by Jashanveer Singh on 4/14/26.
//

import Testing
@testable import habit_tracker_macos

struct habit_tracker_macosTests {

    @Test func currentStreakCountsBackwardFromEndDate() {
        let keys = [
            "2026-04-12",
            "2026-04-14",
            "2026-04-15",
            "2026-04-16",
        ]

        #expect(HabitMetrics.currentStreak(for: keys, endingAt: "2026-04-16") == 3)
        #expect(HabitMetrics.bestStreak(for: keys) == 3)
    }

    @Test func metricsComputesPerfectDaysAndTodayProgress() {
        let habits = [
            Habit(
                title: "Read",
                createdAt: DateKey.date(from: "2026-04-14"),
                completedDayKeys: ["2026-04-14", "2026-04-15", "2026-04-16"]
            ),
            Habit(
                title: "Walk",
                createdAt: DateKey.date(from: "2026-04-14"),
                completedDayKeys: ["2026-04-15"]
            ),
        ]

        let metrics = HabitMetrics.compute(for: habits, todayKey: "2026-04-16")

        #expect(metrics.totalHabits == 2)
        #expect(metrics.doneToday == 1)
        #expect(metrics.progressToday == 0.5)
        #expect(metrics.perfectDays == ["2026-04-15"])
        #expect(metrics.currentPerfectStreak == 0)
    }
}
