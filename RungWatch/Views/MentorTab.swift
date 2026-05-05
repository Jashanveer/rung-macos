import SwiftUI

/// Mentor tab — Bruce's last 24 hours of messages, **newest first**, with
/// tap-to-expand on every row so the user can read the full body without
/// flipping back to the iPhone. The hero card shows the freshest message;
/// the list under it is the rest of the day in reverse-chronological order
/// (matches iMessage / Slack / every chat surface the user already knows).
struct MentorTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    /// Track which message rows the user expanded so the body shows in
    /// full. Keyed by `messageId` so the toggle survives across snapshot
    /// pushes — the iPhone re-sends the list on every habit change.
    @State private var expanded: Set<String> = []

    /// Filter to messages from the last 24 hours and sort newest-first.
    /// `sentAt` is optional on the snapshot for backwards-compat — if it
    /// arrives nil we keep the message (server is the source of truth)
    /// and sort it to the bottom of the bucket.
    private var recentMessages: [WatchSnapshot.WatchMentorMessage] {
        let raw = session.snapshot.mentorMessages ?? []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return raw
            .filter { msg in
                guard let date = msg.sentAt else { return true }
                return date >= cutoff
            }
            .sorted { lhs, rhs in
                let l = lhs.sentAt ?? .distantPast
                let r = rhs.sentAt ?? .distantPast
                return l > r
            }
    }

    var body: some View {
        Group {
            if recentMessages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        WatchPageTitle("Mentor", accent: WatchTheme.cAmber)
                        if let latest = recentMessages.first {
                            HeroMessage(
                                message: latest,
                                isExpanded: expanded.contains(latest.messageId),
                                scale: scale
                            ) {
                                toggle(latest.messageId)
                            }
                            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                        }
                        if recentMessages.count > 1 {
                            VStack(spacing: 3) {
                                ForEach(Array(recentMessages.dropFirst())) { msg in
                                    HistoryRow(
                                        message: msg,
                                        isExpanded: expanded.contains(msg.messageId),
                                        scale: scale
                                    ) {
                                        toggle(msg.messageId)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .animation(WatchMotion.snappy, value: recentMessages.count)
                    .animation(WatchMotion.snappy, value: expanded)
                }
            }
        }
        .watchWashBackground(.mint)
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            WatchPageTitle("Mentor", accent: WatchTheme.cAmber)
                .padding(.horizontal, 12)
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22 * scale))
                .foregroundStyle(WatchTheme.inkSoft)
            Text("Quiet last 24h")
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
            Text("Bruce will message\nyou again soon")
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
    let isExpanded: Bool
    let scale: Double
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(message.origin == .me ? AnyShapeStyle(WatchTheme.brandGradient)
                                                      : AnyShapeStyle(WatchTheme.cCyan))
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
                        .foregroundStyle(message.isUnread ? WatchTheme.cAmber : WatchTheme.inkSoft)
                }
                Text(displayedText)
                    .font(WatchTheme.font(.body, scale: scale, weight: .regular))
                    .foregroundStyle(WatchTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if !isExpanded && hasMore {
                    Text("Tap to read")
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(WatchTheme.cCyan)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 14, tint: heroTint, strong: true)
        }
        .buttonStyle(WatchPressStyle(haptic: false))
    }

    /// What goes in the body text — the trimmed preview when collapsed,
    /// the full body (or the preview if no body shipped) when expanded.
    private var displayedText: String {
        if isExpanded {
            return message.body ?? message.preview
        }
        return message.preview
    }

    /// True when the row has more text than the preview. Preview is the
    /// 1-line summary the iPhone trims to ~64 chars; if `body` is longer
    /// we surface the "Tap to read" hint.
    private var hasMore: Bool {
        guard let body = message.body, !body.isEmpty else { return false }
        return body.count > message.preview.count
    }

    /// Tint glass with the message origin so the hero card colors itself
    /// naturally — mentor unreads in amber, sent messages in cyan, idle
    /// reads pick up the ambient mint wash with no extra hue.
    private var heroTint: Color? {
        if message.isUnread && message.origin == .mentor { return WatchTheme.cAmber }
        if message.origin == .me { return WatchTheme.cCyan }
        return nil
    }
}

// MARK: - History row (older messages, compact, tap to expand)

private struct HistoryRow: View {
    let message: WatchSnapshot.WatchMentorMessage
    let isExpanded: Bool
    let scale: Double
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 7) {
                Text(message.origin == .me ? "you" : message.senderName)
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(message.origin == .me ? WatchTheme.cCyan : WatchTheme.cAmber)
                    .frame(width: 38, alignment: .leading)
                Text(displayedText)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .regular))
                    .foregroundStyle(WatchTheme.ink.opacity(0.85))
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: isExpanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(WatchPressStyle(haptic: false))
    }

    private var displayedText: String {
        if isExpanded {
            return message.body ?? message.preview
        }
        return message.preview
    }
}

#if DEBUG
#Preview {
    MentorTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
