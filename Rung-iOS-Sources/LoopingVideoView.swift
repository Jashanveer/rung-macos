import SwiftUI
import AVFoundation

#if os(macOS)

struct LoopingVideoView: NSViewRepresentable {
    let videoName: String
    let isPlaying: Bool
    /// Seconds into the video where playback should begin when `isPlaying`
    /// flips true. The Bruce/Jazz videos have a standing prefix; seeking past
    /// it keeps the walk animation in sync with the walker's movement so he
    /// doesn't slide before walking.
    var startOffset: Double = 0

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return view
        }

        let asset = AVURLAsset(url: url)
        let player = AVQueuePlayer()
        let templateItem = AVPlayerItem(asset: asset)
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)

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

    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
        var isPlaying: Bool = false
        var startOffset: Double = 0

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

#elseif os(iOS)

import UIKit

struct LoopingVideoView: UIViewRepresentable {
    let videoName: String
    let isPlaying: Bool
    /// Seconds into the video where playback should begin when `isPlaying`
    /// flips true. The Bruce/Jazz videos have a standing prefix; seeking past
    /// it keeps the walk animation in sync with the walker's movement so he
    /// doesn't slide before walking.
    var startOffset: Double = 0

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear

        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return view
        }

        let asset = AVURLAsset(url: url)
        let player = AVQueuePlayer()
        let templateItem = AVPlayerItem(asset: asset)
        let looper = AVPlayerLooper(player: player, templateItem: templateItem)

        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.backgroundColor = UIColor.clear.cgColor

        context.coordinator.player = player
        context.coordinator.looper = looper
        context.coordinator.startOffset = startOffset

        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.startOffset = startOffset
        context.coordinator.apply(isPlaying: isPlaying)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var isPlaying: Bool = false
        var startOffset: Double = 0

        // Only react to actual transitions. `updateUIView` fires on every
        // SwiftUI re-render (which happens ~60–120× per second while Bruce
        // walks), so calling `play()` + `seek(to:)` every time is both
        // wasteful and a source of the "Bruce slides while standing" bug:
        // the seek was issued AFTER play() and could race, starting the
        // video from a stale position. Sequencing seek → play inside the
        // completion handler locks the video to the walking frame at each
        // cycle start so walking animation and position stay in lockstep.
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

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#endif
