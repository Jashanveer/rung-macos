import Foundation
import CoreGraphics
import Observation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

@Observable
class WalkerState {
    var positionProgress: CGFloat = 0.3
    var goingRight = true
    var isWalking = false
    var travelDistance: CGFloat = 500

    /// Offset into the Bruce/Jazz video where the walking frames begin — the
    /// first ~3s of the video is a standing pose. `LoopingVideoView` seeks
    /// here before playing so the walk animation starts on a walking frame,
    /// not the standing prefix (which previously caused Bruce to slide
    /// sideways for several steps before the walking animation kicked in).
    /// Padded slightly past the raw walking-frame boundary to absorb the
    /// ~50–150 ms latency between `AVPlayer.play()` and the first frame
    /// actually landing on screen.
    let videoWalkStartOffset: CFTimeInterval = 3.3

    // Walk-cycle timing. The cycle is now *just* the walking phase — the
    // video's pre/post-walk standing buffers are skipped via the seek above.
    // That keeps sprite position and video frames in lockstep: cycle start
    // = first walking frame, cycle end = last walking frame.
    private let walkDuration: CFTimeInterval = 5.0
    private let accelEnd: CFTimeInterval = 0.7
    private let decelStart: CFTimeInterval = 4.5

    private var walkStartTime: CFTimeInterval = 0
    private var walkStartPos: CGFloat = 0
    private var walkEndPos: CGFloat = 0
    #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: DisplayLinkTarget?
    #else
    private var frameTimer: Timer?
    #endif
    private var pauseWorkItem: DispatchWorkItem?

    deinit {
        stopTicking()
        pauseWorkItem?.cancel()
    }

    func start() {
        enterPause()
    }

    /// Fully halt the walker — stops ticking and cancels any pending walk
    /// cycle. `positionProgress` and `goingRight` stay where they are, so the
    /// character freezes on screen. Safe to call repeatedly.
    func pause() {
        stopTicking()
        pauseWorkItem?.cancel()
        pauseWorkItem = nil
        isWalking = false
    }

    /// Resume the idle → walk cycle from the current `positionProgress`.
    func resume() {
        guard !isWalking, pauseWorkItem == nil else { return }
        enterPause()
    }

    private func enterPause() {
        stopTicking()
        isWalking = false
        let delay = Double.random(in: 3.0...8.0)
        let work = DispatchWorkItem { [weak self] in self?.startWalk() }
        pauseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        startTicking()
    }

    private func startTicking() {
        stopTicking()
        #if canImport(UIKit)
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.fire))
        // Opt into ProMotion. The Info.plist key
        // `CADisableMinimumFrameDurationOnPhone` also has to be set,
        // otherwise iOS caps third-party apps at 60Hz regardless.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLinkTarget = target
        displayLink = link
        #else
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        #endif
    }

    private func stopTicking() {
        #if canImport(UIKit)
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        #else
        frameTimer?.invalidate()
        frameTimer = nil
        #endif
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - walkStartTime

        if elapsed >= walkDuration {
            stopTicking()
            positionProgress = walkEndPos
            isWalking = false
            enterPause()
            return
        }

        let walkNorm = movementPosition(at: elapsed)
        positionProgress = walkStartPos + (walkEndPos - walkStartPos) * walkNorm
    }

    private func movementPosition(at t: CFTimeInterval) -> CGFloat {
        let dIn = accelEnd
        let dLin = decelStart - accelEnd
        let dOut = walkDuration - decelStart

        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if t <= 0 {
            return 0.0
        } else if t <= dIn {
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if t <= decelStart {
            return CGFloat(v * dIn / 2.0 + v * (t - dIn))
        } else if t <= walkDuration {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let tt = t - decelStart
            return CGFloat(easeInDist + linearDist + v * (tt - tt * tt / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }
}

#if canImport(UIKit)
// CADisplayLink needs an @objc selector target. Keeping WalkerState a plain
// @Observable Swift class means we route the callback through this thin
// NSObject wrapper.
private final class DisplayLinkTarget: NSObject {
    private let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
    @objc func fire() { closure() }
}
#endif
