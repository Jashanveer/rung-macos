import SwiftUI

struct MentorChatBubble: View {
    let mentorName: String
    /// Already sorted chronologically (oldest → newest) by HabitBackendStore.
    let messages: [AccountabilityDashboard.Message]
    /// True while we're waiting on the AI mentor's reply. Renders a
    /// three-dot typing bubble below the last message so the user gets
    /// immediate feedback during the Gemini round-trip.
    var isMentorTyping: Bool = false
    @Binding var messageText: String
    /// Surfaced just above the input row when the send flow can't proceed
    /// (e.g. AI mentor match not yet created) or when the backend returned
    /// a recoverable error. nil hides the row.
    var inlineError: String? = nil
    var currentUserId: String? = nil
    /// Messages the user wrote while offline, in submission order.
    /// Rendered above the server transcript with a "queued" pill so
    /// the user can see what's waiting to send. Empty when there's
    /// nothing in the outbox for this match.
    var queuedMessages: [OutboundMentorMessage] = []
    let onSend: () -> Void
    let onClose: () -> Void
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var inputFocused: Bool

    // Sentinel placed at the BOTTOM of the scroll contents. Standard
    // messaging UX (iMessage / WhatsApp / Slack) keeps the latest
    // message at the bottom of the thread and lands the user there on
    // open — that's what users expect, and what the previous
    // newest-on-top inversion was breaking.
    private let bottomAnchorID = "chat-bottom-anchor"

    /// Chronological display order — oldest at top, newest at bottom.
    /// The auto-scroll anchor below pins the viewport to the latest
    /// message so the user always lands on the newest content even
    /// when they have hundreds of messages of history.
    private var displayMessages: [AccountabilityDashboard.Message] {
        messages
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — green theme
            HStack {
                if let onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Shrink chat" : "Expand chat")
                }
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mentorName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
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

            // Messages — rendered chronologically (oldest top, newest
            // bottom) to match every standard messaging surface the
            // user already knows. The auto-scroll target is a 1pt
            // sentinel pinned BELOW the typing indicator so the
            // viewport always lands on the freshest content on open
            // and on every new message.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty && !isMentorTyping && queuedMessages.isEmpty {
                            Text("Say hi to your mentor!")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        ForEach(displayMessages) { msg in
                            ChatMessageRow(message: msg, isFromCurrentUser: isFromCurrentUser(msg))
                                .id(msg.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // Outbox queue — pending sends sit just below
                        // the server transcript and above the typing
                        // indicator so the user reads them in send
                        // order. Submission order is already
                        // chronological so no reverse is needed.
                        ForEach(queuedMessages) { entry in
                            QueuedMessageRow(message: entry)
                                .id(entry.id)
                                .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
                        }

                        if isMentorTyping {
                            TypingIndicatorRow(mentorName: mentorName)
                                .id("typing-indicator")
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // Bottom sentinel — the universal scroll
                        // target. Sits below everything so .bottom
                        // anchoring always pins the latest content
                        // into view.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: messages.count)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: isMentorTyping) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onAppear {
                    // Two-pass scroll: an immediate non-animated jump
                    // pins the viewport before the cells render, then
                    // a follow-up animated pass settles to the exact
                    // bottom once the LazyVStack has measured its
                    // final size. Without the second pass the chat
                    // can land 1-2 messages above the actual newest.
                    scrollToBottom(proxy: proxy, animated: false)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        scrollToBottom(proxy: proxy, animated: false)
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
                TextField("Message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    .keyboardType(.default)
                    .autocorrectionDisabled(false)
                    #endif
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
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
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = true }
        }
        .onAppear {
            // Pop the keyboard on the next runloop so the bubble's transition
            // has settled before the responder changes. A longer delay lets
            // iOS surface the keyboard even when the bubble opens mid-spring.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                inputFocused = true
            }
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
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        // Always anchor on the bottom sentinel so the viewport lands
        // on the freshest content regardless of whether the typing
        // indicator is up. `.bottom` anchor pins the sentinel to the
        // bottom of the visible viewport, which is what users expect.
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private var subtitleText: String {
        if isMentorTyping { return "typing…" }
        return "Your mentor"
    }

    private func isFromCurrentUser(_ message: AccountabilityDashboard.Message) -> Bool {
        guard let currentUserId else { return false }
        return String(message.senderId) == currentUserId
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.32, blue: 0.18)
            : Color(red: 0.83, green: 0.95, blue: 0.86)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.13, blue: 0.09)
            : Color(red: 0.98, green: 1.00, blue: 0.98)
    }
}

/// Left-aligned "mentor is typing…" bubble with three pulsing dots. Rendered
/// inside the chat list so it sits exactly where the next mentor reply will
/// appear — makes the transition feel continuous.
private struct TypingIndicatorRow: View {
    let mentorName: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mentorName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.secondary.opacity(phase == i ? 0.85 : 0.35))
                            .frame(width: 6, height: 6)
                            .scaleEffect(phase == i ? 1.15 : 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.easeInOut(duration: 0.45), value: phase)
            }

            Spacer(minLength: 40)
        }
        .task(id: "typing-loop") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(360))
                if Task.isCancelled { break }
                await MainActor.run { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Mentor is typing")
    }

    private var bubbleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }
}

/// Queued chat row — the user wrote this offline, the outbox holds
/// it, and a clock-pill says "queued · will send when online" so the
/// user knows their message wasn't lost. Mirrors the right-aligned
/// `ChatMessageRow` "from current user" layout for visual continuity.
private struct QueuedMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: OutboundMentorMessage

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("queued · will send when online")
                        .font(.system(size: 9.5, weight: .medium))
                        .tracking(0.3)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var bubbleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }
}

