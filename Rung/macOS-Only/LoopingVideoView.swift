import SwiftUI
import AVFoundation

#if os(macOS)
struct LoopingVideoView: NSViewRepresentable {
    let videoName: String
    let isPlaying: Bool
    /// Seconds into the video where playback should begin when `isPlaying`
    /// flips true. The Bruce/Jazz videos have a ~3s standing prefix; seeking
    /// past it keeps the walk animation in sync with the walker's movement
    /// so he doesn't slide before walking.
    var startOffset: Double = 0

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return view
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)

        context.coordinator.player = player
        context.coordinator.looper = looper
        context.coordinator.playerLayer = playerLayer
        context.coordinator.startOffset = startOffset

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.playerLayer?.frame = nsView.bounds
        context.coordinator.startOffset = startOffset
        context.coordinator.apply(isPlaying: isPlaying)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
        var isPlaying: Bool = false
        var startOffset: Double = 0

        /// Only react to actual isPlaying transitions — `updateNSView` fires
        /// on every SwiftUI re-render. Sequencing seek → play inside the
        /// completion handler prevents a race where play() runs before the
        /// seek completes, which is what previously caused Bruce's legs to
        /// still be in the standing pose while his position was already
        /// sliding sideways.
        func apply(isPlaying desired: Bool) {
            guard desired != isPlaying else { return }
            isPlaying = desired
            if desired {
                let time = CMTime(seconds: startOffset, preferredTimescale: 600)
                player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player = player] _ in
                    player?.play()
                }
            } else {
                player?.pause()
                player?.seek(to: .zero)
            }
        }
    }
}
#endif
