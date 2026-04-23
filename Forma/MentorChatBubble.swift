import SwiftUI

struct MentorChatBubble: View {
    let mentorName: String
    var isAI: Bool = false
    let messages: [AccountabilityDashboard.Message]
    @Binding var messageText: String
    var inlineError: String? = nil
    var currentUserId: String? = nil
    let onSend: () -> Void
    let onClose: () -> Void
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — green theme
            HStack {
                if let onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Shrink chat" : "Expand chat")
                }
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(mentorName)
                            .font(.system(size: 13, weight: .semibold))
                        if isAI {
                            MentorAIBadge()
                        }
                    }
                    Text(isAI ? "AI mentor — here to keep you on track" : "Your mentor")
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

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text("Say hi to your mentor!")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        ForEach(messages) { msg in
                            ChatMessageRow(message: msg, isFromCurrentUser: isFromCurrentUser(msg))
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: messages.count) { _, _ in
                    if let newest = messages.first {
                        withAnimation {
                            proxy.scrollTo(newest.id, anchor: .top)
                        }
                    }
                }
            }

            Divider()

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }

            // Input row
            HStack(spacing: 8) {
                TextField("Message...", text: $messageText, axis: isExpanded ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: isExpanded ? 14 : 12))
                    .lineLimit(isExpanded ? 1...5 : 1...1)
                    .focused($inputFocused)
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : Color.green
                        )
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    lineWidth: 0.5
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                inputFocused = true
            }
        }
    }

    private func isFromCurrentUser(_ message: AccountabilityDashboard.Message) -> Bool {
        guard let currentUserId else { return false }
        return String(message.senderId) == currentUserId
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.15, blue: 0.12)
            : Color(red: 0.94, green: 0.98, blue: 0.95)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.12, blue: 0.10)
            : Color.white
    }
}

/// Subtle pill badge marking the mentor as AI. Tinted with the app accent so
/// it reads as part of the chrome rather than a system warning.
private struct MentorAIBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .semibold))
            Text("AI")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.92 : 0.85))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.32 : 0.22),
                    lineWidth: 0.5
                )
        )
        .accessibilityLabel("AI mentor")
    }
}
