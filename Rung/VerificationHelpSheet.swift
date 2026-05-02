import SwiftUI

/// Surfaced from onboarding's permissions step + the Settings panel.
/// Walks the user through which canonical habits auto-verify against
/// Apple Health (or Screen Time on iOS) and which stay honor-system,
/// plus the leaderboard-weight tier each lands in. The content is
/// derived from the live `CanonicalHabits.all` so it stays in sync if
/// the registry grows new entries.
struct VerificationHelpSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    tierSection(
                        title: "Auto-verified",
                        weight: "10× leaderboard weight",
                        tint: Color.pink,
                        habits: habitsByTier(.auto)
                    )
                    tierSection(
                        title: "Partially verified",
                        weight: "5× leaderboard weight",
                        tint: Color.orange,
                        habits: habitsByTier(.partial)
                    )
                    selfReportSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 580)
        #else
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How verification works")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Why some habits check themselves and others don't")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.025)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                }
        )
    }

    // MARK: - Sections

    private var intro: some View {
        Text("Rung checks your habits against Apple Health and Screen Time so the leaderboard stays honest. Verifiable habits auto-check the moment evidence shows up — you can't tap them done yourself, and self-reporting them counts for less.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tierSection(
        title: String,
        weight: String,
        tint: Color,
        habits: [CanonicalHabit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .kerning(0.4)
                Text(weight)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 4) {
                ForEach(habits, id: \.key) { habit in
                    canonicalRow(habit, tint: tint)
                }
            }
        }
    }

    private func canonicalRow(_ habit: CanonicalHabit, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName(for: habit.key))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(habit.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(triggerCopy(for: habit))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
        )
    }

    private var selfReportSection: some View {
        let habits = habitsByTier(.selfReport)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("SELF-REPORT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
                Text("1× leaderboard weight")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Text("Honor-system habits — Apple Health doesn't track these, so the manual checkmark is the only signal. They still build streaks, just at base score.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                ForEach(habits, id: \.key) { habit in
                    HStack(spacing: 6) {
                        Image(systemName: iconName(for: habit.key))
                            .font(.system(size: 10, weight: .semibold))
                        Text(habit.displayName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                    )
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Missing the evidence?")
                .font(.system(size: 12, weight: .semibold))
            Text("Long-press a verifiable habit on the dashboard to surface a \"Mark done manually\" option. Manual marks record at the self-report tier so the cheating cost is preserved.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
        )
    }

    // MARK: - Helpers

    private func habitsByTier(_ tier: VerificationTier) -> [CanonicalHabit] {
        CanonicalHabits.all.filter { $0.tier == tier }
    }

    /// Maps each canonical key to a representative SF Symbol. Centralised
    /// here so the sheet UI stays in sync with the registry — adding a
    /// new canonical habit just needs a row added below to surface it.
    private func iconName(for key: String) -> String {
        switch key {
        case "run":         return "figure.run"
        case "workout":     return "dumbbell.fill"
        case "walk":        return "figure.walk"
        case "yoga":        return "figure.yoga"
        case "cycle":       return "bicycle"
        case "swim":        return "figure.pool.swim"
        case "meditate":    return "brain.head.profile"
        case "sleep":       return "bed.double.fill"
        case "weighIn":     return "scalemass.fill"
        case "water":       return "drop.fill"
        case "noAlcohol":   return "wineglass"
        case "screenTime":  return "iphone.slash"
        case "read":        return "book.fill"
        case "study":       return "graduationcap.fill"
        case "journal":     return "book.closed.fill"
        case "gratitude":   return "heart.fill"
        case "floss":       return "mouth.fill"
        case "makeBed":     return "bed.double"
        case "eatHealthy":  return "carrot.fill"
        case "family":      return "person.3.fill"
        default:            return "checkmark.circle.fill"
        }
    }

    /// Human-readable explanation of what triggers verification. Mirrors
    /// the actual queries `VerificationService` runs — keep this in sync
    /// when editing the verifier.
    private func triggerCopy(for habit: CanonicalHabit) -> String {
        switch habit.source {
        case .healthKitWorkout:
            if habit.param == nil {
                return "Any workout logged in Apple Health"
            }
            return "A \(habit.displayName.lowercased()) workout in Apple Health"
        case .healthKitSteps:
            let threshold = Int(habit.param ?? 0)
            return "\(threshold)+ steps for the day"
        case .healthKitMindful:
            let minutes = Int(habit.param ?? 0)
            return "\(minutes)+ mindful minutes logged"
        case .healthKitSleep:
            let hours = Int(habit.param ?? 0)
            return "\(hours)+ hours of sleep recorded"
        case .healthKitBodyMass:
            return "Any weigh-in logged today"
        case .healthKitHydration:
            let ml = Int(habit.param ?? 0)
            return "\(ml) ml of water tracked in Health"
        case .healthKitNoAlcohol:
            return "Zero alcoholic-beverage entries today"
        case .screenTimeSocial:
            let minutes = Int(habit.param ?? 0)
            #if os(iOS)
            return "Under \(minutes) min on selected social apps"
            #else
            return "Under \(minutes) min on social apps (iOS only)"
            #endif
        case .selfReport:
            return "Honor system — manual checkmark"
        }
    }
}

/// Minimal flow layout for the self-report chip cloud — wraps children
/// onto a new line when the row is full. Avoids a third-party dependency.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth - spacing)
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
