import SwiftUI

enum CleanShotTheme {
    static let accent = Color(red: 0.18, green: 0.58, blue: 0.86)
    static let success = Color(red: 0.22, green: 0.68, blue: 0.36)
    static let warning = Color(red: 0.96, green: 0.61, blue: 0.18)
    static let gold = Color(red: 0.94, green: 0.74, blue: 0.24)
    static let violet = Color(red: 0.46, green: 0.48, blue: 0.84)

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.058, blue: 0.068)
            : Color(red: 0.955, green: 0.965, blue: 0.975)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.136, blue: 0.155).opacity(0.74)
            : Color.white.opacity(0.72)
    }

    static func elevatedSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.178, blue: 0.20).opacity(0.78)
            : Color.white.opacity(0.82)
    }

    static func controlFill(for colorScheme: ColorScheme, active: Bool = false) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(active ? 0.13 : 0.075)
            : Color.black.opacity(active ? 0.075 : 0.04)
    }

    static func stroke(for colorScheme: ColorScheme, active: Bool = false) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(active ? 0.20 : 0.105)
        }

        return Color.black.opacity(active ? 0.14 : 0.08)
    }

    static func shadow(for colorScheme: ColorScheme, strong: Bool = false) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(strong ? 0.42 : 0.22)
            : Color.black.opacity(strong ? 0.16 : 0.075)
    }
}
