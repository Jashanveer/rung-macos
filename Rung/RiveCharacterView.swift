import AVFoundation
import SwiftUI

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
    @State private var inlineChatError: String? = nil

    private let characterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    private var mentorName: String {
        backend.dashboard?.match?.mentor.displayName ?? ""
    }

    private var messages: [AccountabilityDashboard.Message] {
        backend.messages(matchID: backend.dashboard?.match?.id)
    }

    private var hasMatch: Bool {
        backend.dashboard?.match?.id != nil
    }

    private let collapsedBubbleHeight: CGFloat = 300
    private let collapsedBubbleWidth: CGFloat = 280
    private let expandedBubbleHeight: CGFloat = 720
    private let expandedBubbleWidth: CGFloat = 760
    private let bubbleGap: CGFloat = 8
    private let nudgeBubbleWidth: CGFloat = 180

    var body: some View {
        GeometryReader { geo in
            // Expanded bubble grows to fill most of the window so long mentor
            // messages are readable without scrolling. Clamped to the available
            // geometry so we never overflow the scaffold.
            let bubbleWidth: CGFloat = chatExpanded
                ? max(collapsedBubbleWidth, min(expandedBubbleWidth, geo.size.width - 48))
                : collapsedBubbleWidth
            let bubbleHeight: CGFloat = chatExpanded
                ? max(collapsedBubbleHeight, min(expandedBubbleHeight, geo.size.height - characterHeight - bubbleGap - 24))
                : collapsedBubbleHeight

            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            // The character is positioned with its frame bottom at
            // `geo.size.height + characterHeight*0.15` (15% off-screen), so the
            // visible character frame top sits `characterHeight * 0.85` pixels
            // above the view bottom. The +0.08 buffer keeps the bubble clear of
            // the top of Bruce's head.
            let visibleCharTop = characterHeight * 0.93

            LoopingVideoView(
                videoName: "walk-bruce-01",
                isPlaying: walker.isWalking,
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
                    y: geo.size.height - characterHeight / 2 + characterHeight * 0.15
                )

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

            // Chat bubble — positioned just above the character's head
            if chatOpen {
                let bubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
                let bubbleCenterX = characterHeadX
                let clampedX = clamped(bubbleCenterX, lowerBound: bubbleWidth / 2 + 8, upperBound: geo.size.width - bubbleWidth / 2 - 8)
                let anchorX = (bubbleCenterX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(x: clamped(anchorX, lowerBound: 0, upperBound: 1), y: 1)

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
                    isExpanded: chatExpanded,
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
                .zIndex(10)
            }

            if let text = visibleNudge {
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
        .frame(height: chatOpen
               ? characterHeight + (chatExpanded ? expandedBubbleHeight : collapsedBubbleHeight) + bubbleGap
               : characterHeight)
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

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            chatOpen = true
        }

        Task {
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
            }
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let matchID = backend.dashboard?.match?.id {
            messageText = ""
            inlineChatError = nil
            Task {
                await backend.sendMenteeMessage(matchId: matchID, message: text)
                if case .failure(let message) = backend.messageRequestState {
                    inlineChatError = message
                }
            }
            return
        }

        // Match not loaded yet — bypass the in-memory dashboard cache and
        // force a fresh fetch so a newly-seeded AI mentor match is picked up.
        // If the backend still has no match after the refresh, surface the
        // error inline instead of silently dropping the message.
        inlineChatError = "Connecting to your mentor…"
        Task {
            await backend.responseCache.invalidateDashboard()
            await backend.refreshDashboard()
            guard let matchID = backend.dashboard?.match?.id else {
                inlineChatError = "No mentor match yet. Sign out and back in to trigger an AI mentor assignment."
                return
            }
            messageText = ""
            inlineChatError = nil
            await backend.sendMenteeMessage(matchId: matchID, message: text)
            if case .failure(let message) = backend.messageRequestState {
                inlineChatError = message
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

    private let characterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    /// The friend whose stats we surface on the orange character.
    ///
    /// Product rule: show the top leaderboard friend so the user sees who
    /// they're chasing. Falls back to the social feed (what the user sees
    /// in the leaderboard pill) when the weekly challenge leaderboard is
    /// empty, so the rival stays in sync with what the user actually sees
    /// on-screen.
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

    private let bubbleHeight: CGFloat = 252
    private let bubbleWidth: CGFloat = 260
    private let bubbleGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            let visibleCharTop = characterHeight * 0.55

            // Jazz — the orange lil-agent character
            LoopingVideoView(
                videoName: "walk-jazz-01",
                isPlaying: walker.isWalking,
                startOffset: walker.videoWalkStartOffset
            )
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
                .contentShape(Rectangle())
                .onTapGesture { toggleChat() }
                .position(
                    x: charX + charWidth / 2,
                    y: geo.size.height - characterHeight / 2 + characterHeight * 0.15
                )

            // Chat bubble anchored above the character's head
            if chatOpen {
                let bubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
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
                }
                .onChange(of: geo.size.width) { _, _ in
                    walker.travelDistance = travelDistance
                }
        }
        .frame(height: chatOpen ? characterHeight + bubbleHeight + bubbleGap : characterHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
    }

    private func toggleChat() { chatOpen ? closeChat() : openChat() }

    private func openChat() {
        chatAnimationTask?.cancel()
        chatShown = false
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
            }
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}

