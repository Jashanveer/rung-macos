import SwiftUI

/// Tab 6 — recent mentor conversation. Shows the last few messages between
/// the user and their mentor as compact bubbles, oldest at the top so the
/// freshest reply lands at the bottom of the visible region (matches iMessage
/// reading order). Read-only — replies happen on the iPhone or Mac.
struct MentorTab: View {
    @EnvironmentObject private var session: WatchSession

    private var messages: [WatchSnapshot.WatchMentorMessage] {
        session.snapshot.mentorMessages ?? []
    }

    private var unreadCount: Int {
        messages.filter { $0.isUnread }.count
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
        }
        .watchPageHeader(
            "MENTOR",
            accent: WatchTheme.accent,
            trailing: unreadCount > 0 ? "\(unreadCount) NEW" : nil
        )
        .containerBackground(WatchTheme.bg.gradient, for: .tabView)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("\u{1F4AC}")
                .font(.system(size: 22))
            Text("No messages yet")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
            Text("Reply from your iPhone\nto start the thread.")
                .font(.system(size: 8.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: WatchSnapshot.WatchMentorMessage

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            if message.origin == .mentor {
                avatar
                bubble
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 14)
                bubble
                avatar
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(message.origin == .me ? AnyShapeStyle(WatchTheme.brandGradient)
                                              : AnyShapeStyle(WatchTheme.accent.opacity(0.85)))
            Text(String(message.senderName.prefix(1)).uppercased())
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 14, height: 14)
        .overlay(alignment: .topTrailing) {
            if message.isUnread {
                Circle()
                    .fill(WatchTheme.gold)
                    .frame(width: 4, height: 4)
                    .offset(x: 1, y: -1)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(message.preview)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(message.relativeTime.uppercased())
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(WatchTheme.inkSoft)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: message.origin == .me ? .trailing : .leading)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.origin {
        case .me:
            LinearGradient(
                colors: [WatchTheme.accent.opacity(0.28), WatchTheme.accent.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WatchTheme.accent.opacity(0.35), lineWidth: 0.5)
            )
        case .mentor:
            if message.isUnread {
                LinearGradient(
                    colors: [WatchTheme.gold.opacity(0.18), WatchTheme.gold.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(WatchTheme.gold.opacity(0.4), lineWidth: 0.5)
                )
            } else {
                WatchTheme.glassFill
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(WatchTheme.glassStroke, lineWidth: 0.5)
                    )
            }
        }
    }
}

#Preview {
    MentorTab()
        .environmentObject(WatchSession.shared)
}
