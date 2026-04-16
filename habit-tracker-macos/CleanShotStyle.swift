import SwiftUI

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .padding(16)
            .cleanShotSurface(shape: shape, level: .base)
    }
}

enum CleanShotSurfaceLevel {
    case base
    case elevated
    case control
}

struct CleanShotSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let level: CleanShotSurfaceLevel
    let isActive: Bool
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(material, in: shape)
            .background(fill, in: shape)
            .overlay(
                shape
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: isActive), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: shadowColor, radius: appliedShadowRadius, y: appliedShadowRadius == 0 ? 0 : 6)
    }

    private var fill: Color {
        switch level {
        case .base:
            CleanShotTheme.surface(for: colorScheme)
        case .elevated:
            CleanShotTheme.elevatedSurface(for: colorScheme)
        case .control:
            CleanShotTheme.controlFill(for: colorScheme, active: isActive)
        }
    }

    private var material: Material {
        switch level {
        case .base:
            return .thinMaterial
        case .elevated:
            return .regularMaterial
        case .control:
            return .ultraThinMaterial
        }
    }

    private var appliedShadowRadius: CGFloat {
        switch level {
        case .base:
            return min(shadowRadius, 12)
        case .elevated:
            return min(shadowRadius, 18)
        case .control:
            return isActive ? 4 : 0
        }
    }

    private var shadowColor: Color {
        switch level {
        case .base:
            return CleanShotTheme.shadow(for: colorScheme)
        case .elevated:
            return CleanShotTheme.shadow(for: colorScheme, strong: true)
        case .control:
            return isActive ? CleanShotTheme.shadow(for: colorScheme) : .clear
        }
    }
}

extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }

    func minimalPanel() -> some View {
        cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control
        )
    }

    func sidebarSurfaceStyle() -> some View {
        cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
            level: .elevated,
            shadowRadius: 12
        )
    }

    func cleanShotSurface<S: InsettableShape>(
        shape: S,
        level: CleanShotSurfaceLevel,
        isActive: Bool = false,
        shadowRadius: CGFloat = 10
    ) -> some View {
        modifier(
            CleanShotSurfaceModifier(
                shape: shape,
                level: level,
                isActive: isActive,
                shadowRadius: shadowRadius
            )
        )
    }
}

struct PrimaryCircleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(CleanShotTheme.accent, in: Circle())
            .overlay(
                Circle()
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: true), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(CleanShotTheme.accent.opacity(configuration.isPressed ? 0.75 : 1.0), in: Capsule())
    }
}

struct SecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? CleanShotTheme.accent : .primary)
            .background(CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 1)
            )
    }
}

struct EdgeHandleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? CleanShotTheme.accent : .secondary)
            .background(
                CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed || isActive),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme, active: isActive), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(CleanShotTheme.controlFill(for: colorScheme, active: configuration.isPressed), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 1)
            )
    }
}

