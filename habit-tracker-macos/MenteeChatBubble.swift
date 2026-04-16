import SwiftUI

struct MenteeChatBubble: View {
    let mentee: AccountabilityDashboard.MenteeSummary
    let onSend: (String) -> Void
    let onClose: () -> Void

    @State private var messageText = ""
    @State private var isSending = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — orange accent to match Jazz character
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mentee.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your mentee")
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

            // Mentee stats
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Weekly consistency")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(mentee.weeklyConsistencyPercent)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(consistencyColor)
                }

                HStack {
                    Image(systemName: mentee.missedHabitsToday > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(mentee.missedHabitsToday > 0 ? Color.orange : Color.green)
                        .font(.system(size: 12))
                    Text("Missed today")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mentee.missedHabitsToday == 0
                         ? "All done!"
                         : "\(mentee.missedHabitsToday) habit\(mentee.missedHabitsToday == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mentee.missedHabitsToday > 0 ? Color.orange : Color.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Suggested action", systemImage: "lightbulb.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(mentee.suggestedAction)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(12)

            Divider()

            // Input row
            HStack(spacing: 8) {
                TextField("Cheer them up...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .disabled(isSending)
                    .onSubmit { submitMessage() }

                Button(action: submitMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                                ? Color.secondary : Color.orange
                        )
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

    private func submitMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        messageText = ""
        onSend(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isSending = false }
    }

    private var consistencyColor: Color {
        mentee.weeklyConsistencyPercent >= 70 ? .green
            : mentee.weeklyConsistencyPercent >= 40 ? .orange
            : .red
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
