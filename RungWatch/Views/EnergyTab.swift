import SwiftUI

/// Energy tab — two-process chronotype curve fed by the iPhone's
/// `EnergyForecast` (HealthKit sleep + recovery). The watch is a
/// renderer; the iPhone owns the model and pushes 24 hourly samples
/// per snapshot. Layout mirrors the design v3:
///
///   • Top — score + label ("72 STEADY") + summary line
///   • Middle — line + filled-area chart with a "now" marker
///   • Bottom — peak-window callout in a glass row
///
/// When the iPhone hasn't computed a forecast yet (HealthKit denied
/// or no sleep samples in the last few nights), the tab falls back to
/// a flat, hint-only state so the screen never feels broken.
struct EnergyTab: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    private var energy: WatchSnapshot.WatchEnergy? {
        session.snapshot.energy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                WatchPageTitle("Energy", accent: WatchTheme.cViolet)
                if let energy {
                    chart(for: energy)
                } else {
                    placeholder
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .watchWashBackground(.twilight)
    }

    private func chart(for energy: WatchSnapshot.WatchEnergy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(energy.score)")
                    .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                    .monospacedDigit()
                Text(energy.label)
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(bandColor(for: energy.label))
            }
            Text(energy.summary)
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(WatchTheme.inkSoft)

            EnergyCurveView(energy: energy)
                .frame(height: 64)
                .padding(.top, 4)

            HStack {
                Text("WAKE").foregroundStyle(WatchTheme.inkFaint)
                Spacer()
                Text("NOON").foregroundStyle(WatchTheme.inkFaint)
                Spacer()
                Text("BED").foregroundStyle(WatchTheme.inkFaint)
            }
            .font(.system(size: 7 * scale, weight: .heavy, design: .rounded))
            .tracking(1.0)

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9 * scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.cAmber)
                Text("Peak ")
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.ink)
                + Text(energy.peakWindow)
                    .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.cAmber)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassSurface(cornerRadius: 11, tint: WatchTheme.cAmber)
            .padding(.top, 4)
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("—")
                .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(WatchTheme.ink)
            Text("Open Rung on iPhone\nto sync sleep + energy")
                .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                .foregroundStyle(WatchTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            EnergyCurveView(energy: WatchSnapshot.WatchEnergy(
                samples: Array(repeating: 0.55, count: 24),
                nowIndex: 12, score: 0, label: "OFF",
                summary: "", peakWindow: "—",
                wakeIndex: 7, bedIndex: 23
            ))
            .frame(height: 64)
            .opacity(0.4)
            .padding(.top, 4)
        }
    }

    private func bandColor(for label: String) -> Color {
        switch label {
        case "PEAK":   return WatchTheme.cAmber
        case "STEADY": return WatchTheme.cViolet
        case "DIP":    return WatchTheme.cRose
        case "LOW":    return WatchTheme.cRose
        default:       return WatchTheme.inkSoft
        }
    }
}

/// Drawing layer — line + area + dotted wake/bed markers + glowing
/// "now" dot. Pure SwiftUI shapes so it scales with the watch face.
private struct EnergyCurveView: View {
    let energy: WatchSnapshot.WatchEnergy

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(2, energy.samples.count)
            // Local closure helpers — `func` can't live in a ViewBuilder
            // body without the compiler complaining about the explicit
            // return, so wrap the maths in trailing-return closures.
            let x: (Int) -> CGFloat = { i in
                CGFloat(i) / CGFloat(count - 1) * w
            }
            let y: (Double) -> CGFloat = { v in
                let inset: CGFloat = 4
                return h - CGFloat(v) * (h - inset * 2) - inset
            }

            ZStack {
                // Wake / bed markers — dashed verticals
                Path { p in
                    let xw = x(energy.wakeIndex)
                    p.move(to: CGPoint(x: xw, y: 0))
                    p.addLine(to: CGPoint(x: xw, y: h))
                    let xb = x(energy.bedIndex)
                    p.move(to: CGPoint(x: xb, y: 0))
                    p.addLine(to: CGPoint(x: xb, y: h))
                }
                .stroke(
                    Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 2])
                )

                // Filled area under the curve
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for i in 0..<count {
                        let v = energy.samples[safe: i] ?? 0.5
                        let pt = CGPoint(x: x(i), y: y(v))
                        if i == 0 {
                            p.addLine(to: pt)
                        } else {
                            p.addLine(to: pt)
                        }
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            WatchTheme.cViolet.opacity(0.55),
                            WatchTheme.cViolet.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Curve line
                Path { p in
                    for i in 0..<count {
                        let v = energy.samples[safe: i] ?? 0.5
                        let pt = CGPoint(x: x(i), y: y(v))
                        if i == 0 {
                            p.move(to: pt)
                        } else {
                            p.addLine(to: pt)
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [WatchTheme.cCyan, WatchTheme.cViolet, WatchTheme.cAmber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: WatchTheme.cViolet.opacity(0.6), radius: 3)

                // Now dot
                let nowIdx = max(0, min(count - 1, energy.nowIndex))
                let nowV = energy.samples[safe: nowIdx] ?? 0.5
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: .white, radius: 4)
                    .position(x: x(nowIdx), y: y(nowV))
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 12, height: 12)
                    .position(x: x(nowIdx), y: y(nowV))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

#if DEBUG
#Preview {
    EnergyTab()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
