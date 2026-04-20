import SwiftUI

// Forma brand colors (handoff spec).
extension Color {
    static let formaBg   = Color(red: 0x0C / 255.0, green: 0x0F / 255.0, blue: 0x16 / 255.0)
    static let formaBlue = Color(red: 0x2E / 255.0, green: 0x94 / 255.0, blue: 0xDB / 255.0)
    static let formaGold = Color(red: 0xF0 / 255.0, green: 0xBD / 255.0, blue: 0x3D / 255.0)
    static let formaGrey = Color.white.opacity(0.08)
}

/// Reusable 4×4 Forma app icon. `buildStep` drives the piece-by-piece intro (0…5).
/// Pass `buildStep: 5` for the fully-assembled icon used in nav/header contexts.
struct FormaIconView: View {
    let size: CGFloat
    let buildStep: Int

    init(size: CGFloat, buildStep: Int = 5) {
        self.size = size
        self.buildStep = buildStep
    }

    // Base 120pt coordinate space — everything scales uniformly.
    private static let designSize: CGFloat = 120
    private static let cornerRadius: CGFloat = 28
    private static let cellSize: CGFloat = 10
    private static let cellCornerRadius: CGFloat = 3
    private static let gridOrigin: CGFloat = 30   // x/y of cell 0
    private static let gridStep: CGFloat = 16     // 10pt cell + 6pt gap

    var body: some View {
        let scale = size / Self.designSize

        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius * scale, style: .continuous)
                .fill(Color.formaBg)
                .opacity(buildStep >= 0 ? 1 : 0)

            ForEach(0..<16, id: \.self) { index in
                cell(index: index, scale: scale)
            }

            CheckStroke(progress: checkProgress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 1.5 * scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: Self.cellSize * scale, height: Self.cellSize * scale)
                .position(cellCenter(index: 10, scale: scale))
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Per-cell layout + animation

    private func cell(index: Int, scale: CGFloat) -> some View {
        let appearStep = appearStep(for: index)
        let isVisible = buildStep >= appearStep
        let staggerDelay = Double(index) * 0.03

        return RoundedRectangle(cornerRadius: Self.cellCornerRadius * scale, style: .continuous)
            .fill(cellColor(for: index))
            .frame(width: Self.cellSize * scale, height: Self.cellSize * scale)
            .position(cellCenter(index: index, scale: scale))
            .scaleEffect(isVisible ? 1 : 0.4)
            .opacity(isVisible ? 1 : 0)
            .animation(
                .interpolatingSpring(stiffness: 200, damping: 14).delay(staggerDelay),
                value: buildStep
            )
    }

    private func cellCenter(index: Int, scale: CGFloat) -> CGPoint {
        let row = index / 4
        let col = index % 4
        let x = (Self.gridOrigin + CGFloat(col) * Self.gridStep + Self.cellSize / 2) * scale
        let y = (Self.gridOrigin + CGFloat(row) * Self.gridStep + Self.cellSize / 2) * scale
        return CGPoint(x: x, y: y)
    }

    /// Which build step each cell appears in (spec: groups of 3 per step, last step picks up the tail).
    private func appearStep(for index: Int) -> Int {
        switch index {
        case 0, 1, 2:   return 1
        case 3, 4, 5:   return 2
        case 6, 7, 8:   return 3
        case 9, 10, 11: return 4
        default:        return 5
        }
    }

    private func cellColor(for index: Int) -> Color {
        switch index {
        case 0...9: return .formaBlue
        case 10:    return .formaGold
        default:    return .formaGrey
        }
    }

    /// Check stroke draws on during step 5. 0…1 progress, eased via the intro timeline.
    private var checkProgress: CGFloat {
        buildStep >= 5 ? 1 : 0
    }
}

// MARK: - Check stroke

/// Two-segment checkmark drawn in a unit frame (cell-sized). Animates via `trim`-like
/// progress so the stroke sweeps on with easeOut.
private struct CheckStroke: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Draw a check shape inside the given rect, leaving breathing room inside the cell.
        let inset = rect.width * 0.18
        let p1 = CGPoint(x: rect.minX + inset, y: rect.midY + rect.height * 0.02)
        let p2 = CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - inset)
        let p3 = CGPoint(x: rect.maxX - inset, y: rect.minY + inset)

        var path = Path()
        path.move(to: p1)

        let firstSegmentPortion: CGFloat = 0.4
        if progress <= firstSegmentPortion {
            let t = progress / firstSegmentPortion
            path.addLine(to: interpolate(p1, p2, t: t))
            return path
        }

        path.addLine(to: p2)
        let t = (progress - firstSegmentPortion) / (1 - firstSegmentPortion)
        path.addLine(to: interpolate(p2, p3, t: t))
        return path
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

// MARK: - Previews

#Preview("Complete") {
    FormaIconView(size: 120, buildStep: 5)
        .padding(30)
        .background(Color.black)
}

#Preview("Building step 3") {
    FormaIconView(size: 120, buildStep: 3)
        .padding(30)
        .background(Color.black)
}
