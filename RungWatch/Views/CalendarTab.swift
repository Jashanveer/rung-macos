import SwiftUI

/// Tab 2 — month grid heatmap of perfect-day completion. Today is gold-bordered
/// and the bottom row shows the current streak.
struct CalendarTab: View {
    @EnvironmentObject private var session: WatchSession

    private var snapshot: WatchSnapshot { session.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("S M T W T F S")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(WatchTheme.inkSoft)

            grid

            HStack(spacing: 4) {
                Spacer()
                Text("\u{1F525} \(snapshot.metrics.currentStreak)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.gold)
                Text("day streak")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.inkSoft)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    // MARK: - Grid

    private var grid: some View {
        let monthDays = monthDays(for: snapshot.todayKey)
        let leadingBlanks = leadingBlanks(for: monthDays.first?.date)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
            ForEach(monthDays, id: \.dayKey) { day in
                CalendarDayCell(
                    dayNumber: day.dayNumber,
                    intensity: snapshot.calendarHeatmap[day.dayKey] ?? 0,
                    isToday: day.dayKey == snapshot.todayKey
                )
            }
        }
    }

    // MARK: - Calendar maths

    private struct DayCell {
        let dayNumber: Int
        let dayKey: String
        let date: Date
    }

    private func monthDays(for todayKey: String) -> [DayCell] {
        guard let today = WatchDayKey.date(from: todayKey) else { return [] }
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
              let dayCount = calendar.range(of: .day, in: .month, for: today)?.count
        else { return [] }
        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            let dayNumber = calendar.component(.day, from: date)
            return DayCell(
                dayNumber: dayNumber,
                dayKey: WatchDayKey.dayKey(for: date),
                date: date
            )
        }
    }

    /// How many empty cells to drop before the 1st of the month. Sunday-first
    /// to match the SMTWTFS header in the design.
    private func leadingBlanks(for firstDate: Date?) -> Int {
        guard let firstDate else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: firstDate)  // 1 = Sunday
        return weekday - 1
    }
}

// MARK: - Cell

private struct CalendarDayCell: View {
    let dayNumber: Int
    let intensity: Double
    let isToday: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isToday ? WatchTheme.gold : Color.clear, lineWidth: 1)
                )
                .shadow(color: isToday ? WatchTheme.gold.opacity(0.5) : .clear,
                        radius: 2, x: 0, y: 0)

            Text("\(dayNumber)")
                .font(.system(size: 8, weight: isToday ? .bold : .medium))
                .foregroundStyle(intensity > 0.5 ? Color.white : WatchTheme.inkSoft)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var fillColor: Color {
        if intensity == 0 {
            return Color.white.opacity(0.05)
        }
        // Same alpha curve as the design HTML: 0.15 + intensity * 0.7
        let alpha = 0.15 + intensity * 0.7
        return WatchTheme.success.opacity(alpha)
    }
}

#Preview {
    CalendarTab()
        .environmentObject(WatchSession.shared)
}
