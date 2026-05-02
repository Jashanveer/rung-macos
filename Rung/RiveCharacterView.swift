import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Mentor Character + Chat Bubble

/// A walking mentor character at the bottom of the window with a floating chat bubble.
struct MentorCharacterView: View {
    @ObservedObject var backend: HabitBackendStore
    @Binding var nudge: String?
    @State private var walker = WalkerState()
    @State private var chatOpen = false
    @State private var chatShown = false
    @State private var chatExpanded = false
    @State private var chatAnimationTask: Task<Void, Never>? = nil
    @State private var messageText = ""
    @State private var hasUnread = false
    @State private var visibleNudge: String? = nil
    @State private var nudgeShown = false
    @State private var nudgeDismissTask: Task<Void, Never>? = nil
    @State private var isSending = false
    @State private var inlineChatError: String? = nil
    // Keyboard height in screen coordinates. Used to lift the whole mentor
    // block (character + bubble) above the on-screen keyboard while the chat
    // is open. `.ignoresSafeArea(.keyboard)` keeps SwiftUI's automatic
    // avoidance from interfering, so we apply the offset manually.
    @State private var keyboardHeight: CGFloat = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let baseCharacterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    /// Bruce's .mov has ~12pt of transparent footer within each 130pt frame.
    /// Sinking the frame's center by this fraction (~12/130) places the
    /// visible feet exactly on the scaffold's bottom edge.
    private var verticalSinkFraction: CGFloat {
        #if os(iOS)
        if horizontalSizeClass == .compact { return 0.15 }
        return 0.35
        #else
        return 0.35
        #endif
    }

    private var mentorName: String {
        "Bruce"
    }

    private var messages: [AccountabilityDashboard.Message] {
        backend.messages(matchID: backend.dashboard?.match?.id)
    }

    private let baseBubbleHeight: CGFloat = 300
    private let baseBubbleWidth: CGFloat = 280
    private let bubbleGap: CGFloat = 8
    private let baseNudgeBubbleWidth: CGFloat = 180

    var body: some View {
        // When the keyboard is up with the chat open, we stop trying to anchor
        // the bubble to the character — the character is hidden, and the bubble
        // expands to fill the area above the keyboard. This avoids the
        // keyboard-covers-input problem on both iPhone and iPad.
        let keyboardExpanded = chatOpen && keyboardHeight > 0
        // Manual expand toggle (top-left chevron in the chat title bar) puts
        // the bubble in the same large layout used for the keyboard, but
        // without requiring the input field to be focused. Long mentor messages
        // are unreadable in the compact 300pt bubble.
        let largeMode = chatOpen && (keyboardExpanded || chatExpanded)

        GeometryReader { geo in
            // iPhone (~390pt) shrinks character + bubble; iPad/Mac keeps original sizes.
            let narrow = geo.size.width < 500
            let characterHeight: CGFloat = narrow ? 108 : baseCharacterHeight
            let compactBubbleWidth: CGFloat = min(baseBubbleWidth, geo.size.width - 24)
            let compactBubbleHeight: CGFloat = narrow ? 260 : baseBubbleHeight
            let nudgeBubbleWidth: CGFloat = min(baseNudgeBubbleWidth, geo.size.width - 40)

            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            // Tuned so the bubble sits just above the visible character head,
            // not above the frame's empty top padding.
            let visibleCharTop = characterHeight * 0.55

            // Where the keyboard top sits inside our local coord space. When
            // the parent applies `.ignoresSafeArea(.keyboard)`, geo.size.height
            // spans the whole scaffold so this math is valid screen-wide.
            let keyboardTopLocal = max(0, geo.size.height - keyboardHeight)

            // In large mode (keyboard up OR manual expand), the bubble fills
            // most of the space above the keyboard / above the character.
            // In compact mode, it keeps the old size/anchor.
            let largeBottomBound = keyboardExpanded ? keyboardTopLocal : geo.size.height - 24
            let bubbleWidth: CGFloat = largeMode
                ? min(geo.size.width - 32, 640)
                : compactBubbleWidth
            let bubbleHeight: CGFloat = largeMode
                ? max(220, min(largeBottomBound - 32, 720))
                : compactBubbleHeight

            LoopingVideoView(
                videoName: "walk-bruce-01",
                isPlaying: walker.isWalking && !chatOpen,
                startOffset: walker.videoWalkStartOffset
            )
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleChat()
                }
                .position(
                    x: charX + charWidth / 2,
                    y: geo.size.height - characterHeight / 2 + characterHeight * verticalSinkFraction
                )
                .opacity(largeMode ? 0 : 1)
                .allowsHitTesting(!largeMode)

            if hasUnread && !chatOpen {
                Circle()
                    .fill(.red)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Text("\(messages.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .position(
                        x: charX + charWidth - 4,
                        y: geo.size.height - visibleCharTop - 4
                    )
            }

            // Chat bubble — compact mode anchors just above the character's
            // head; expanded mode (keyboard up) centres the bubble in the
            // free space above the keyboard and ignores the character's
            // location entirely.
            if chatOpen {
                let rawBubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
                let compactNarrowY = max(bubbleHeight / 2 + 12, min(rawBubbleY, geo.size.height * 0.36))
                let compactY = narrow ? compactNarrowY : rawBubbleY
                let expandedY = max(bubbleHeight / 2 + 16, largeBottomBound / 2)
                let bubbleY = largeMode ? expandedY : compactY

                let bubbleCenterX = largeMode ? geo.size.width / 2 : characterHeadX
                let clampedX = clamped(bubbleCenterX, lowerBound: bubbleWidth / 2 + 8, upperBound: geo.size.width - bubbleWidth / 2 - 8)
                let anchorX = (bubbleCenterX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(
                    x: clamped(anchorX, lowerBound: 0, upperBound: 1),
                    y: largeMode ? 0.5 : 1
                )

                MentorChatBubble(
                    mentorName: mentorName,
                    // Default to true: the only mentor flow this app ships
                    // today is the AI mentor (Bruce). Without the default,
                    // the chat header reads "Your mentor" during the brief
                    // window between opening the bubble and the dashboard
                    // refresh landing the match — which is misleading since
                    // there's no human-mentor variant to disambiguate from.
                    isAI: backend.dashboard?.match?.aiMentor ?? true,
                    messages: messages,
                    isMentorTyping: (backend.dashboard?.match?.aiMentor ?? true) && backend.aiMentorTyping,
                    messageText: $messageText,
                    inlineError: inlineChatError,
                    currentUserId: backend.currentUserId,
                    onSend: sendMessage,
                    onClose: {
                        closeChat()
                    },
                    isExpanded: largeMode,
                    onToggleExpand: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            chatExpanded.toggle()
                        }
                    }
                )
                .frame(width: bubbleWidth, height: bubbleHeight)
                .scaleEffect(chatShown ? 1 : 0.05, anchor: scaleAnchor)
                .opacity(chatShown ? 1 : 0)
                .position(x: clampedX, y: bubbleY)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: chatShown)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: chatExpanded)
                .animation(.easeOut(duration: 0.25), value: keyboardHeight)
                .zIndex(10)
            }

            if let text = visibleNudge, !largeMode {
                let nudgeCenterX = clamped(
                    characterHeadX,
                    lowerBound: nudgeBubbleWidth / 2 + 8,
                    upperBound: geo.size.width - nudgeBubbleWidth / 2 - 8
                )
                let nudgeAnchorX = (characterHeadX - (nudgeCenterX - nudgeBubbleWidth / 2)) / nudgeBubbleWidth
                let clampedNudgeAnchorX = clamped(nudgeAnchorX, lowerBound: 0, upperBound: 1)
                let nudgeAnchor = UnitPoint(x: clampedNudgeAnchorX, y: 1)
                let nudgeBubbleY = geo.size.height - visibleCharTop - bubbleGap - 22

                SpeechBubbleNudge(text: text, width: nudgeBubbleWidth, tailAnchorX: clampedNudgeAnchorX)
                    .scaleEffect(nudgeShown ? 1 : 0.01, anchor: nudgeAnchor)
                    .opacity(nudgeShown ? 1 : 0)
                    .position(x: nudgeCenterX, y: nudgeBubbleY)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: nudgeShown)
                    .zIndex(11)
                    .allowsHitTesting(false)
            }

            Color.clear
                .allowsHitTesting(false)
                .onAppear {
                    walker.travelDistance = travelDistance
                    walker.start()
                }
                .onChange(of: geo.size.width) { _, _ in
                    walker.travelDistance = travelDistance
                }
                .onChange(of: messages.count) { old, new in
                    if new > old && !chatOpen {
                        hasUnread = true
                    }
                }
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard
                        let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    else { return }
                    let screenH = UIScreen.main.bounds.height
                    // Keyboard height above the screen edge; 0 when dismissed.
                    keyboardHeight = max(0, screenH - frame.origin.y)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardHeight = 0
                }
                #endif
                .onChange(of: nudge) { _, newValue in
                    guard let msg = newValue else { return }
                    nudgeDismissTask?.cancel()
                    nudge = nil
                    visibleNudge = msg
                    nudgeShown = false
                    DispatchQueue.main.async {
                        nudgeShown = true
                    }
                    nudgeDismissTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            nudgeShown = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                visibleNudge = nil
                            }
                        }
                    }
                }
        }
        // In large mode (keyboard up OR manual expand) the view grows to fill
        // the scaffold so the bubble has room to render. In compact mode it
        // keeps the old footprint (character or character + short bubble stack).
        .frame(
            height: largeMode
                ? nil
                : (chatOpen ? baseCharacterHeight + baseBubbleHeight + bubbleGap : baseCharacterHeight)
        )
        .frame(maxHeight: largeMode ? .infinity : nil, alignment: .bottom)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: chatExpanded)
    }

    private func toggleChat() {
        if chatOpen {
            closeChat()
        } else {
            openChat()
        }
    }

    private func openChat() {
        chatAnimationTask?.cancel()
        hasUnread = false
        chatShown = false
        chatExpanded = false
        // Freeze the walker so it doesn't advance in the background while the
        // chat is open. Without this, `positionProgress` keeps ticking and the
        // character teleports to the new spot when the bubble dismisses.
        walker.pause()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            chatOpen = true
        }

        Task {
            // Ensure Bruce (the AI mentor match) exists before the user can
            // type. The backend's /dashboard endpoint auto-creates the AI
            // mentor match on first call for any account — so a fresh pull
            // is the right primitive when we open the chat cold.
            if backend.dashboard?.match?.id == nil {
                await backend.responseCache.invalidateDashboard()
                await backend.refreshDashboard()
            }
            await backend.markMatchRead(matchID: backend.dashboard?.match?.id)
        }

        chatAnimationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    chatShown = true
                }
            }
        }
    }

    private func closeChat() {
        chatAnimationTask?.cancel()

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            chatShown = false
        }

        chatAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    chatOpen = false
                }
                walker.resume()
            }
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        if let matchID = backend.dashboard?.match?.id {
            isSending = true
            messageText = ""
            inlineChatError = nil
            Task {
                defer { Task { @MainActor in isSending = false } }
                await backend.sendMenteeMessage(matchId: matchID, message: text)
                if case .failure(let message) = backend.messageRequestState {
                    await MainActor.run { inlineChatError = message }
                }
            }
            return
        }

        // Match not loaded yet — bypass the in-memory dashboard cache and
        // force a fresh fetch so a newly-seeded AI mentor match is picked up.
        // If the backend still has no match after the refresh, surface the
        // error inline instead of silently restoring the typed text and
        // leaving the user wondering why nothing happened.
        isSending = true
        inlineChatError = "Connecting to your mentor…"
        Task {
            defer { Task { @MainActor in isSending = false } }
            await backend.responseCache.invalidateDashboard()
            await backend.refreshDashboard()
            guard let matchID = backend.dashboard?.match?.id else {
                await MainActor.run {
                    inlineChatError = "No mentor match yet. Sign out and back in to trigger an AI mentor assignment."
                }
                return
            }
            await MainActor.run {
                messageText = ""
                inlineChatError = nil
            }
            await backend.sendMenteeMessage(matchId: matchID, message: text)
            if case .failure(let message) = backend.messageRequestState {
                await MainActor.run { inlineChatError = message }
            }
        }
    }
}

// MARK: - Mentee Character + Chat Bubble

/// A walking mentee character — visually distinct from the mentor (purple tint, offset start).
/// Represents a person the current user is mentoring in the social hub.
struct MenteeCharacterView: View {
    @ObservedObject var backend: HabitBackendStore
    @State private var walker = WalkerState()
    @State private var chatOpen = false
    @State private var chatShown = false
    @State private var chatAnimationTask: Task<Void, Never>? = nil
    @State private var hasAttention = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let baseCharacterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    private var verticalSinkFraction: CGFloat {
        #if os(iOS)
        if horizontalSizeClass == .compact { return 0.15 }
        return 0.35
        #else
        return 0.35
        #endif
    }

    /// The friend whose stats we surface on the orange character.
    ///
    /// Product rule: show the top leaderboard friend so the user sees who
    /// they're chasing. If the current user is already at rank 1, fall back
    /// to rank 2 (the nearest challenger). Falls back to the social feed
    /// (what the user sees in the leaderboard pill) when the weekly challenge
    /// leaderboard is empty, so the rival stays in sync with what the user
    /// actually sees on-screen.
    private var topFriend: TopFriendSnapshot? {
        guard let dashboard = backend.dashboard else { return nil }

        let updates = dashboard.social?.updates ?? []
        let suggestions = dashboard.social?.suggestions ?? []
        let myName = dashboard.profile.displayName

        // Build the same consistency-ranked list the dashboard pill renders so
        // the rival's rank stays in lock-step with what the user sees there.
        // The backend's weekly-challenge leaderboard alone can't be trusted —
        // it sometimes omits the current user (or fails to set `currentUser`),
        // which made jay show up as "Rank #1" even when avneet held the top spot.
        struct Ranked {
            let displayName: String
            let consistency: Int
            let progress: Int
            let isCurrentUser: Bool
        }

        var ranked: [Ranked] = [
            Ranked(
                displayName: myName,
                consistency: dashboard.level.weeklyConsistencyPercent,
                progress: 0,
                isCurrentUser: true
            )
        ]
        ranked.append(contentsOf: updates.map {
            Ranked(
                displayName: $0.displayName,
                consistency: $0.weeklyConsistencyPercent,
                progress: $0.progressPercent,
                isCurrentUser: $0.displayName == myName
            )
        })

        let sorted = ranked.sorted {
            if $0.consistency != $1.consistency {
                return $0.consistency > $1.consistency
            }
            // Tie-break: keep the current user above ties so the rival shown
            // is genuinely ranked behind them, not co-leading.
            if $0.isCurrentUser != $1.isCurrentUser {
                return $0.isCurrentUser
            }
            return $0.displayName < $1.displayName
        }

        guard let rivalIndex = sorted.firstIndex(where: { !$0.isCurrentUser }) else {
            return nil
        }
        let rival = sorted[rivalIndex]
        let rivalRank = rivalIndex + 1

        // "Perfect days" surfaces the rival's year-to-date count. The backend
        // exposes this on `SocialActivity.yearPerfectDays` as of the
        // year-perfect-days API. Older builds (and offline fallbacks) lack
        // the field — for those we extrapolate from 7-day consistency. Floor
        // at 1 if the rival clearly completed today.
        let updateMatch = updates.first { $0.displayName == rival.displayName }
        let suggestionMatch = suggestions.first { $0.displayName == rival.displayName }
        let backendCount = updateMatch?.yearPerfectDays ?? 0
        let perfectDays: Int
        if backendCount > 0 {
            perfectDays = backendCount
        } else {
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
            let estimate = Int((Double(rival.consistency) / 100.0 * Double(dayOfYear)).rounded())
            perfectDays = max(estimate, rival.progress >= 100 ? 1 : 0)
        }

        return TopFriendSnapshot(
            displayName: rival.displayName,
            perfectDays: perfectDays,
            weeklyConsistencyPercent: rival.consistency,
            progressPercent: suggestionMatch?.progressPercent ?? rival.progress,
            rank: rivalRank
        )
    }

    private let baseBubbleHeight: CGFloat = 252
    private let baseBubbleWidth: CGFloat = 260
    private let bubbleGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 500
            let characterHeight: CGFloat = narrow ? 108 : baseCharacterHeight
            let bubbleWidth: CGFloat = min(baseBubbleWidth, geo.size.width - 24)
            let bubbleHeight: CGFloat = narrow ? 224 : baseBubbleHeight

            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            let visibleCharTop = characterHeight * 0.55

            // Jazz — the orange lil-agent character
            LoopingVideoView(
                videoName: "walk-jazz-01",
                isPlaying: walker.isWalking && !chatOpen,
                startOffset: walker.videoWalkStartOffset
            )
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
                .contentShape(Rectangle())
                .onTapGesture { toggleChat() }
                .position(
                    x: charX + charWidth / 2,
                    y: geo.size.height - characterHeight / 2 + characterHeight * verticalSinkFraction
                )

            // Attention badge when mentee missed habits today
            if hasAttention && !chatOpen {
                Circle()
                    .fill(.orange)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                    )
                    .position(
                        x: charX + charWidth - 4,
                        y: geo.size.height - visibleCharTop - 4
                    )
            }

            // Chat bubble anchored above the character's head. On iPhone it
            // stays fixed while open so typing does not make it drift.
            if chatOpen {
                let rawBubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
                let bubbleY = narrow
                    ? max(bubbleHeight / 2 + 12, min(rawBubbleY, geo.size.height * 0.36))
                    : rawBubbleY
                let clampedX = clamped(characterHeadX, lowerBound: bubbleWidth / 2 + 8, upperBound: geo.size.width - bubbleWidth / 2 - 8)
                let anchorX = (characterHeadX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(x: clamped(anchorX, lowerBound: 0, upperBound: 1), y: 1)

                Group {
                    if let topFriend {
                        MenteeChatBubble(friend: topFriend, onClose: closeChat)
                    } else {
                        MenteeEmptyChatBubble(onClose: closeChat)
                    }
                }
                .frame(width: bubbleWidth, height: bubbleHeight)
                .scaleEffect(chatShown ? 1 : 0.05, anchor: scaleAnchor)
                .opacity(chatShown ? 1 : 0)
                .position(x: clampedX, y: bubbleY)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: chatShown)
                .zIndex(10)
            }

            Color.clear
                .allowsHitTesting(false)
                .onAppear {
                    // Start mentee on the right side so they walk toward the mentor
                    walker.positionProgress = 0.7
                    walker.goingRight = false
                    walker.travelDistance = travelDistance
                    walker.start()
                    hasAttention = (topFriend?.progressPercent ?? 100) < 100
                }
                .onChange(of: geo.size.width) { _, _ in
                    walker.travelDistance = travelDistance
                }
                .onChange(of: topFriend?.progressPercent ?? 100) { _, new in
                    if !chatOpen { hasAttention = new < 100 }
                }
        }
        .frame(height: chatOpen ? baseCharacterHeight + baseBubbleHeight + bubbleGap : baseCharacterHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
    }

    private func toggleChat() { chatOpen ? closeChat() : openChat() }

    private func openChat() {
        chatAnimationTask?.cancel()
        hasAttention = false
        chatShown = false
        walker.pause()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { chatOpen = true }
        chatAnimationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { chatShown = true }
            }
        }
    }

    private func closeChat() {
        chatAnimationTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { chatShown = false }
        chatAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { chatOpen = false }
                walker.resume()
            }
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}
