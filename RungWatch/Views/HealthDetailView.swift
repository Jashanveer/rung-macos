import SwiftUI

/// Drill-in view for a HealthKit-linked habit. Read-only — the user can't
/// toggle these manually because `AutoVerificationCoordinator` on the iPhone
/// owns the state and re-broadcasts the snapshot on its own schedule.
struct HealthDetailView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    let habit: WatchSnapshot.WatchHabit

    /// "Synced 2m ago" — derived from the snapshot's `generatedAt` so the
    /// user gets a sense of freshness without polling on the watch.
    private var syncedLabel: String {
        let elapsed = Date().timeIntervalSince(session.snapshot.generatedAt)
        switch elapsed {
        case ..<10:                      return "Synced just now"
        case 10..<60:                    return "Synced \(Int(elapsed))s ago"
        case 60..<3600:                  return "Synced \(Int(elapsed / 60))m ago"
        case 3600..<86400:               return "Synced \(Int(elapsed / 3600))h ago"
        default:                         return "Synced \(Int(elapsed / 86400))d ago"
        }
    }

    private var progressColor: Color {
        habit.progress >= 1 ? WatchTheme.success : WatchTheme.accent
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(habit.emoji.isEmpty ? "\u{2665}" : habit.emoji)
                .font(.system(size: 18))

            Text(habit.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WatchTheme.ink)

            // ♥ AUTO badge
            Text("\u{2665} AUTO \u{00B7} APPLE HEALTH")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(WatchTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [WatchTheme.accent.opacity(0.18), WatchTheme.accent.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(WatchTheme.accent.opacity(0.4), lineWidth: 0.5)
                )

            // Big number
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(habit.unitsLogged)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(progressColor)
                if habit.unitsTarget > 0 {
                    Text("/\(habit.unitsTarget) \(habit.unitsLabel.lowercased())")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WatchTheme.inkSoft)
                }
            }
            .padding(.top, 2)

            // Progress bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(progressColor)
                        .frame(width: max(0, proxy.size.width * min(1, habit.progress)))
                }
            }
            .frame(height: 3)

            Text(syncedLabel)
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.inkSoft)
                .padding(.top, 1)
        }
        .padding(.horizontal, 11)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .watchWashNavigationBackground(.cyan)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("\u{2039}") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(WatchTheme.ink)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthDetailView(habit: .init(
            id: "demo",
            title: "Move 30 min",
            emoji: "\u{1F3C3}",
            kind: .healthKit,
            progress: 1.4,
            unitsLogged: 42,
            unitsTarget: 30,
            unitsLabel: "MIN",
            isCompleted: false,
            sourceLabel: "APPLE HEALTH",
            canonicalKey: "run"
        ))
        .environmentObject(WatchSession.shared)
    }
}
