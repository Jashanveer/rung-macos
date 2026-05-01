import SwiftUI

/// Snapshot of the friend currently occupying the "mentee" character slot.
///
/// Per product decision, the orange character no longer surfaces a backend
/// mentee. It shows the top leaderboard friend (or the runner-up if the
/// current user already holds rank 1) so the user can see who they're chasing.
/// The chat affordance is gone — this is a stats card, not a conversation.
struct TopFriendSnapshot {
    let displayName: String
    /// Perfect days this week (the leaderboard ranking score).
    let perfectDays: Int
    /// Weekly consistency %, when social data has a match for `displayName`.
    let weeklyConsistencyPercent: Int?
    /// Today's completion % (0–100), when social data has a match.
    let progressPercent: Int?
    /// Leaderboard rank the friend occupies (1-based).
    let rank: Int
}

struct MenteeChatBubble: View {
    let friend: TopFriendSnapshot
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — orange accent to match Jazz character
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Rank #\(friend.rank) this week")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(titleBarColor)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Perfect days")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(friend.perfectDays)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                }

                if let consistency = friend.weeklyConsistencyPercent {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text("Weekly consistency")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(consistency)%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(consistencyColor(consistency))
                    }
                }

                if let progress = friend.progressPercent {
                    HStack {
                        Image(systemName: progress >= 100 ? "checkmark.circle.fill" : "clock.badge")
                            .foregroundStyle(progress >= 100 ? Color.green : Color.orange)
                            .font(.system(size: 12))
                        Text(progress >= 100 ? "Done today" : "Pending today")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(progress >= 100 ? "100%" : "\(progress)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(progress >= 100 ? Color.green : Color.orange)
                    }
                }
            }
            .padding(12)
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    lineWidth: 0.5
                )
        )
    }

    private func consistencyColor(_ percent: Int) -> Color {
        percent >= 70 ? .green : percent >= 40 ? .orange : .red
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.14, blue: 0.11)
            : Color(red: 1.0, green: 0.97, blue: 0.94)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.11, blue: 0.09)
            : Color.white
    }
}

/// Fallback bubble rendered when no leaderboard friend exists yet, so
/// tapping Jazz still gives visible feedback instead of opening into void.
struct MenteeEmptyChatBubble: View {
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text("No rival yet")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(titleBarColor)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Add a friend to the weekly challenge and Jazz will show who you're chasing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    lineWidth: 0.5
                )
        )
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.14, blue: 0.11)
            : Color(red: 1.0, green: 0.97, blue: 0.94)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.11, blue: 0.09)
            : Color.white
    }
}
