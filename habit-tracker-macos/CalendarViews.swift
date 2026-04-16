import SwiftUI

struct CalendarSheet: View {
    let perfectDays: [String]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Perfect Days")
                    .font(.headline)
                Spacer()
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

            YearPerfectCalendar(perfectDays: perfectDays)
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

    let perfectDays: [String]

    private let columns = [GridItem(.adaptive(minimum: 122), spacing: 18)]
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var perfectSet: Set<String> { Set(perfectDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(String(year)) Perfect Days")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 12) {
                    LegendDot(title: "Not perfect", color: CleanShotTheme.controlFill(for: colorScheme))
                    LegendDot(title: "Perfect", color: CleanShotTheme.success)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...12, id: \.self) { month in
                    MonthDots(month: month, year: year, perfectSet: perfectSet)
                }
            }
        }
        .padding(8)
    }
}

struct MonthDots: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let perfectSet: Set<String>

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
                        .fill(
                            perfectSet.contains(day.key)
                                ? CleanShotTheme.success
                                : CleanShotTheme.controlFill(for: colorScheme)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .help(day.key)
                }
            }
        }
    }

    private var monthName: String {
        Calendar.current.monthSymbols[month - 1].prefix(3).description
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
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Confetti Celebration

