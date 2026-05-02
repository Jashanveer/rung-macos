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
    /// Calendar vs. Energy view selector. Gated by `showEnergyView`
    /// (Account setting) so users without Apple Watch can hide Energy.
    @State private var sheetMode: CalendarSheetMode = .calendar

    /// User-controlled toggle on the Account page. Defaults to true so
    /// existing users don't lose the Energy view. When false the Cal /
    /// Energy switcher disappears and `sheetMode` is pinned to .calendar.
    @AppStorage("Settings.showEnergyView") private var showEnergyView = true

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
        if isCompact {
            compactBody
        } else {
            regularBody
        }
    }

    private var compactBody: some View {
        VStack(spacing: 12) {
            if showEnergyView {
                HStack {
                    Spacer()
                    CalendarSheetModeToggle(mode: $sheetMode, colorScheme: colorScheme)
                }
                .padding(.horizontal, 4)
            }

            switch sheetMode {
            case .calendar:
                PerfectDaysYearView(
                    year: year,
                    perfectDayKeys: perfectDayKeys,
                    dailyCompletionCounts: dailyCompletionCounts,
                    totalHabits: totalHabits,
                    displayMode: $displayMode,
                    namespace: monthTransitionNamespace,
                    onTapMonth: { _ in }
                )
                .transition(.opacity.combined(with: .offset(y: 6)))
            case .energy:
                EnergyView(service: SleepInsightsService.shared)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: sheetMode)
        .onChange(of: showEnergyView) { _, newValue in
            // If the user disables Energy view from Settings while it's
            // active, snap back to the Calendar mode so they don't get
            // stuck on a hidden tab.
            if !newValue && sheetMode == .energy {
                sheetMode = .calendar
            }
        }
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The outer title used to read "Habit Activity" / "Energy"
            // but `YearPerfectCalendar` already prints "2026 Habit
            // Activity" on its own row, and `EnergyView` opens with its
            // own "Energy now" heading — so we keep the outer header to
            // controls only.
            HStack {
                Spacer()
                if showEnergyView {
                    CalendarSheetModeToggle(mode: $sheetMode, colorScheme: colorScheme)
                }
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

            // Fixed-height container so flipping the Calendar / Energy
            // toggle never resizes the bottom sheet. Sized to the
            // year-grid's natural footprint with a small breathing
            // margin — Energy mode scrolls inside the same window.
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
            .frame(height: 420)
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
        .onChange(of: showEnergyView) { _, newValue in
            if !newValue && sheetMode == .energy {
                sheetMode = .calendar
            }
        }
    }
}

