import SwiftUI

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case activity
    case perfectDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity:
            return "Habit Activity"
        case .perfectDays:
            return "Perfect Days"
        }
    }

    var systemImage: String {
        switch self {
        case .activity:
            return "square.grid.3x3.fill"
        case .perfectDays:
            return "checkmark.seal.fill"
        }
    }
}

struct CalendarSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let habits: [Habit]
    let onClose: () -> Void
    @State private var displayMode: CalendarDisplayMode = .activity

    private var streakHabits: [Habit] {
        habits.filter { $0.entryType == .habit }
    }

    private var dailyCompletionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for habit in streakHabits {
            for dayKey in Set(habit.completedDayKeys) {
                counts[dayKey, default: 0] += 1
            }
        }
        return counts
    }
    private var perfectDayKeys: Set<String> {
        Set(HabitMetrics.perfectDayKeys(for: streakHabits))
    }
    private var totalHabits: Int {
        streakHabits.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(displayMode.title)
                    .font(.headline)
                Spacer()
                CalendarModeToggle(mode: $displayMode, colorScheme: colorScheme)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .cleanShotSurface(shape: Circle(), level: .control)
                }
                .buttonStyle(.plain)
            }

            YearPerfectCalendar(
                dailyCompletionCounts: dailyCompletionCounts,
                perfectDayKeys: perfectDayKeys,
                displayMode: displayMode,
                totalHabits: totalHabits
            )
        }
        .padding(18)
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
            level: .elevated,
            shadowRadius: 12
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.height > 50 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            onClose()
                        }
                    }
                }
        )
    }
}


struct YearPerfectCalendar: View {
    @Environment(\.colorScheme) private var colorScheme

    let dailyCompletionCounts: [String: Int]
    let perfectDayKeys: Set<String>
    let displayMode: CalendarDisplayMode
    let totalHabits: Int

    private let columns = [GridItem(.adaptive(minimum: 122), spacing: 18)]
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var yearCompletionCounts: [String: Int] {
        dailyCompletionCounts.filter { $0.key.hasPrefix("\(year)-") }
    }
    private var legendLevels: [Int] {
        [0, 1, 2, 3, 4]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(String(year)) \(displayMode.title)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if displayMode == .activity {
                    HStack(spacing: 12) {
                        ForEach(legendLevels, id: \.self) { level in
                            LegendDot(
                                title: level == 0 ? "None" : level == 4 ? "High" : "",
                                color: activityColor(for: level)
                            )
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        LegendDot(title: "Not perfect", color: CleanShotTheme.controlFill(for: colorScheme))
                        LegendDot(title: "Perfect", color: CleanShotTheme.success)
                    }
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...12, id: \.self) { month in
                    MonthDots(
                        month: month,
                        year: year,
                        dailyCompletionCounts: yearCompletionCounts,
                        perfectDayKeys: perfectDayKeys,
                        displayMode: displayMode,
                        totalHabits: totalHabits
                    )
                }
            }
        }
        .padding(8)
    }

    private func activityColor(for level: Int) -> Color {
        guard level > 0 else {
            return CleanShotTheme.controlFill(for: colorScheme)
        }
        let opacities: [Double] = [0.26, 0.46, 0.68, 0.9]
        return CleanShotTheme.success.opacity(opacities[max(0, min(level - 1, 3))])
    }
}

struct MonthDots: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let dailyCompletionCounts: [String: Int]
    let perfectDayKeys: Set<String>
    let displayMode: CalendarDisplayMode
    let totalHabits: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var days: [DayInfo] {
        DateKey.days(inMonth: month, year: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(monthName)
                .font(.caption.weight(.bold))

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(days) { day in
                    Circle()
                        .fill(fillColor(for: day.key))
                        .aspectRatio(1, contentMode: .fit)
                        .help(helpText(for: day.key))
                }
            }
        }
    }

    private var monthName: String {
        Calendar.current.monthSymbols[month - 1].prefix(3).description
    }

    private func fillColor(for dayKey: String) -> Color {
        if displayMode == .perfectDays {
            return perfectDayKeys.contains(dayKey)
                ? CleanShotTheme.success
                : CleanShotTheme.controlFill(for: colorScheme)
        }
        return activityColor(for: dayKey)
    }

    private func helpText(for dayKey: String) -> String {
        if displayMode == .perfectDays {
            return "\(dayKey): \(perfectDayKeys.contains(dayKey) ? "Perfect day" : "Not perfect")"
        }
        return "\(dayKey): \(dailyCompletionCounts[dayKey, default: 0]) habits completed"
    }

    private func activityColor(for dayKey: String) -> Color {
        let count = dailyCompletionCounts[dayKey, default: 0]
        guard count > 0 else {
            return CleanShotTheme.controlFill(for: colorScheme)
        }

        let scaled = Double(count) / Double(max(totalHabits, 1))
        switch scaled {
        case ..<0.25:
            return CleanShotTheme.success.opacity(0.26)
        case ..<0.5:
            return CleanShotTheme.success.opacity(0.46)
        case ..<0.75:
            return CleanShotTheme.success.opacity(0.68)
        default:
            return CleanShotTheme.success.opacity(0.9)
        }
    }
}

struct CalendarModeToggle: View {
    @Binding var mode: CalendarDisplayMode
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CalendarDisplayMode.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        mode = item
                    }
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(mode == item ? Color.white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(mode == item ? CleanShotTheme.success : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme))
        )
    }
}


struct LegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            if !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Confetti Celebration
