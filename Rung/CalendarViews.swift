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

/// Top-level sheet mode for the regular (iPad / macOS) calendar surface.
/// Lets the user flip between the perfect-days calendar and the
/// HealthKit-driven energy curve without leaving the bottom-edge sheet.
/// Phones don't see this toggle — Energy lives in its own tab there.
enum CalendarSheetMode: String, CaseIterable, Identifiable {
    case calendar
    case energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .energy:   return "Energy"
        }
    }

    var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .energy:   return "bolt.heart.fill"
        }
    }
}

struct CalendarSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Namespace private var monthTransitionNamespace

    let habits: [Habit]
    let onClose: () -> Void
    @State private var displayMode: CalendarDisplayMode = .perfectDays
    @State private var zoomedMonth: Int?
    /// Top-level toggle (iPad / macOS only). The phone path has its own
    /// dedicated Energy tab so it never reads this flag.
    @State private var sheetMode: CalendarSheetMode = .calendar

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

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
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ZStack {
            content
                .opacity(zoomedMonth == nil ? 1 : 0)

            if let month = zoomedMonth {
                if isCompact {
                    PerfectDaysMonthDetailView(
                        month: month,
                        year: year,
                        habits: streakHabits,
                        perfectDayKeys: perfectDayKeys,
                        dailyCompletionCounts: dailyCompletionCounts,
                        totalHabits: totalHabits,
                        namespace: monthTransitionNamespace,
                        onClose: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                zoomedMonth = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    MonthDetailView(
                        month: month,
                        year: year,
                        dailyCompletionCounts: dailyCompletionCounts,
                        perfectDayKeys: perfectDayKeys,
                        displayMode: displayMode,
                        totalHabits: totalHabits,
                        namespace: monthTransitionNamespace,
                        onClose: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                zoomedMonth = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            compactBody
        } else {
            regularBody
        }
    }

    private var compactBody: some View {
        PerfectDaysYearView(
            year: year,
            perfectDayKeys: perfectDayKeys,
            dailyCompletionCounts: dailyCompletionCounts,
            totalHabits: totalHabits,
            displayMode: $displayMode,
            namespace: monthTransitionNamespace,
            onTapMonth: { month in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    zoomedMonth = month
                }
            }
        )
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(sheetMode == .calendar ? displayMode.title : "Energy")
                    .font(.headline)
                Spacer()
                CalendarSheetModeToggle(mode: $sheetMode, colorScheme: colorScheme)
                if sheetMode == .calendar {
                    CalendarModeToggle(mode: $displayMode, colorScheme: colorScheme)
                }
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

            // Both modes share a fixed-height container so flipping the
            // toggle never resizes the bottom sheet — same window, two
            // views. Height roughly matches a year-grid calendar's
            // natural size on macOS / iPad.
            Group {
                switch sheetMode {
                case .calendar:
                    YearPerfectCalendar(
                        dailyCompletionCounts: dailyCompletionCounts,
                        perfectDayKeys: perfectDayKeys,
                        displayMode: displayMode,
                        totalHabits: totalHabits,
                        isCompact: false,
                        namespace: monthTransitionNamespace,
                        onTapMonth: nil
                    )
                case .energy:
                    EnergyView(service: SleepInsightsService.shared)
                }
            }
            .frame(height: 540)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: sheetMode)
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

// MARK: - iPhone Year View (Image #6)

/// iPhone-only year view: 3×4 grid of month tiles with a mini perfect-day
/// heatmap inside each tile. Matches the Image #6 wireframe.
private struct PerfectDaysYearView: View {
    @Environment(\.colorScheme) private var colorScheme

    let year: Int
    let perfectDayKeys: Set<String>
    let dailyCompletionCounts: [String: Int]
    let totalHabits: Int
    @Binding var displayMode: CalendarDisplayMode
    let namespace: Namespace.ID
    let onTapMonth: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(1...12, id: \.self) { month in
                        Button {
                            onTapMonth(month)
                        } label: {
                            MonthHeatmapTile(
                                month: month,
                                year: year,
                                perfectDayKeys: perfectDayKeys,
                                dailyCompletionCounts: dailyCompletionCounts,
                                displayMode: displayMode,
                                totalHabits: totalHabits
                            )
                            .matchedGeometryEffect(id: "month-\(month)", in: namespace, isSource: true)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                legend
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayMode.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(String(year)) · tap a month to zoom")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CalendarModeToggle(mode: $displayMode, colorScheme: colorScheme)
        }
    }

    @ViewBuilder
    private var legend: some View {
        if displayMode == .perfectDays {
            HStack(spacing: 14) {
                LegendDot(title: "none", color: CleanShotTheme.controlFill(for: colorScheme))
                LegendDot(title: "perfect", color: CleanShotTheme.success)
                Spacer()
            }
            .padding(.horizontal, 2)
        } else {
            HStack(spacing: 10) {
                ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                    LegendDot(
                        title: level == 0 ? "none" : level == 4 ? "high" : "",
                        color: activityLegendColor(for: level)
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 2)
        }
    }

    private func activityLegendColor(for level: Int) -> Color {
        guard level > 0 else {
            return CleanShotTheme.controlFill(for: colorScheme)
        }
        let opacities: [Double] = [0.26, 0.46, 0.68, 0.9]
        return CleanShotTheme.success.opacity(opacities[max(0, min(level - 1, 3))])
    }
}

/// Single month tile in the year grid. Renders the month name at the top and
/// a compact heatmap of small circles — one per day. In perfect-days mode the
/// circle is green when the day was perfect, neutral otherwise. In activity
/// mode the circle shades with the ratio of habits completed.
private struct MonthHeatmapTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let perfectDayKeys: Set<String>
    let dailyCompletionCounts: [String: Int]
    let displayMode: CalendarDisplayMode
    let totalHabits: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2.5), count: 7)

    private var days: [DayInfo] {
        DateKey.days(inMonth: month, year: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthName)
                .font(.system(size: 15, weight: .bold, design: .rounded))

            LazyVGrid(columns: columns, spacing: 2.5) {
                ForEach(days) { day in
                    Circle()
                        .fill(fill(for: day.key))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme).opacity(0.45))
        }
    }

    private var monthName: String {
        Calendar.current.shortMonthSymbols[month - 1]
    }

    private func fill(for dayKey: String) -> Color {
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
}

// MARK: - iPhone Month Detail (Image #6)

/// iPhone-only month detail view. Shows a big day-circle grid with today
/// highlighted, plus a recap card at the bottom listing habits completed
/// on the currently-focused day.
private struct PerfectDaysMonthDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let habits: [Habit]
    let perfectDayKeys: Set<String>
    let dailyCompletionCounts: [String: Int]
    let totalHabits: Int
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var focusedDayKey: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
    private var todayKey: String { DateKey.key(for: Date()) }

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

    private var perfectCount: Int {
        days.filter { perfectDayKeys.contains($0.key) }.count
    }

    private var currentFocusKey: String {
        focusedDayKey ?? currentMonthTodayKey ?? days.last?.key ?? todayKey
    }

    private var currentMonthTodayKey: String? {
        days.first(where: { $0.key == todayKey })?.key
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                subtitle
                grid
                recapCard
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme).opacity(0.25))
                .matchedGeometryEffect(id: "month-\(month)", in: namespace, isSource: false)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.width > 60 {
                        onClose()
                    }
                }
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CleanShotTheme.accent)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(CleanShotTheme.controlFill(for: colorScheme))
                    }
            }
            .buttonStyle(.plain)

            Text("\(longMonthName) \(String(year))")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Spacer()
        }
    }

    private var subtitle: some View {
        Text("\(perfectCount) perfect \(perfectCount == 1 ? "day" : "days") of \(days.count)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(weekdays.indices, id: \.self) { index in
                Text(weekdays[index])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCircleButton(
                        day: day,
                        isPerfect: perfectDayKeys.contains(day.key),
                        isToday: day.key == todayKey,
                        isFocused: day.key == currentFocusKey,
                        completionCount: dailyCompletionCounts[day.key, default: 0],
                        totalHabits: totalHabits,
                        action: {
                            #if os(iOS)
                            Haptics.selection()
                            #endif
                            withAnimation(.easeInOut(duration: 0.18)) {
                                focusedDayKey = day.key
                            }
                        }
                    )
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private var recapCard: some View {
        DayRecapCard(
            dayKey: currentFocusKey,
            todayKey: todayKey,
            habits: habits,
            totalHabits: totalHabits,
            isPerfect: perfectDayKeys.contains(currentFocusKey)
        )
    }

    private var longMonthName: String {
        Calendar.current.monthSymbols[month - 1]
    }
}

/// Large circular day button used in the month detail grid. Green fill for
/// perfect days, blue ring for today, blue fill when the user is currently
/// inspecting that day.
private struct DayCircleButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let day: DayInfo
    let isPerfect: Bool
    let isToday: Bool
    let isFocused: Bool
    let completionCount: Int
    let totalHabits: Int
    let action: () -> Void

    private var dayNumber: String {
        Int(day.key.suffix(2)).map(String.init) ?? ""
    }

    private var fillColor: Color {
        if isPerfect {
            return CleanShotTheme.success
        }
        if completionCount > 0, totalHabits > 0 {
            let ratio = Double(completionCount) / Double(totalHabits)
            return CleanShotTheme.success.opacity(max(0.18, min(ratio * 0.7, 0.7)))
        }
        return CleanShotTheme.controlFill(for: colorScheme)
    }

    private var textColor: Color {
        isPerfect ? .white : .primary
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fillColor)
                if isToday {
                    Circle()
                        .strokeBorder(CleanShotTheme.accent, lineWidth: 2.5)
                }
                if isFocused && !isToday {
                    Circle()
                        .strokeBorder(CleanShotTheme.accent.opacity(0.55), lineWidth: 2)
                }
                Text(dayNumber)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

/// Bottom "recap" card shown under the month grid. Lists the completed habits
/// for the currently focused day as pill chips.
private struct DayRecapCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let dayKey: String
    let todayKey: String
    let habits: [Habit]
    let totalHabits: Int
    let isPerfect: Bool

    private var completedHabits: [Habit] {
        habits.filter { $0.completedDayKeys.contains(dayKey) }
    }

    private var completedCount: Int {
        completedHabits.count
    }

    private var dateString: String {
        let date = DateKey.date(from: dayKey)
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var statusLabel: String {
        guard totalHabits > 0 else { return "no habits yet" }
        if isPerfect {
            return "\(completedCount)/\(totalHabits) — perfect day"
        }
        if completedCount == 0 {
            return "0/\(totalHabits) — no habits logged"
        }
        return "\(completedCount)/\(totalHabits) completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(dateString)
                    .font(.system(size: 15, weight: .semibold))
                if dayKey == todayKey {
                    Text("· today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CleanShotTheme.accent)
                }
                Spacer()
            }

            Text(statusLabel)
                .font(.subheadline)
                .foregroundStyle(isPerfect ? CleanShotTheme.success : .secondary)

            if !completedHabits.isEmpty {
                WrappingChips(items: completedHabits.map(\.title))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme).opacity(0.55))
        }
    }
}

/// Simple flow layout for pill chips — wraps to new rows as they fill.
private struct WrappingChips: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CleanShotTheme.success)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(CleanShotTheme.success.opacity(0.15))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(CleanShotTheme.success.opacity(0.35), lineWidth: 1)
                    }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowInfo {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [RowInfo] {
        var rows: [RowInfo] = [RowInfo()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].width + (rows[rows.count - 1].items.isEmpty ? 0 : spacing) + size.width
            if needed > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(RowInfo())
            }
            var row = rows[rows.count - 1]
            if !row.items.isEmpty { row.width += spacing }
            row.items.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

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

/// Top-level Calendar / Energy toggle — same visual language as
/// `CalendarModeToggle` so the iPad / macOS sheet header reads as one
/// coherent control bar rather than two unrelated pickers.
struct CalendarSheetModeToggle: View {
    @Binding var mode: CalendarSheetMode
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CalendarSheetMode.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = item
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(mode == item ? Color.white : .secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(mode == item ? Color.indigo : Color.clear)
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
