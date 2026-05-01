import SwiftUI

/// Full-screen 5×8 grid cascade that obscures the auth → dashboard handoff.
/// Tiles cascade in from top-left, hold until the parent signals it's safe to
/// reveal, then fade out while whatever lives underneath mounts.
///
/// `readyToReveal` lets the cascade double as a loading cover: pass `false`
/// while an API request is in flight, then flip to `true` once the response
/// lands. When `true` from the start (default), the cascade runs its original
/// timeline — cascade in, brief hold, fade out.
struct RungTransition: View {
    var onCovered: (() -> Void)? = nil
    var readyToReveal: Bool = true
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = 5
    private let cols = 8

    @State private var tileProgress: [CGFloat] = []
    @State private var overlayOpacity: Double = 1
    @State private var isCovered = false
    @State private var didBeginDismiss = false
    /// @State mirror of `readyToReveal`. The prop is a plain stored property
    /// on this struct; an async task started by `.task` captures `self` by
    /// value, so reads of `self.readyToReveal` after any `await` return the
    /// stale value from when the task started. Mirroring into @State (and
    /// syncing via onChange/onAppear) guarantees we always observe the
    /// current value driven by the parent.
    @State private var readyLatched = false

    var body: some View {
        GeometryReader { geo in
            let tileW = geo.size.width  / CGFloat(cols)
            let tileH = geo.size.height / CGFloat(rows)

            ZStack {
                if reduceMotion {
                    Color.rungBg
                        .opacity(overlayOpacity)
                        .ignoresSafeArea()
                } else {
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
        }
        .ignoresSafeArea()
        .allowsHitTesting(overlayOpacity > 0.05)
        .onAppear { readyLatched = readyToReveal }
        .onChange(of: readyToReveal) { _, newValue in
            readyLatched = newValue
            dismissIfReady()
        }
        .onChange(of: isCovered) { _, _ in
            dismissIfReady()
        }
    }

    private func tileScale(at index: Int) -> CGFloat {
        guard index < tileProgress.count else { return 0 }
        return tileProgress[index]
    }

    @MainActor
    private func dismissIfReady() {
        guard !didBeginDismiss, isCovered, readyLatched else { return }
        Task { await performDismiss() }
    }

    @MainActor
    private func runTimeline() async {
        tileProgress = Array(repeating: 0, count: rows * cols)

        if reduceMotion {
            try? await Task.sleep(nanoseconds: 200_000_000)
            markCovered()
            return
        }

        for i in 0..<rows * cols {
            let row = i / cols
            let col = i % cols
            let delay = Double(row + col) * 0.04   // 40ms per diagonal step

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard i < tileProgress.count else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    tileProgress[i] = 1
                }
            }
        }

        // Hold: wait for the slowest (bottom-right) tile to settle plus a brief pause.
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Screen is fully covered — parent can swap content underneath and/or
        // finish its pending work. The onChange(isCovered) handler will
        // perform the fade-out if the parent has already flipped readyToReveal.
        markCovered()
    }

    @MainActor
    private func markCovered() {
        guard !isCovered else { return }
        onCovered?()
        isCovered = true   // triggers onChange(isCovered) → dismissIfReady()
    }

    @MainActor
    private func performDismiss() async {
        guard !didBeginDismiss else { return }
        didBeginDismiss = true
        withAnimation(.easeOut(duration: 0.3)) { overlayOpacity = 0 }
        try? await Task.sleep(nanoseconds: 320_000_000)
        onComplete()
    }
}

#Preview {
    RungTransition(onComplete: {})
        .frame(width: 800, height: 500)
}
