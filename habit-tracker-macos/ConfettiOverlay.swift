import SwiftUI

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let xVelocity: CGFloat
    let yVelocity: CGFloat
    let shape: Int // 0 = circle, 1 = rectangle, 2 = triangle
}

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var elapsed: TimeInterval = 0
    @State private var startDate = Date()

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan, .mint, .indigo
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                Canvas { context, canvasSize in
                    for particle in particles {
                        let t = elapsed
                        let gravity: CGFloat = 420
                        let drag: CGFloat = 0.97

                        let px = particle.x + particle.xVelocity * t * drag
                        let py = particle.y + particle.yVelocity * t * drag + 0.5 * gravity * t * t
                        let angle = Angle.degrees(particle.rotation + t * 180)

                        guard px > -20, px < canvasSize.width + 20,
                              py < canvasSize.height + 40 else { continue }

                        context.opacity = max(1.0 - t * 0.4, 0)

                        switch particle.shape {
                        case 0:
                            let rect = CGRect(
                                x: px - particle.size / 2,
                                y: py - particle.size / 2,
                                width: particle.size,
                                height: particle.size
                            )
                            context.fill(
                                Circle().path(in: rect),
                                with: .color(particle.color)
                            )
                        case 1:
                            let transform = CGAffineTransform.identity
                                .translatedBy(x: px, y: py)
                                .rotated(by: angle.radians)
                            let rect = CGRect(
                                x: -particle.size * 0.6,
                                y: -particle.size * 0.3,
                                width: particle.size * 1.2,
                                height: particle.size * 0.6
                            )
                            let path = Rectangle().path(in: rect).applying(transform)
                            context.fill(path, with: .color(particle.color))
                        default:
                            var path = Path()
                            let s = particle.size
                            path.move(to: CGPoint(x: 0, y: -s / 2))
                            path.addLine(to: CGPoint(x: s / 2, y: s / 2))
                            path.addLine(to: CGPoint(x: -s / 2, y: s / 2))
                            path.closeSubpath()
                            let transform = CGAffineTransform.identity
                                .translatedBy(x: px, y: py)
                                .rotated(by: angle.radians)
                            context.fill(
                                path.applying(transform),
                                with: .color(particle.color)
                            )
                        }
                    }
                }
                .onChange(of: timeline.date) {
                    elapsed = timeline.date.timeIntervalSince(startDate)
                }
            }
            .onAppear {
                startDate = Date()
                spawnParticles(in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func spawnParticles(in size: CGSize) {
        let centerX = size.width / 2
        let topY = size.height * 0.15

        particles = (0..<80).map { _ in
            let angle = Double.random(in: -Double.pi * 0.85 ... -Double.pi * 0.15)
            let speed = CGFloat.random(in: 280...620)
            return ConfettiParticle(
                x: centerX + CGFloat.random(in: -60...60),
                y: topY + CGFloat.random(in: -20...20),
                size: CGFloat.random(in: 5...11),
                color: colors.randomElement() ?? .yellow,
                rotation: Double.random(in: 0...360),
                xVelocity: cos(angle) * speed,
                yVelocity: sin(angle) * speed,
                shape: Int.random(in: 0...2)
            )
        }
    }
}

