import SwiftUI

/// Mentor tab — focuses the **most recent message** as a hero card filling
/// the top of the screen, with the rest of the thread tucked underneath
/// for users who want to scroll. iMessage-style reading order: oldest at
/// top of the secondary list, freshest is the hero.
struct MentorTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    private var messages: [WatchSnapshot.WatchMentorMessage] {
        session.snapshot.mentorMessages ?? []
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        if let latest = messages.last {
                            HeroMessage(message: latest, scale: scale)
                        }
                        if messages.count > 1 {
                            VStack(spacing: 3) {
                                ForEach(messages.dropLast()) { msg in
                                    HistoryRow(message: msg, scale: scale)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
        }
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22 * scale))
                .foregroundStyle(WatchTheme.inkSoft)
            Text("No messages")
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
            Text("Reply on iPhone\nto start the thread")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hero (latest)

private struct HeroMessage: View {
    let message: WatchSnapshot.WatchMentorMessage
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.origin == .me ? AnyShapeStyle(WatchTheme.brandGradient)
                                                  : AnyShapeStyle(WatchTheme.accent))
                    .frame(width: 18 * scale, height: 18 * scale)
                    .overlay(
                        Text(String(message.senderName.prefix(1)).uppercased())
                            .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                            .foregroundStyle(.white)
                    )
                Text(message.senderName)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(WatchTheme.ink)
                Spacer()
                Text(message.relativeTime.uppercased())
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(message.isUnread ? WatchTheme.gold : WatchTheme.inkSoft)
            }
            Text(message.preview)
                .font(WatchTheme.font(.body, scale: scale, weight: .regular))
                .foregroundStyle(WatchTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var heroBackground: some View {
        if message.isUnread && message.origin == .mentor {
            LinearGradient(colors: [WatchTheme.gold.opacity(0.22),
                                    WatchTheme.gold.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WatchTheme.gold.opacity(0.4), lineWidth: 0.5)
                )
        } else if message.origin == .me {
            LinearGradient(colors: [WatchTheme.accent.opacity(0.22),
                                    WatchTheme.accent.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WatchTheme.accent.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            LinearGradient(colors: [Color.white.opacity(0.07),
                                    Color.white.opacity(0.025)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - History row (older messages, compact)

private struct HistoryRow: View {
    let message: WatchSnapshot.WatchMentorMessage
    let scale: Double

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(message.origin == .me ? "you" : message.senderName)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(message.origin == .me ? WatchTheme.accent : WatchTheme.gold)
                .frame(width: 38, alignment: .leading)
            Text(message.preview)
                .font(WatchTheme.font(.caption, scale: scale, weight: .regular))
                .foregroundStyle(WatchTheme.ink.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    MentorTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
