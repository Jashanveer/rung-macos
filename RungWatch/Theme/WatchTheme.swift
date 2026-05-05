import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

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

/// Watch-side port of the iOS / macOS Rung "Liquid Glass" system. Surfaces
/// float over a warm radial color wash — never flat black — and use a
/// frosted-white tile with a hairline stroke + inner top-edge highlight to
/// match the iOS 26 / watchOS 26 system materials. Each tab gets a tinted
/// ambient wash so the user can tell screens apart at a glance even
/// without reading labels.
enum WatchTheme {
    // Canvas — warm midnight, never flat black.
    static let bg          = Color(hex: 0x07080C)
    static let canvas      = Color(hex: 0x14101F)
    static let line        = Color.white.opacity(0.10)
    static let hairline    = Color.white.opacity(0.18)

    // Ink
    static let ink         = Color(hex: 0xF5F6F8)
    static let inkSoft     = Color(hex: 0x9099AA)
    static let inkFaint    = Color(hex: 0x5A6172)

    // Brand palette — sRGB approximations of the design's oklch ramp
    // (lightness ≈ 0.74, chroma ≈ 0.14–0.18). Hand-tuned so the colors
    // stay in the same perceptual band as the iOS / iPad / macOS app.
    static let cAmber      = Color(hex: 0xF6BD52)   // oklch(0.78 0.16 70)
    static let cPeach      = Color(hex: 0xEFA580)   // oklch(0.76 0.14 35)
    static let cViolet     = Color(hex: 0xA088EA)   // oklch(0.70 0.16 290)
    static let cCyan       = Color(hex: 0x77B2DC)   // oklch(0.74 0.13 220)
    static let cMint       = Color(hex: 0x6FDDA8)   // oklch(0.78 0.14 160)
    static let cRose       = Color(hex: 0xEF7E89)   // oklch(0.72 0.18 15)

    // Semantic aliases — the rest of the watch code still talks in
    // accent / success / warning / danger / gold, so map those onto the
    // new palette instead of breaking call sites.
    static let accent      = cCyan
    static let success     = cMint
    static let warning     = cAmber
    static let danger      = cRose
    static let gold        = cAmber
    static let violet      = cViolet

    // Glass surface — matches the design's `.glass` CSS (frosted white
    // 6–13% with a hairline stroke). Used as a fallback on pre-26
    // watchOS where the system `glassEffect` isn't available yet.
    static let glassFill   = LinearGradient(
        colors: [Color.white.opacity(0.13), Color.white.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let glassStroke = Color.white.opacity(0.18)

    // Brand gradient (level pill, avatar, brand mark, primary button).
    // Cyan→violet keeps the hue within the palette band so it doesn't
    // pop out of the warm wash like the old blue→gold did.
    static let brandGradient = LinearGradient(
        colors: [cCyan, cViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Progress / ring gradient — peach → violet → cyan reads from "warm
    // start" to "cool end" and matches the design's daily-ring stroke.
    static let progressGradient = LinearGradient(
        colors: [cPeach, cViolet, cCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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

// MARK: - Animation tokens

/// Centralised spring curves so every watch surface uses the same
/// "snappy but not abrupt" motion. Matches the Rung iOS/macOS app's
/// 0.35–0.5s spring vocabulary — the user sees the same physical
/// feedback regardless of which surface they're touching.
enum WatchMotion {
    /// Default tap / state-flip spring. Used for toggle buttons, ring
    /// progress, sheet entrances. Same shape as iOS's "fast spring".
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.78)
    /// Slower, gentler spring for layout transitions where snappy
    /// would feel jittery (tab switches, hero entrance).
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Fast micro-bounce for symbol effects + counter rolls.
    static let micro = Animation.spring(response: 0.25, dampingFraction: 0.74)
}

// MARK: - Press feedback

/// Watch-friendly press style — subtle 0.96 scale + opacity dip, plus a
/// light haptic on touch-down. Apple Watch HIG says taps need physical
/// feedback to feel real on a sub-second touchpoint, so the haptic is
/// not optional. Apply via `.buttonStyle(WatchPressStyle())`.
struct WatchPressStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(WatchMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard haptic, pressed else { return }
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.click)
                #endif
            }
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

// MARK: - Page title

/// Tiny caps page title that sits in the top-left of every tab. Mirrors
/// the iOS bottom-tab labels ("Today", "Calendar", "Stats", …) so the
/// user always knows which screen they're on at a glance, especially
/// after the tab dots disappear with watchOS's auto-hide. Render with a
/// small accent dot + tracking to match the design's monospaced caps.
struct WatchPageTitle: View {
    let title: String
    let accent: Color

    init(_ title: String, accent: Color = WatchTheme.cAmber) {
        self.title = title
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
                .shadow(color: accent.opacity(0.8), radius: 2)
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tab backgrounds (warm radial washes)

/// Each tab in the watch app picks a wash so users can tell screens apart
/// at a glance. The colors come from the design v3 oklch palette and share
/// the same chroma so the app reads as one piece. There is no "flat black"
/// option — every screen has a tinted ambient wash bleeding from corners.
enum WatchWash {
    case violet   // Habits / Stats — primary daily flow
    case peach    // Calendar — warm streak energy
    case cyan     // Friends — leaderboard, cool blue lean
    case mint     // Mentor — fresh chat surface
    case twilight // Account — violet→peach gradient, settings
    case amber    // Reserved for focus / pomodoro (long-press flow)
}

/// The actual wash view. Two stacked radial gradients (one warm corner,
/// one cool corner) painted over a deep midnight base — never pure black,
/// always a faint hue tint. Tuned for Apple Watch's ~180×220pt screen.
struct WatchWashBackground: View {
    let wash: WatchWash

    var body: some View {
        ZStack {
            // Deep midnight base with a faint violet bias so even the
            // darkest pixel has hue, matching iOS 26's "no flat black"
            // material guidance.
            Color(hex: 0x06070B)

            switch wash {
            case .violet:
                radial(WatchTheme.cViolet.opacity(0.55), at: .init(x: 0.6, y: -0.05), radius: 240)
                radial(WatchTheme.cAmber.opacity(0.16), at: .init(x: 0.2, y: 1.05), radius: 200)
            case .peach:
                radial(WatchTheme.cPeach.opacity(0.55), at: .init(x: 0.25, y: -0.05), radius: 220)
                radial(WatchTheme.cRose.opacity(0.30), at: .init(x: 0.85, y: 1.05), radius: 220)
            case .cyan:
                radial(WatchTheme.cCyan.opacity(0.50), at: .init(x: 0.25, y: -0.05), radius: 230)
                radial(WatchTheme.cViolet.opacity(0.28), at: .init(x: 0.85, y: 1.05), radius: 220)
            case .mint:
                radial(WatchTheme.cMint.opacity(0.45), at: .init(x: 0.5, y: -0.05), radius: 220)
                radial(WatchTheme.cCyan.opacity(0.30), at: .init(x: 0.5, y: 1.05), radius: 220)
            case .twilight:
                radial(WatchTheme.cViolet.opacity(0.50), at: .init(x: 0.5, y: -0.05), radius: 230)
                radial(WatchTheme.cPeach.opacity(0.28), at: .init(x: 0.5, y: 1.05), radius: 220)
            case .amber:
                radial(WatchTheme.cAmber.opacity(0.55), at: .init(x: 0.5, y: -0.05), radius: 230)
                radial(WatchTheme.cViolet.opacity(0.30), at: .init(x: 0.5, y: 1.05), radius: 220)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func radial(_ color: Color, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color, color.opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        .blendMode(.screen)
    }
}

// MARK: - Surface modifiers

extension View {
    /// Glass-tile background used on stat squares, account rows, and badges.
    /// Pre-26 fallback for `liquidGlassSurface` — matches the design's
    /// `.glass` CSS class.
    func watchGlass(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(WatchTheme.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)
        )
    }

    /// Liquid Glass surface — frosted material + brighter top-edge stroke
    /// + soft drop shadow. Mirrors the iOS / macOS Rung pattern so the
    /// watch feels native to the rest of the app. On watchOS 26 the
    /// material picks up the system `glassEffect`; older releases get
    /// the gradient-fill fallback automatically.
    @ViewBuilder
    func liquidGlassSurface(
        cornerRadius: CGFloat = 14,
        tint: Color? = nil,
        strong: Bool = false
    ) -> some View {
        let topAlpha = strong ? 0.20 : 0.13
        let bottomAlpha = strong ? 0.08 : 0.05
        let strokeTop = strong ? 0.36 : 0.28
        let strokeBottom = strong ? 0.12 : 0.08
        let shadowAlpha = strong ? 0.42 : 0.32

        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(topAlpha),
                                Color.white.opacity(bottomAlpha)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                if let tint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.30), tint.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.plusLighter)
                }
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeTop),
                                Color.white.opacity(strokeBottom)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: Color.black.opacity(shadowAlpha), radius: 8, y: 3)
        )
    }

    /// Apply one of the warm radial washes as the tab container
    /// background. Always prefer this over `WatchTheme.bg` — the design
    /// language requires every screen to ride on a tinted ambient wash,
    /// never flat black.
    @ViewBuilder
    func watchWashBackground(_ wash: WatchWash) -> some View {
        #if os(watchOS)
        self.containerBackground(for: .tabView) {
            WatchWashBackground(wash: wash)
        }
        #else
        self.background(WatchWashBackground(wash: wash))
        #endif
    }

    /// Same wash, but applied to a navigation container (used by the
    /// drill-in detail screens — habit detail, health detail, workout).
    @ViewBuilder
    func watchWashNavigationBackground(_ wash: WatchWash) -> some View {
        #if os(watchOS)
        self.containerBackground(for: .navigation) {
            WatchWashBackground(wash: wash)
        }
        #else
        self.background(WatchWashBackground(wash: wash))
        #endif
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
