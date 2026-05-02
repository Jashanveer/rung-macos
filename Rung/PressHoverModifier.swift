import SwiftUI

/// Cross-platform hover/press tracker. On macOS the `isPressed` binding tracks
/// `.onHover`; on iOS it tracks the finger-down state of a long-press that
/// fires immediately and cancels as soon as the user drags far enough to be
/// scrolling.
///
/// Use this everywhere the macOS code previously called `.onHover { isHovered =
/// $0 }`. On Mac the behavior is identical. On iPhone/iPad the same callback
/// now fires on touch-down and clears on touch-up OR when the user starts
/// scrolling past the press-gesture's maximumDistance.
struct PressHoverModifier: ViewModifier {
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onHover { isPressed = $0 }
        #else
        // A zero-distance `DragGesture` here (the previous implementation)
        // claimed the touch immediately, which blocked the enclosing
        // ScrollView from ever starting a scroll when the finger landed on
        // a hover-tracked tile (Stats screen cards, habit cards, etc.).
        // `onLongPressGesture` with `minimumDuration: .infinity` and a small
        // `maximumDistance` fires `onPressingChanged(true)` on touch-down
        // and `onPressingChanged(false)` the moment the finger moves past
        // the distance threshold — which is exactly when the ScrollView
        // wants to take over. The `perform` closure never runs because the
        // long-press never "completes".
        content
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: 10,
                perform: {},
                onPressingChanged: { pressing in
                    isPressed = pressing
                }
            )
        #endif
    }
}

extension View {
    /// Track "hover on Mac, press on iOS" into a single boolean. See
    /// `PressHoverModifier` for why.
    func pressHover(_ isPressed: Binding<Bool>) -> some View {
        modifier(PressHoverModifier(isPressed: isPressed))
    }
}
