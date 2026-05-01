import SwiftUI

/// Full-screen 5×8 grid that obscures the auth → dashboard handoff.
///
/// Two drive modes:
/// - **Automatic (default):** tiles cascade in diagonally, hold ~1s, then fade.
///   Used by onboarding completion where we control the full timeline.
/// - **Await-dismiss:** tiles fill the screen nearly instantly, then hold
///   indefinitely until `dismiss` flips true (driven by the login API result).
///   Used for the login/register cascade so the grid shows the moment the
///   button is tapped and stays covering until the network round-trip completes.
struct RungTransition: View {
    /// When true, tiles fill fast (no staggered cascade) and the view holds
    /// covered until `dismiss` flips true. `onCovered` fires once the grid is
    /// fully opaque so the caller can kick off its background work.
    var awaitDismiss: Bool = false
    /// In `awaitDismiss` mode, flip true to start the fade-out. Ignored when
    /// `awaitDismiss == false` (legacy automatic timeline).
    var dismiss: Bool = false
    var onCovered: (() -> Void)? = nil
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = 5
    private let cols = 8

    @State private var tileProgress: [CGFloat] = []
    @State private var overlayOpacity: Double = 1
    @State private var hasCovered = false
    @State private var fadeStarted = false

    var body: some View {
        GeometryReader { geo in
            let tileW = geo.size.width  / CGFloat(cols)
            let tileH = geo.size.height / CGFloat(rows)

            ZStack {
                // Solid backdrop. Keeps whatever is behind (dashboard during
                // auth → dashboard handoff) fully hidden while tiles cascade in
                // from scale 0. Fades out with the tiles.
                Color.rungBg
                    .opacity(overlayOpacity)
                    .ignoresSafeArea()

                if !reduceMotion {
                    ForEach(0..<rows * cols, id: \.self) { i in
                        let row = i / cols
                        let col = i % cols
                        // Checkerboard: alternate both horizontally and vertically.
                        let isGold = (row + col).isMultiple(of: 2)
                        Rectangle()
                            .fill(isGold ? Color.rungGold : Color.rungAccent)
                            .frame(width: tileW, height: tileH)
                            .position(
                                x: tileW * (CGFloat(col) + 0.5),
                                y: tileH * (CGFloat(row) + 0.5)
                            )
                            .scaleEffect(tileScale(at: i))
                    }
                    .opacity(overlayOpacity)
                }
            }
            .task { await runTimeline() }
            .onChange(of: dismiss) { _, shouldDismiss in
                guard awaitDismiss, shouldDismiss else { return }
                Task { await startFadeOutIfReady() }
            }
            // Covers the race where `dismiss` arrived before `hasCovered`
            // became true: the dismiss-onChange runs first, bails out
            // because the cascade isn't fully covering yet, and the
            // fallback inside runTimeline reads a stale captured `dismiss`
            // value (View struct props don't update inside a running async
            // closure). Reading `dismiss` from this body-level handler
            // sees the live value.
            .onChange(of: hasCovered) { _, covered in
                guard awaitDismiss, covered, dismiss else { return }
                Task { await startFadeOutIfReady() }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(overlayOpacity > 0.05)
    }

    private func tileScale(at index: Int) -> CGFloat {
        guard index < tileProgress.count else { return 0 }
        return tileProgress[index]
    }

    @MainActor
    private func runTimeline() async {
        tileProgress = Array(repeating: 0, count: rows * cols)

        if reduceMotion {
            try? await Task.sleep(nanoseconds: 120_000_000)
            hasCovered = true
            onCovered?()
            if awaitDismiss {
                // Parent drives fade-out via `dismiss`. Bail here; `onChange`
                // will call startFadeOutIfReady when it flips.
                if dismiss { await startFadeOutIfReady() }
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await performFadeOut()
            return
        }

        // 40ms per diagonal step gives a clearly visible top-left → bottom-right
        // sweep. Faster steps (5–10ms) collapse the cascade visually so it looks
        // like the tiles snap in from the centre simultaneously, which loses the
        // diagonal character. Match macOS for consistency on iPhone + iPad.
        for i in 0..<rows * cols {
            let row = i / cols
            let col = i % cols
            let delay = Double(row + col) * 0.04   // 40ms per diagonal step

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard i < tileProgress.count else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    tileProgress[i] = 1
                }
            }
        }

        // Wait for the final tile to seat before declaring the screen covered.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        hasCovered = true
        onCovered?()

        if awaitDismiss {
            // Parent will flip `dismiss` when its work is done.
            if dismiss { await startFadeOutIfReady() }
            return
        }

        await performFadeOut()
    }

    @MainActor
    private func startFadeOutIfReady() async {
        guard hasCovered, !fadeStarted else { return }
        await performFadeOut()
    }

    @MainActor
    private func performFadeOut() async {
        guard !fadeStarted else { return }
        fadeStarted = true
        withAnimation(.easeOut(duration: 0.3)) { overlayOpacity = 0 }
        try? await Task.sleep(nanoseconds: 320_000_000)
        onComplete()
    }
}

#Preview {
    RungTransition(onComplete: {})
        .frame(width: 800, height: 500)
}
