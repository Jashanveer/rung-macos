import SwiftUI

struct SpeechBubbleNudge: View {
    let text: String
    let width: CGFloat
    let tailAnchorX: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: width)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 0.5)
                )

            HStack(spacing: 0) {
                Spacer()
                    .frame(width: tailOffset)

                Triangle()
                    .fill(backgroundColor)
                    .frame(width: 12, height: 7)

                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.19, blue: 0.22)
            : Color.white
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var tailOffset: CGFloat {
        max(0, min(width - 12, width * tailAnchorX - 6))
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview("Nudge") {
    SpeechBubbleNudge(text: "Nice work!", width: 160, tailAnchorX: 0.5)
        .padding(40)
}
