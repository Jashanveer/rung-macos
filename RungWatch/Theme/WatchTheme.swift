import SwiftUI

/// User-controlled font scale, persisted via `@AppStorage` on the watch.
/// Three discrete steps so users can pick from Account → Display.
/// `1.0` = the default ramp; `0.9` for compact watches, `1.15` for users
/// who want chunkier numbers — Apple Watch favors big, glanceable text and
/// most of our default sizes are deliberately on the smaller end.
enum WatchFontScale: Double, CaseIterable, Identifiable {
    case compact = 0.9
    case `default` = 1.0
    case large = 1.15

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .compact:  return "Compact"
        case .default:  return "Default"
        case .large:    return "Large"
        }
    }
}

/// Read the user's stored font scale anywhere in the watch app via
/// `@Environment(\.watchFontScale)` after the root view injects it.
private struct WatchFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var watchFontScale: Double {
        get { self[WatchFontScaleKey.self] }
        set { self[WatchFontScaleKey.self] = newValue }
    }
}

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

    /// Curated typography ramp. Use these instead of `Font.system(size:)` so
    /// the user's chosen font scale lands consistently across every screen.
    /// Apple Watch HIG calls out that body should sit around 17pt — our old
    /// 9-10pt sizes were design-mock-faithful but felt too dense in real use.
    enum FontRole {
        case hero        // 38pt — the page's headline number ("4 / 7", "12d")
        case heroSmall   // 30pt — secondary hero (level number, top podium)
        case title       // 18pt — section titles inside a card
        case body        // 14pt — primary list rows
        case caption     // 11pt — meta lines (timestamps, day labels)
        case label       // 9pt   — uppercase tracking labels ("DONE", "APR")
    }

    static func font(_ role: FontRole, scale: Double = 1.0, weight: Font.Weight = .semibold, design: Font.Design = .rounded) -> Font {
        let baseSize: CGFloat
        switch role {
        case .hero:       baseSize = 38
        case .heroSmall:  baseSize = 30
        case .title:      baseSize = 18
        case .body:       baseSize = 14
        case .caption:    baseSize = 11
        case .label:      baseSize = 9
        }
        return .system(size: baseSize * CGFloat(scale), weight: weight, design: design)
    }
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

    /// CleanShot-style page header. A small accent dot, the page title in
    /// caps, and an optional right-side monospaced label (e.g. "9:41" or
    /// "APR"). Sits above the tab content with a hairline divider so users
    /// know which screen they're on at a glance.
    @ViewBuilder
    func watchPageHeader(
        _ title: String,
        accent: Color = WatchTheme.accent,
        trailing: String? = nil
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: accent.opacity(0.7), radius: 2)
                Text(title)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(WatchTheme.ink)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(WatchTheme.inkSoft)
                }
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
            self
        }
    }
}
