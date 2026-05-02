import SwiftUI

/// Streak-first calendar. The current streak takes the whole top half of the
/// screen — Rise-style hero number — with a 7-day rolling strip below so the
/// user can still see this week's perfect-day pattern at a glance. The dense
/// month grid moved to a drill-in to keep the tab itself scannable.
struct CalendarTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    private var snapshot: WatchSnapshot { session.snapshot }
    private var metrics: WatchSnapshot.Metrics { snapshot.metrics }

    var body: some View {
        VStack(spacing: 12) {
            streakHero
            weekStrip
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    // MARK: - Streak hero

    private var streakHero: some View {
        VStack(spacing: -2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(metrics.currentStreak)")
                    .font(WatchTheme.font(.hero, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.gold)
                Text("d")
                    .font(WatchTheme.font(.title, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.gold.opacity(0.6))
            }
            Text("CURRENT STREAK")
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - 7-day strip

    private var weekStrip: some View {
        let days = lastSevenDays(todayKey: snapshot.todayKey)
        return HStack(spacing: 4) {
            ForEach(days, id: \.dayKey) { day in
                DayCell(
                    label: day.label,
                    intensity: snapshot.calendarHeatmap[day.dayKey] ?? 0,
                    isToday: day.dayKey == snapshot.todayKey,
                    scale: scale
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9 * scale))
                .foregroundStyle(WatchTheme.gold.opacity(0.7))
            Text("Best \(metrics.bestStreak)d")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
            Text(snapshot.calendarMonthLabel)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(WatchTheme.inkSoft)
        }
    }

    // MARK: - Date helpers

    private struct StripDay {
        let dayKey: String
        let label: String   // "M T W T F S S"
    }

    private func lastSevenDays(todayKey: String) -> [StripDay] {
        guard let today = WatchDayKey.date(from: todayKey) else { return [] }
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let f = DateFormatter()
            f.dateFormat = "EEEEE"   // single-letter weekday
            return StripDay(
                dayKey: WatchDayKey.dayKey(for: date),
                label: f.string(from: date)
            )
        }
    }
}

// MARK: - Strip cell

private struct DayCell: View {
    let label: String
    let intensity: Double
    let isToday: Bool
    let scale: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .foregroundStyle(WatchTheme.inkSoft)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
                if isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WatchTheme.gold, lineWidth: 1.5)
                }
            }
            .frame(height: 28 * scale)
        }
        .frame(maxWidth: .infinity)
    }

    private var fillColor: Color {
        if intensity == 0 { return Color.white.opacity(0.06) }
        return WatchTheme.success.opacity(0.2 + intensity * 0.6)
    }
}

#if DEBUG
#Preview {
    CalendarTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
