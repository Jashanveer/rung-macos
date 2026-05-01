import Foundation
import CoreGraphics
import Observation
import QuartzCore

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
    let videoWalkStartOffset: CFTimeInterval = 3.0

    // Walk-cycle timing. The cycle is now *just* the walking phase — the
    // video's pre/post-walk standing buffers are skipped via the seek above.
    // That keeps sprite position and video frames in lockstep: cycle start
    // = first walking frame, cycle end = last walking frame.
    private let walkDuration: CFTimeInterval = 5.5
    private let accelEnd: CFTimeInterval = 0.75
    private let decelStart: CFTimeInterval = 5.0

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

        if elapsed >= walkDuration {
            frameTimer?.invalidate()
            frameTimer = nil
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
