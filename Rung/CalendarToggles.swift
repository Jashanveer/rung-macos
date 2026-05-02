import SwiftUI

/// Top-level Calendar / Energy toggle — same visual language as
/// `CalendarModeToggle` so the iPad / macOS sheet header reads as one
/// coherent control bar rather than two unrelated pickers.
struct CalendarSheetModeToggle: View {
    @Binding var mode: CalendarSheetMode
    let colorScheme: ColorScheme

    /// Each segment fills this exact width so flipping between
    /// "Calendar" (longer) and "Energy" (shorter) doesn't resize the
    /// pill — sized to fit "Calendar" + icon at .system(size: 11).
    private static let segmentWidth: CGFloat = 84

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
                            .lineLimit(1)
                    }
                    .foregroundStyle(mode == item ? Color.white : Color.primary.opacity(0.78))
                    .frame(width: Self.segmentWidth, height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(mode == item ? activeFill(for: item) : Color.clear)
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

    /// Two-tone active fill: Calendar = green (matches the heatmap's
    /// success colour), Energy = indigo (matches the EnergyView gauge
    /// tint). Keeps the active segment visually rooted to its content.
    private func activeFill(for item: CalendarSheetMode) -> Color {
        switch item {
        case .calendar: return CleanShotTheme.success
        case .energy:   return Color.indigo
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

