import SwiftUI

struct ChatMessageRow: View {
    let message: AccountabilityDashboard.Message
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(message.message)
                    .font(.system(size: 12))
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

            Spacer(minLength: 40)
        }
    }

    private var messageBubbleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }
}
