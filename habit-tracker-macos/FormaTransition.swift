import SwiftUI

/// Full-screen 5×8 grid cascade that obscures the auth → dashboard handoff.
/// Tiles cascade in from top-left, briefly hold, then fade out while the
/// dashboard mounts behind.
struct FormaTransition: View {
    var onCovered: (() -> Void)? = nil
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = 5
    private let cols = 8

    @State private var tileProgress: [CGFloat] = []
    @State private var overlayOpacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let tileW = geo.size.width  / CGFloat(cols)
            let tileH = geo.size.height / CGFloat(rows)

            ZStack {
                if reduceMotion {
                    Color.formaBg
                        .opacity(overlayOpacity)
                        .ignoresSafeArea()
                } else {
                    ForEach(0..<rows * cols, id: \.self) { i in
                        let row = i / cols
                        let col = i % cols
                        let isGold = i.isMultiple(of: 2)
                        Rectangle()
                            .fill(isGold ? Color.formaGold : Color.formaBlue)
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
    }

    private func tileScale(at index: Int) -> CGFloat {
        guard index < tileProgress.count else { return 0 }
        return tileProgress[index]
    }

    @MainActor
    private func runTimeline() async {
        tileProgress = Array(repeating: 0, count: rows * cols)

        if reduceMotion {
            try? await Task.sleep(nanoseconds: 200_000_000)
            onCovered?()
            withAnimation(.easeOut(duration: 0.3)) { overlayOpacity = 0 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onComplete()
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

        // Screen is fully covered — parent can now swap content underneath.
        onCovered?()

        withAnimation(.easeOut(duration: 0.3)) { overlayOpacity = 0 }
        try? await Task.sleep(nanoseconds: 320_000_000)
        onComplete()
    }
}

#Preview {
    FormaTransition(onComplete: {})
        .frame(width: 800, height: 500)
}
