import SwiftUI

/// Watch-side port of `CleanShotTheme` from the iOS/macOS Rung app, with
/// hex literals matching the Apple Watch design HTML 1:1. Watch screens are
/// always dark — there's no light-mode fallback so the constants are flat.
enum WatchTheme {
    // Backgrounds
    static let bg          = Color(hex: 0x0E0F13)
    static let canvas      = Color(hex: 0x14161C)
    static let line        = Color.white.opacity(0.07)

    // Ink
    static let ink         = Color(hex: 0xF1F3F7)
    static let inkSoft     = Color(hex: 0x8A90A0)

    // Brand palette — same hex as CleanShotTheme but as compile-time literals
    static let accent      = Color(hex: 0x2E94DB)
    static let success     = Color(hex: 0x38AD5C)
    static let warning     = Color(hex: 0xF59C2E)
    static let danger      = Color(hex: 0xE65C61)
    static let gold        = Color(hex: 0xF0BD3E)
    static let violet      = Color(hex: 0x757AD7)

    // Glass surface — matches the HTML mock's gradient + 0.5pt stroke.
    static let glassFill   = LinearGradient(
        colors: [Color.white.opacity(0.06), Color.white.opacity(0.025)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let glassStroke = Color.white.opacity(0.08)

    // Brand gradient (used on level pill, avatar, brand mark)
    static let brandGradient = LinearGradient(
        colors: [accent, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Progress bar gradient (blue → gold)
    static let progressGradient = LinearGradient(
        colors: [accent, gold],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Hex helper

extension Color {
    /// Hex literal initialiser used by the watch theme so the design constants
    /// stay one-to-one with the source HTML mock.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Glass background modifier

extension View {
    /// Glass-tile background used on stat squares, account rows, and badges.
    /// Matches the `.glass` CSS class from the design mock.
    func watchGlass(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(WatchTheme.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(WatchTheme.glassStroke, lineWidth: 0.5)
                )
        )
    }

    /// Status-bar style applied to the top of every tab. Left side ink, right
    /// side gold monospaced label (e.g. "STATS", "ME", "APR").
    @ViewBuilder
    func watchStatusBar(left: String, right: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(left)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Text(right)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(WatchTheme.gold)
            }
            .frame(height: 14)
            .padding(.horizontal, 10)
            .padding(.top, 3)
            self
        }
    }
}
