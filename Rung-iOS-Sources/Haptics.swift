import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Thin cross-platform wrapper around `UIImpactFeedbackGenerator` and
/// `UINotificationFeedbackGenerator`. No-ops on macOS. Respects
/// Reduce Motion / AX preferences by letting the underlying system throttle.
enum Haptics {
    enum Impact {
        case light
        case medium
        case heavy
        case soft
        case rigid

        #if os(iOS)
        fileprivate var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light:  return .light
            case .medium: return .medium
            case .heavy:  return .heavy
            case .soft:   return .soft
            case .rigid:  return .rigid
            }
        }
        #endif
    }

    enum Notification {
        case success
        case warning
        case error

        #if os(iOS)
        fileprivate var uiType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error:   return .error
            }
        }
        #endif
    }

    static func impact(_ style: Impact = .medium) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func notify(_ type: Notification) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type.uiType)
        #endif
    }

    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
