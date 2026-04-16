import AVFoundation
import SwiftUI

// MARK: - Mentor Character + Chat Bubble

/// A walking mentor character at the bottom of the window with a floating chat bubble.
struct MentorCharacterView: View {
    @ObservedObject var backend: HabitBackendStore
    @State private var walker = WalkerState()
    @State private var chatOpen = false
    @State private var messageText = ""
    @State private var hasUnread = false

    private let characterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    private var mentorName: String {
        backend.dashboard?.match?.mentor.displayName ?? "Mentor"
    }

    private var messages: [AccountabilityDashboard.Message] {
        backend.dashboard?.menteeDashboard.messages ?? []
    }

    private let bubbleHeight: CGFloat = 300
    private let bubbleWidth: CGFloat = 280
    private let bubbleGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            // The visible character occupies ~85% of the frame (bottom 15% is ground offset)
            let visibleCharTop = characterHeight * 0.85

            // Character
            LoopingVideoView(videoName: "walk-bruce-01", isPlaying: walker.isWalking)
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
                .position(
                    x: charX + charWidth / 2,
                    y: geo.size.height - characterHeight / 2 + characterHeight * 0.15
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        chatOpen.toggle()
                        if chatOpen { hasUnread = false }
                    }
                }

            // Unread indicator
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
                let bubbleCenterX = charX + charWidth / 2
                let clampedX = min(max(bubbleCenterX, bubbleWidth / 2 + 8), geo.size.width - bubbleWidth / 2 - 8)
                // Anchor point so the bubble scales from the character's head
                let anchorX = (bubbleCenterX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(x: min(max(anchorX, 0), 1), y: 1)

                MentorChatBubble(
                    mentorName: mentorName,
                    messages: messages,
                    messageText: $messageText,
                    onSend: sendMessage,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            chatOpen = false
                        }
                    }
                )
                .frame(width: bubbleWidth, height: bubbleHeight)
                .position(x: clampedX, y: bubbleY)
                .transition(.scale(scale: 0.3, anchor: scaleAnchor).combined(with: .opacity))
                .zIndex(10)
            }

            Color.clear
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
        }
        .frame(height: chatOpen ? characterHeight + bubbleHeight + bubbleGap : characterHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
    }

    private func clampBubbleX(charX: CGFloat, bubbleWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let idealX = charX - bubbleWidth / 2
        let minX: CGFloat = 8
        let maxX = containerWidth - bubbleWidth - 8
        return min(max(idealX, minX), maxX)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        // TODO: Wire to backend send-message API when available
        // For now this clears the field; the mentor's replies come via dashboard refresh
        Task {
            await backend.refreshDashboard()
        }
    }
}

// MARK: - Chat Bubble View

private struct MentorChatBubble: View {
    let mentorName: String
    let messages: [AccountabilityDashboard.Message]
    @Binding var messageText: String
    let onSend: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(mentorName)
                    .font(.system(size: 13, weight: .semibold))
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
                            ChatMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
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
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08),
                    lineWidth: 0.5
                )
        )
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.17)
            : Color(red: 0.96, green: 0.96, blue: 0.98)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.14)
            : Color.white
    }
}

private struct ChatMessageRow: View {
    let message: AccountabilityDashboard.Message
    @Environment(\.colorScheme) private var colorScheme

    // Messages from the mentor (senderId != current user) appear on the left
    // For simplicity, assume nudge messages and named senders are from the mentor
    private var isFromMentor: Bool { true }

    var body: some View {
        HStack {
            if !isFromMentor { Spacer(minLength: 40) }

            VStack(alignment: isFromMentor ? .leading : .trailing, spacing: 2) {
                if isFromMentor {
                    Text(message.senderName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

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

            if isFromMentor { Spacer(minLength: 40) }
        }
    }

    private var messageBubbleColor: Color {
        if isFromMentor {
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color(red: 0.93, green: 0.93, blue: 0.95)
        } else {
            return Color.blue.opacity(0.85)
        }
    }
}

// MARK: - Walk State Machine

@Observable
class WalkerState {
    var positionProgress: CGFloat = 0.3
    var goingRight = true
    var isWalking = false
    var travelDistance: CGFloat = 500

    // Video timing (from lil-agents frame analysis for Bruce)
    private let videoDuration: CFTimeInterval = 10.0
    private let accelStart: CFTimeInterval = 3.0
    private let fullSpeedStart: CFTimeInterval = 3.75
    private let decelStart: CFTimeInterval = 8.0
    private let walkStop: CFTimeInterval = 8.5

    private var walkStartTime: CFTimeInterval = 0
    private var walkStartPos: CGFloat = 0
    private var walkEndPos: CGFloat = 0
    private var frameTimer: Timer?

    func start() {
        enterPause()
    }

    private func enterPause() {
        isWalking = false
        let delay = Double.random(in: 3.0...8.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startWalk()
        }
    }

    private func startWalk() {
        if positionProgress > 0.85 {
            goingRight = false
        } else if positionProgress < 0.15 {
            goingRight = true
        } else {
            goingRight = Bool.random()
        }

        walkStartPos = positionProgress

        let referenceWidth: CGFloat = 500
        let walkPixels = CGFloat.random(in: 0.25...0.5) * referenceWidth
        let walkAmount = travelDistance > 0 ? walkPixels / travelDistance : 0.3

        if goingRight {
            walkEndPos = min(walkStartPos + walkAmount, 1.0)
        } else {
            walkEndPos = max(walkStartPos - walkAmount, 0.0)
        }

        isWalking = true
        walkStartTime = CACurrentMediaTime()

        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - walkStartTime

        if elapsed >= videoDuration {
            frameTimer?.invalidate()
            frameTimer = nil
            positionProgress = walkEndPos
            enterPause()
            return
        }

        let walkNorm = movementPosition(at: elapsed)
        positionProgress = walkStartPos + (walkEndPos - walkStartPos) * walkNorm
    }

    private func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart

        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= accelStart {
            return 0.0
        } else if videoTime <= fullSpeedStart {
            let t = videoTime - accelStart
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if videoTime <= decelStart {
            let easeInDist = v * dIn / 2.0
            let t = videoTime - fullSpeedStart
            return CGFloat(easeInDist + v * t)
        } else if videoTime <= walkStop {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let t = videoTime - decelStart
            return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }
}

// MARK: - Looping Video Player (NSViewRepresentable)

#if os(macOS)
private struct LoopingVideoView: NSViewRepresentable {
    let videoName: String
    let isPlaying: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return view
        }

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        view.layer?.addSublayer(playerLayer)

        context.coordinator.player = player
        context.coordinator.looper = looper
        context.coordinator.playerLayer = playerLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.playerLayer?.frame = nsView.bounds

        if isPlaying {
            context.coordinator.player?.play()
        } else {
            context.coordinator.player?.pause()
            context.coordinator.player?.seek(to: .zero)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
    }
}
#endif
