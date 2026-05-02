import SwiftUI

// MARK: - Shared / Regular Layout

struct YearPerfectCalendar: View {
    @Environment(\.colorScheme) private var colorScheme

    let dailyCompletionCounts: [String: Int]
    let perfectDayKeys: Set<String>
    let displayMode: CalendarDisplayMode
    let totalHabits: Int
    var isCompact: Bool = false
    var namespace: Namespace.ID? = nil
    var onTapMonth: ((Int) -> Void)? = nil

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 122), spacing: 18)]
    }
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
                    HStack(spacing: 10) {
                        ForEach(legendLevels, id: \.self) { level in
                            LegendDot(
                                title: level == 0 ? "None" : level == 4 ? "High" : "",
                                color: activityColor(for: level)
                            )
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        LegendDot(title: "Not perfect", color: CleanShotTheme.controlFill(for: colorScheme))
                        LegendDot(title: "Perfect", color: CleanShotTheme.success)
                    }
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...12, id: \.self) { month in
                    let tile = MonthDots(
                        month: month,
                        year: year,
                        dailyCompletionCounts: yearCompletionCounts,
                        perfectDayKeys: perfectDayKeys,
                        displayMode: displayMode,
                        totalHabits: totalHabits,
                        isCompact: isCompact
                    )
                    .modifier(MonthMatchedGeometry(namespace: namespace, month: month))

                    if let onTapMonth {
                        Button {
                            onTapMonth(month)
                        } label: {
                            tile
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        tile
                    }
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

private struct MonthMatchedGeometry: ViewModifier {
    let namespace: Namespace.ID?
    let month: Int

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "month-\(month)", in: namespace, isSource: true)
        } else {
            content
        }
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
    var isCompact: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var days: [DayInfo] {
        DateKey.days(inMonth: month, year: year)
    }
    private var leadingEmptyCells: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
    private var dayCells: [DayInfo?] {
        Array(repeating: nil, count: leadingEmptyCells) + days.map { Optional($0) }
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

                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Circle()
                            .fill(fillColor(for: day.key))
                            .aspectRatio(1, contentMode: .fit)
                            .help(helpText(for: day.key))
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// iPad/macOS month detail. Retained from the previous design.
struct MonthDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let dailyCompletionCounts: [String: Int]
    let perfectDayKeys: Set<String>
    let displayMode: CalendarDisplayMode
    let totalHabits: Int
    let namespace: Namespace.ID
    let onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    private var days: [DayInfo] {
        DateKey.days(inMonth: month, year: year)
    }

    private var leadingEmptyCells: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var dayCells: [DayInfo?] {
        Array(repeating: nil, count: leadingEmptyCells) + days.map { Optional($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Year")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(CleanShotTheme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayMode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(longMonthName)
                .font(.system(size: 32, weight: .bold, design: .rounded))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayDetailCell(
                            day: day,
                            fillColor: fillColor(for: day.key),
                            helpText: helpText(for: day.key)
                        )
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme).opacity(0.4))
                .matchedGeometryEffect(id: "month-\(month)", in: namespace, isSource: false)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.width > 60 || value.translation.height > 80 {
                        onClose()
                    }
                }
        )
    }

    private var longMonthName: String {
        Calendar.current.monthSymbols[month - 1]
    }

    private func fillColor(for dayKey: String) -> Color {
        if displayMode == .perfectDays {
            return perfectDayKeys.contains(dayKey)
                ? CleanShotTheme.success
                : CleanShotTheme.controlFill(for: colorScheme)
        }
        let count = dailyCompletionCounts[dayKey, default: 0]
        guard count > 0 else {
            return CleanShotTheme.controlFill(for: colorScheme)
        }
        let scaled = Double(count) / Double(max(totalHabits, 1))
        switch scaled {
        case ..<0.25: return CleanShotTheme.success.opacity(0.26)
        case ..<0.5:  return CleanShotTheme.success.opacity(0.46)
        case ..<0.75: return CleanShotTheme.success.opacity(0.68)
        default:      return CleanShotTheme.success.opacity(0.9)
        }
    }

    private func helpText(for dayKey: String) -> String {
        if displayMode == .perfectDays {
            return perfectDayKeys.contains(dayKey) ? "Perfect day" : "Not perfect"
        }
        return "\(dailyCompletionCounts[dayKey, default: 0]) habits"
    }
}

private struct DayDetailCell: View {
    let day: DayInfo
    let fillColor: Color
    let helpText: String

    private var dayNumber: String {
        Int(day.key.suffix(2)).map(String.init) ?? ""
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
            Text(dayNumber)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .help(helpText)
    }
}

