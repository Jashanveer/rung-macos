
import SwiftUI

struct EdgePanelHandle: View {
    enum DragDirection {
        case horizontal
        case vertical
    }

    let systemImage: String
    let label: String
    let edge: Edge
    let isActive: Bool
    let dragDirection: DragDirection
    let action: () -> Void

    @State private var isHovered = false

    private var dateLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var displayLabel: String {
        if case .bottom = edge, !isHovered {
            return dateLabel
        }

        return label
    }

    var body: some View {
        Button(action: action) {
            Group {
                switch edge {
                case .leading:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 74)
                case .trailing:
                    Label(label, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 74)
                case .bottom:
                    Label(displayLabel, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(width: 188, height: 34)
                        .overlay {
                            Label(dateLabel, systemImage: systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 16)
                                .hidden()
                        }
                default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(EdgeHandleButtonStyle(isActive: isActive))
        .accessibilityLabel(label)
        .animation(.smooth(duration: 0.14), value: isHovered)
        .pressHover($isHovered)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    switch dragDirection {
                    case .horizontal:
                        if abs(value.translation.width) > 24 {
                            action()
                        }
                    case .vertical:
                        if abs(value.translation.height) > 24 {
                            action()
                        }
                    }
                }
        )
    }
}

