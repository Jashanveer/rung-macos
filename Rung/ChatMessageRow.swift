import SwiftUI

struct ChatMessageRow: View {
    let message: AccountabilityDashboard.Message
    var isFromCurrentUser: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 40) }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if isFromCurrentUser, let timeLabel { timeText(timeLabel) }
                    Text(message.senderName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !isFromCurrentUser, let timeLabel { timeText(timeLabel) }
                }

                Text(Self.humanize(message.message))
                    .font(.system(size: 12))
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(messageBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if message.nudge {
                    Label("Nudge", systemImage: "hand.wave.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            if !isFromCurrentUser { Spacer(minLength: 40) }
        }
    }

    /// "9:47 AM" today, "Yesterday 9:47 AM" yesterday, "Mon 9:47 AM"
    /// within the past week, full date otherwise. Returns nil when the
    /// server timestamp is malformed so the caller hides the slot
    /// rather than rendering a broken value.
    private var timeLabel: String? {
        guard let date = Self.parseISO(message.createdAt) else { return nil }
        return Self.timestamp(for: date, now: Date())
    }

    @ViewBuilder
    private func timeText(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.2)
            .foregroundStyle(.secondary)
    }

    private var messageBubbleColor: Color {
        if isFromCurrentUser {
            return Color(red: 0.20, green: 0.62, blue: 0.36)
        }
        return colorScheme == .dark
            ? Color.green.opacity(0.16)
            : Color(red: 0.88, green: 0.96, blue: 0.90)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserFallback: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    static func parseISO(_ raw: String) -> Date? {
        isoParser.date(from: raw) ?? isoParserFallback.date(from: raw)
    }

    /// Localised, day-aware timestamp. Today shows just the time;
    /// yesterday prefixes "Yesterday"; within the week shows the
    /// abbreviated weekday; older falls back to full date+time. Uses
    /// the user's locale so the AM/PM vs 24h split matches the system
    /// settings.
    static func timestamp(for date: Date, now: Date) -> String {
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.locale = .autoupdatingCurrent
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        let timeStr = timeFmt.string(from: date)
        if cal.isDateInToday(date)     { return timeStr }
        if cal.isDateInYesterday(date) { return "Yesterday \(timeStr)" }
        let dayDelta = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if dayDelta < 7 {
            let weekday = DateFormatter()
            weekday.locale = .autoupdatingCurrent
            weekday.dateFormat = "EEE"
            return "\(weekday.string(from: date)) \(timeStr)"
        }
        let dateFmt = DateFormatter()
        dateFmt.locale = .autoupdatingCurrent
        dateFmt.dateStyle = .short
        dateFmt.timeStyle = .short
        return dateFmt.string(from: date)
    }

    /// Strip common Markdown markers from chat content so the bubble reads as
    /// natural prose. Plain `Text` doesn't render Markdown, so without this
    /// asterisks and hashes leak through verbatim ("**One tiny move:**").
    private static func humanize(_ raw: String) -> String {
        var s = raw
        // Bold / italic emphasis — handle paired markers, longest first so
        // double markers don't get half-stripped by the single-marker pass.
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,     with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\*\w])\*([^\*\n]+?)\*(?![\*\w])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![_\w])_([^_\n]+?)_(?![_\w])"#,     with: "$1", options: .regularExpression)
        // Inline code → plain text.
        s = s.replacingOccurrences(of: #"`([^`\n]+?)`"#, with: "$1", options: .regularExpression)
        // ATX heading markers at line start.
        s = s.replacingOccurrences(of: #"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#, with: "", options: .regularExpression)
        // Collapse runs of 3+ newlines to a single blank line.
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
