import SwiftUI

/// "Where is my energy right now and where is it going?" view. The hero is
/// a circular gauge for the current reading, backed by a hand-drawn curve
/// chart for the rest of today, with a sleep-debt readout and two
/// recommendations underneath.
///
/// All math comes from `EnergyForecast`; this file is purely presentational
/// so the same view ships on every platform without `#if` branches.
///
/// Empty state: if HealthKit hasn't given us ≥3 nights yet, render a
/// friendly explainer + a one-tap button to request HK access, then
/// return — never show speculative numbers.
struct EnergyView: View {
    @ObservedObject var service: SleepInsightsService

    @Environment(\.colorScheme) private var colorScheme
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let snapshot = service.snapshot, let forecast = service.forecast {
                    headerSection(snapshot: snapshot, forecast: forecast)
                    EnergyCurveChart(forecast: forecast)
                        .frame(height: 180)
                    sleepDebtSection(snapshot: snapshot)
                    recommendationsSection(forecast: forecast)
                    bedtimeSection(snapshot: snapshot)
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .task {
            // Refresh on appear so the gauge reflects new sleep data the
            // moment the user opens the tab. Cheap — the service is a
            // singleton and HK queries are cached internally.
            await service.refresh()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(snapshot: SleepSnapshot, forecast: EnergyForecast) -> some View {
        let now = Date()
        let energy = forecast.energy(at: now)
        let band = EnergyForecast.label(for: energy)
        VStack(spacing: 12) {
            Text("Energy now")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .textCase(.uppercase)

            EnergyGauge(value: energy, band: band)
                .frame(width: 200, height: 200)

            Text(band.label)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(bandTint(for: band))

            Text(headerSubtitle(for: band))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func sleepDebtSection(snapshot: SleepSnapshot) -> some View {
        let debt = snapshot.sleepDebtHours
        let info: (label: String, tint: Color, icon: String) = {
            if debt < 1 {
                return ("Sleep debt: clear", .green, "checkmark.seal.fill")
            } else if debt < 5 {
                return (String(format: "Sleep debt: %.1fh", debt), .orange, "moon.zzz.fill")
            } else {
                return (String(format: "Sleep debt: %.1fh — heavy", debt), .red, "exclamationmark.triangle.fill")
            }
        }()
        return InsightRow(
            systemImage: info.icon,
            tint: info.tint,
            primary: info.label,
            secondary: "Rolling deficit over the last \(snapshot.sampleCount) nights · 8h target"
        )
    }

    @ViewBuilder
    private func recommendationsSection(forecast: EnergyForecast) -> some View {
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .hour, value: 12, to: now) ?? now

        VStack(spacing: 10) {
            if let peak = forecast.nextPeak(after: now, until: endOfDay) {
                let mins = Int(peak.timeIntervalSince(now) / 60)
                let timing = mins <= 1 ? "right now" : (mins < 60 ? "in \(mins) min" : timeString(peak))
                InsightRow(
                    systemImage: "bolt.fill",
                    tint: .green,
                    primary: "Peak \(timing)",
                    secondary: "Best window for deep work, hard workouts, or any habit you've been putting off."
                )
            }
            if let dip = forecast.nextDip(after: now, until: endOfDay) {
                let mins = Int(dip.timeIntervalSince(now) / 60)
                let timing = mins <= 1 ? "right now" : (mins < 60 ? "in \(mins) min" : timeString(dip))
                InsightRow(
                    systemImage: "battery.25",
                    tint: .orange,
                    primary: "Dip \(timing)",
                    secondary: "Schedule something low-stakes — a walk, a stretch, a reading break."
                )
            }
        }
    }

    @ViewBuilder
    private func bedtimeSection(snapshot: SleepSnapshot) -> some View {
        let bedLabel = snapshot.bedTimeLabel
        let wakeLabel = snapshot.wakeTimeLabel
        InsightRow(
            systemImage: "moon.stars.fill",
            tint: .indigo,
            primary: "Tonight: aim for \(bedLabel)",
            secondary: "You usually wake around \(wakeLabel) — staying close to your normal window keeps debt from compounding."
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.indigo.opacity(0.5))
                .padding(.top, 28)
            Text("Not enough sleep data yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Rung needs three nights of sleep tracking from Apple Health to model your energy curve. Wear your Apple Watch overnight, or log sleep in the Health app, then check back here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Button {
                Task {
                    try? await VerificationService.shared.requestAuthorization()
                    await service.refresh()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                    Text("Connect Apple Health")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.pink.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.pink.opacity(0.32), lineWidth: 0.5)
                )
                .foregroundStyle(.pink)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 30)
    }

    // MARK: - Helpers

    private func headerSubtitle(for band: EnergyBand) -> String {
        switch band {
        case .peak:     return "Best window of the day. If you've got a hard task, do it now."
        case .moderate: return "Solid execution range. Move through your list without overthinking it."
        case .dip:      return "Low-effort window. Reading, light admin, a walk."
        case .low:      return "Running on fumes. Anything beyond essentials can wait."
        }
    }

    private func bandTint(for band: EnergyBand) -> Color {
        switch band {
        case .peak:     return .green
        case .moderate: return .indigo
        case .dip:      return .orange
        case .low:      return .red
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Gauge

/// Circular dial showing the current energy value. Concentric arcs:
/// - background ring (subtle)
/// - filled arc up to `value` (band-tinted gradient)
/// - large numeric readout in the centre
private struct EnergyGauge: View {
    let value: Double  // 0..100
    let band: EnergyBand

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background ring — full sweep, low opacity. Anchors the eye
            // to the dial circumference even when value is small.
            Circle()
                .trim(from: 0.075, to: 0.925)
                .stroke(
                    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Filled arc — proportional to value. Same start angle as the
            // background so the head doesn't drift.
            let trim = 0.075 + (0.925 - 0.075) * (value / 100)
            Circle()
                .trim(from: 0.075, to: max(0.076, trim))
                .stroke(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)

            VStack(spacing: 2) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of 100")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
            }
        }
    }

    private var gradientColors: [Color] {
        switch band {
        case .peak:     return [Color.green, Color(red: 0.10, green: 0.65, blue: 0.45)]
        case .moderate: return [Color.indigo, Color(red: 0.30, green: 0.40, blue: 0.85)]
        case .dip:      return [Color.orange, Color(red: 0.92, green: 0.50, blue: 0.10)]
        case .low:      return [Color.red, Color(red: 0.78, green: 0.18, blue: 0.20)]
        }
    }
}

// MARK: - Curve

/// Hand-drawn energy-curve chart. Plots `forecast.curve(...)` from
/// 6 AM to midnight (or wider if the user's wake/bed times push outside),
/// fills a soft gradient under the line, and overlays markers for "now",
/// next peak, and next dip.
private struct EnergyCurveChart: View {
    let forecast: EnergyForecast

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let chartStart = calendar.date(byAdding: .hour, value: 6, to: startOfToday) ?? startOfToday
            let chartEnd = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            let samples = forecast.curve(from: chartStart, until: chartEnd, step: 15 * 60)
            let now = Date()

            ZStack {
                // Grid lines at 25/50/75
                ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                    Path { path in
                        let y = geo.size.height * (1 - ratio)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04),
                        style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                    )
                }

                // Filled area under the curve.
                Path { path in
                    guard let first = samples.first else { return }
                    let firstPoint = pointFor(sample: first, in: geo.size, range: chartStart...chartEnd)
                    path.move(to: CGPoint(x: firstPoint.x, y: geo.size.height))
                    path.addLine(to: firstPoint)
                    for sample in samples.dropFirst() {
                        path.addLine(to: pointFor(sample: sample, in: geo.size, range: chartStart...chartEnd))
                    }
                    if let last = samples.last {
                        let lastPoint = pointFor(sample: last, in: geo.size, range: chartStart...chartEnd)
                        path.addLine(to: CGPoint(x: lastPoint.x, y: geo.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.32), Color.indigo.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // The curve itself.
                Path { path in
                    guard let first = samples.first else { return }
                    path.move(to: pointFor(sample: first, in: geo.size, range: chartStart...chartEnd))
                    for sample in samples.dropFirst() {
                        path.addLine(to: pointFor(sample: sample, in: geo.size, range: chartStart...chartEnd))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.indigo, Color(red: 0.30, green: 0.40, blue: 0.88)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Now marker — vertical line + filled dot at curve height.
                if now >= chartStart && now <= chartEnd {
                    let nowEnergy = forecast.energy(at: now)
                    let nowPoint = pointFor(
                        sample: (now, nowEnergy),
                        in: geo.size,
                        range: chartStart...chartEnd
                    )
                    Path { path in
                        path.move(to: CGPoint(x: nowPoint.x, y: 0))
                        path.addLine(to: CGPoint(x: nowPoint.x, y: geo.size.height))
                    }
                    .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1))
                    Circle()
                        .fill(Color.indigo)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .position(nowPoint)
                }

                // X-axis labels at every 6h tick. Static label set keeps
                // layout predictable; dynamic ticks would jitter as the
                // chart updates.
                hourLabels(geo: geo, range: chartStart...chartEnd)
            }
        }
    }

    private func pointFor(
        sample: (Date, Double),
        in size: CGSize,
        range: ClosedRange<Date>
    ) -> CGPoint {
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let elapsed = sample.0.timeIntervalSince(range.lowerBound)
        let xRatio = total > 0 ? elapsed / total : 0
        let yRatio = sample.1 / 100
        return CGPoint(
            x: size.width * xRatio,
            y: size.height * (1 - yRatio)
        )
    }

    @ViewBuilder
    private func hourLabels(geo: GeometryProxy, range: ClosedRange<Date>) -> some View {
        let calendar = Calendar.current
        let labels: [(label: String, ratio: Double)] = stride(from: 0, through: 4, by: 1).compactMap { i in
            let interval = range.upperBound.timeIntervalSince(range.lowerBound)
            let ratio = Double(i) / 4
            let date = range.lowerBound.addingTimeInterval(interval * ratio)
            let hour = calendar.component(.hour, from: date)
            let label: String
            switch hour {
            case 0:        label = "12a"
            case 12:       label = "12p"
            case 1...11:   label = "\(hour)a"
            default:       label = "\(hour - 12)p"
            }
            return (label, ratio)
        }
        ForEach(Array(labels.enumerated()), id: \.offset) { _, item in
            Text(item.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .position(x: geo.size.width * item.ratio, y: geo.size.height + 8)
        }
    }
}

// MARK: - Insight row

/// Reusable two-line row used by every section under the gauge. Keeps
/// the visual rhythm consistent (icon → primary → secondary) so the
/// whole view reads as a single design system.
private struct InsightRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let tint: Color
    let primary: String
    let secondary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(colorScheme == .dark ? 0.18 : 0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(.system(size: 14, weight: .semibold))
                Text(secondary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}
