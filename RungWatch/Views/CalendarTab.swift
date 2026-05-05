import SwiftUI

/// Streak-first calendar. Streak number on top, then the **whole current
/// month** as a 6×7 rounded-dot grid (Mon-first, mirroring the iOS app).
/// A small toggle flips the grid between two modes:
///
///   • **Dots** — minimalist green-dot view ("did I show up that day?")
///   • **Heatmap** — graduated mint intensity ("how complete was that day?")
///
/// The 5-day strip from the previous design has been retired — users
/// asked to see the full month at a glance.
struct CalendarTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double
    @AppStorage("watchCalendarHeatmap") private var heatmapMode: Bool = false

    private var snapshot: WatchSnapshot { snapshotProxy() }
    private var metrics: WatchSnapshot.Metrics { snapshot.metrics }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPageTitle("Calendar", accent: WatchTheme.cPeach)
                streakHero
                modeToggle
                monthGrid
                footer
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .watchWashBackground(.peach)
    }

    // MARK: - Streak hero

    private var streakHero: some View {
        VStack(spacing: -2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(metrics.currentStreak)")
                    .font(WatchTheme.font(.hero, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.cAmber)
                Text("d")
                    .font(WatchTheme.font(.title, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.cAmber.opacity(0.6))
            }
            Text("CURRENT STREAK")
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeChip(title: "Dots", selected: !heatmapMode) { heatmapMode = false }
            modeChip(title: "Heat", selected:  heatmapMode) { heatmapMode = true  }
        }
    }

    private func modeChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(selected ? .white : WatchTheme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .liquidGlassSurface(
                    cornerRadius: 8,
                    tint: selected ? WatchTheme.cMint : nil,
                    strong: selected
                )
        }
        .buttonStyle(WatchPressStyle())
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        let layout = MonthGridLayout(referenceDate: Date(), todayKey: snapshot.todayKey)
        return VStack(alignment: .leading, spacing: 4) {
            // Month name + weekday header
            HStack(alignment: .firstTextBaseline) {
                Text(layout.monthName)
                    .font(WatchTheme.font(.body, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.ink)
                Spacer()
                Text(layout.year)
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(WatchTheme.inkSoft)
            }
            HStack(spacing: 3) {
                ForEach(layout.weekdayLabels, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            // 6 weekly rows × 7 columns of dots
            VStack(spacing: 3) {
                ForEach(layout.weeks.indices, id: \.self) { weekIdx in
                    HStack(spacing: 3) {
                        ForEach(layout.weeks[weekIdx].indices, id: \.self) { colIdx in
                            let cell = layout.weeks[weekIdx][colIdx]
                            DayDot(
                                cell: cell,
                                intensity: cell.dayKey.map { snapshot.calendarHeatmap[$0] ?? 0 } ?? 0,
                                heatmap: heatmapMode
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .liquidGlassSurface(cornerRadius: 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9 * scale))
                .foregroundStyle(WatchTheme.cAmber.opacity(0.8))
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

    /// Indirection so `snapshot` resolves at call time even when the
    /// SwiftData / WatchConnectivity push lands mid-build.
    private func snapshotProxy() -> WatchSnapshot { session.snapshot }
}

// MARK: - Day dot

/// One dot in the month grid. Render rules:
///   • Empty cell (off-month padding) → invisible spacer
///   • In-month, no completion → faint outlined circle
///   • Completed day, dots mode → mint-filled circle
///   • Completed day, heatmap mode → mint with intensity-based opacity
///   • Today → amber outline glowing through whichever fill is chosen
private struct DayDot: View {
    let cell: MonthGridLayout.Cell
    let intensity: Double
    let heatmap: Bool

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(
                Circle()
                    .stroke(strokeColor, lineWidth: cell.isToday ? 1.2 : 0.5)
            )
            .shadow(color: shadowColor, radius: cell.isToday ? 4 : (heatmap && intensity > 0 ? 3 : 0))
            .opacity(cell.dayKey == nil ? 0 : 1)
            .frame(maxWidth: 14, maxHeight: 14)
            .frame(height: 14)
    }

    private var fill: Color {
        guard let _ = cell.dayKey else { return .clear }
        if heatmap {
            return intensity == 0
                ? Color.white.opacity(0.06)
                : WatchTheme.cMint.opacity(0.30 + intensity * 0.55)
        }
        return intensity > 0
            ? WatchTheme.cMint.opacity(0.85)
            : Color.white.opacity(0.06)
    }

    private var strokeColor: Color {
        if cell.isToday { return WatchTheme.cAmber }
        return Color.white.opacity(0.10)
    }

    private var shadowColor: Color {
        if cell.isToday { return WatchTheme.cAmber.opacity(0.6) }
        if heatmap && intensity > 0 { return WatchTheme.cMint.opacity(0.45) }
        return .clear
    }
}

// MARK: - Month layout helper

/// Builds a 6-row × 7-col month grid from a reference date. Mon-first
/// (matches the iOS app's ISO calendar). Days outside the current month
/// land in `Cell.dayKey == nil` so the renderer can skip them. Putting
/// the maths here keeps the SwiftUI body readable and lets the unit
/// tests cover the bucket boundaries directly.
private struct MonthGridLayout {
    struct Cell {
        let dayKey: String?   // "yyyy-MM-dd" or nil for off-month padding
        let dayNumber: Int    // 1...31 or 0 for padding
        let isToday: Bool
    }

    let monthName: String
    let year: String
    let weekdayLabels: [String]
    let weeks: [[Cell]]   // 6 weeks of 7 cells each

    init(referenceDate: Date, todayKey: String) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // ISO-8601 = Monday first.

        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard
            let firstOfMonth = calendar.date(from: comps),
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else {
            self.monthName = ""
            self.year = ""
            self.weekdayLabels = []
            self.weeks = []
            return
        }

        let nameFormatter = DateFormatter()
        nameFormatter.dateFormat = "LLLL"
        self.monthName = nameFormatter.string(from: firstOfMonth)
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        self.year = yearFormatter.string(from: firstOfMonth)

        // Mon..Sun single-letter labels.
        self.weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

        // Index of the 1st of the month (0 = Mon, 6 = Sun) under ISO.
        let weekdayOfFirst = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        dayKeyFormatter.calendar = calendar
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.timeZone = .current

        var cells: [Cell] = []
        // Leading padding so the 1st lands in the right column.
        for _ in 0..<weekdayOfFirst {
            cells.append(.init(dayKey: nil, dayNumber: 0, isToday: false))
        }
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let key = dayKeyFormatter.string(from: date)
            cells.append(.init(dayKey: key, dayNumber: day, isToday: key == todayKey))
        }
        // Trailing padding to fill 6 rows.
        while cells.count < 42 {
            cells.append(.init(dayKey: nil, dayNumber: 0, isToday: false))
        }

        self.weeks = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }
}

#if DEBUG
#Preview {
    CalendarTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
