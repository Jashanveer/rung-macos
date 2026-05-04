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
    @StateObject private var calendarService = CalendarService.shared

    @Environment(\.colorScheme) private var colorScheme
    @State private var refreshing = false
    /// True after the user tapped "Connect Apple Health" once. iOS won't
    /// re-prompt for HK access if the user already answered, so the
    /// second tap routes straight to the Health app where they can flip
    /// the toggle by hand. We also surface an alert with the same option
    /// when the first tap returned without producing any data.
    /// Hydrated from `UserDefaults` on appear — same breadcrumb that
    /// `PermissionsStatusCard` writes — so navigating away and back
    /// doesn't reset the button to "Connect" after a real grant.
    @State private var didRequestHealthKit = false
    @State private var isRequestingHealthKit = false
    @State private var showHealthAccessAlert = false
    /// `true` = "we can't read sleep data" (offer Open-Health).
    /// `false` = "access is fine, just not enough nights tracked yet."
    @State private var healthAlertIsAccessIssue = true

    #if os(iOS)
    /// Same key used by `PermissionsStatusCard` so both surfaces share
    /// one source of truth for "user has been prompted at least once".
    private static let healthKitAskedKey = "PermissionsStatusCard.healthKitAsked.v1"
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let snapshot = service.snapshot, let forecast = service.forecast {
                    headerSection(snapshot: snapshot, forecast: forecast)
                    let suggestion = HabitTimeSuggestion.suggest(
                        events: calendarService.todaysEvents,
                        forecast: forecast
                    )
                    PeakShapeBadge(forecast: forecast)
                    EnergyCurveChart(forecast: forecast, suggestion: suggestion)
                        .frame(height: 180)
                    if let suggestion {
                        suggestionCallout(suggestion)
                    }
                    staleDataNoticeIfNeeded()
                    sleepDebtSection(snapshot: snapshot)
                    recommendationsSection(forecast: forecast)
                    bedtimeSection(snapshot: snapshot)
                    melatoninWindowSection(forecast: forecast)
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

    /// Friendly callout below the curve that names the suggested time
    /// in plain English and explains why it was picked. Mirrors the
    /// "Best slot" pin on the chart so users connect the two.
    @ViewBuilder
    private func suggestionCallout(_ suggestion: HabitTimeSuggestion.Suggestion) -> some View {
        let gold = Color(red: 0.94, green: 0.74, blue: 0.24)
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(gold)
                .frame(width: 28, height: 28)
                .background(Circle().fill(gold.opacity(colorScheme == .dark ? 0.18 : 0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.label)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Suggested by your calendar gaps + energy curve. Open a habit to schedule it for then.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(gold.opacity(colorScheme == .dark ? 0.10 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(gold.opacity(0.35), lineWidth: 0.5)
        )
    }

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

            if let chronotype = snapshot.chronotype {
                ChronotypeBadge(
                    chronotype: chronotype,
                    midpointLabel: snapshot.midpointLabel ?? "",
                    peakLabel: timeString(forecast.circadianPeak)
                )
                .padding(.top, 4)
            }
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
        let windows = EnergyCurveChart.windows(for: forecast)

        VStack(spacing: 10) {
            ForEach(windows) { window in
                InsightRow(
                    systemImage: icon(for: window.kind),
                    tint: window.tint,
                    primary: "\(headline(for: window.kind)) · \(timeString(window.time))",
                    secondary: copy(for: window.kind)
                )
            }
        }
    }

    private func icon(for kind: EnergyWindow.Kind) -> String {
        switch kind {
        case .focus:    return "brain.head.profile"
        case .recover:  return "tray.full.fill"
        case .move:     return "figure.run"
        case .windDown: return "moon.stars.fill"
        }
    }

    private func headline(for kind: EnergyWindow.Kind) -> String {
        switch kind {
        case .focus:    return "Focus window"
        case .recover:  return "Recover · post-lunch dip"
        case .move:     return "Movement window"
        case .windDown: return "Wind-down"
        }
    }

    private func copy(for kind: EnergyWindow.Kind) -> String {
        switch kind {
        case .focus:
            return "Office work, deep focus, learning. Cortisol is at its highest, your prefrontal cortex is sharp — protect this time for analytical work."
        case .recover:
            return "Laundry, dishes, cooking, errands. Your alertness dips after lunch — pair low-cognition chores so your peaks aren't burnt on housework. Run a wash while you cook."
        case .move:
            return "Gym, runs, walks, social calls. Body temperature is at its highest of the day for peak physical performance, while cognitive demand naturally relaxes — pair the two."
        case .windDown:
            return "Reading, journaling, planning tomorrow. Skip intense work and bright screens so melatonin can rise on schedule."
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

    /// Predicted dim-light melatonin onset row. The deep-research model
    /// derives DLMO as wake + 14h, shifted earlier/later when the
    /// chronotype is stable. Surfacing it explicitly tells the user when
    /// their biological wind-down begins — the cliff before bedtime
    /// where bright screens, caffeine, and intense work cost the most.
    @ViewBuilder
    private func melatoninWindowSection(forecast: EnergyForecast) -> some View {
        let dlmoLabel = timeString(forecast.predictedDLMO)
        let confidenceCopy = forecast.chronotypeStable
            ? "Anchored to your learned chronotype."
            : "Anchored to your wake time — refines as we learn your chronotype."
        InsightRow(
            systemImage: "drop.halffull",
            tint: Color(red: 0.46, green: 0.36, blue: 0.86),
            primary: "Melatonin window opens \(dlmoLabel)",
            secondary: "Dim screens + skip caffeine ~90 min before this. \(confidenceCopy)"
        )
    }

    /// Stale-data warning surfaced only on macOS when the iPhone hasn't
    /// synced in > 3 days. The model is still useful (chronotype doesn't
    /// shift overnight), but the sleep-debt readout drifts further from
    /// reality every day, so we tell the user to bring iOS up to date.
    @ViewBuilder
    private func staleDataNoticeIfNeeded() -> some View {
        #if os(macOS)
        if let updated = service.snapshotUpdatedAt {
            let age = Date().timeIntervalSince(updated)
            if age > 3 * 86_400 {
                let days = Int(age / 86_400)
                InsightRow(
                    systemImage: "iphone.gen3.slash",
                    tint: .orange,
                    primary: "Last synced \(days)d ago from iPhone",
                    secondary: "Open Rung on your phone to refresh sleep data — your energy debt and chronotype will drift the longer this stays stale."
                )
            }
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.indigo.opacity(0.5))
                .padding(.top, 28)
            Text(emptyStateTitle)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(emptyStateBody)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            #if os(iOS)
            // Only iOS can read HealthKit on a native app. macOS users
            // get a stay-where-you-are message above instead of a button
            // that wouldn't actually do anything.
            Button(action: handleHealthKitTap) {
                HStack(spacing: 6) {
                    if isRequestingHealthKit {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.pink)
                    } else {
                        Image(systemName: didRequestHealthKit ? "arrow.up.right.square.fill" : "heart.text.square.fill")
                    }
                    Text(connectButtonTitle)
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
            .disabled(isRequestingHealthKit)
            .task {
                // Hydrate the asked-state from the shared breadcrumb so
                // navigating away and back doesn't relabel the button to
                // "Connect" after the user already granted access.
                didRequestHealthKit = UserDefaults.standard.bool(forKey: Self.healthKitAskedKey)
            }
            .alert(healthAlertIsAccessIssue ? "Apple Health access needed" : "Not enough sleep tracked yet",
                   isPresented: $showHealthAccessAlert) {
                if healthAlertIsAccessIssue {
                    Button("Open Health") { openHealthApp() }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                if healthAlertIsAccessIssue {
                    Text("iOS only shows the Apple Health prompt once per app. Open the Health app → Browse → Sharing → Apps → Rung → turn on Sleep so Rung can read your data.")
                } else {
                    Text("Rung needs at least 3 nights of sleep tracking to model your energy curve. Wear your Apple Watch overnight or log sleep in the Health app, then check back.")
                }
            }
            #endif
        }
        .padding(.vertical, 30)
    }

    #if os(iOS)
    /// Two-tap behaviour for the Connect-Health button:
    /// 1. First tap → fire `requestAuthorization`. iOS shows the system
    ///    prompt (first-time users only). After it resolves we re-refresh
    ///    and pick one of three outcomes: success (snapshot lands),
    ///    "not enough nights yet" (granted but <3 sleep nights tracked),
    ///    or "no access" (zero sleep samples returned — likely denied).
    /// 2. Subsequent taps → skip straight to opening the Health app via
    ///    its system URL scheme. Settings → Rung is the wrong place for
    ///    HK toggles, which only live inside Health.
    private func handleHealthKitTap() {
        if didRequestHealthKit {
            openHealthApp()
            return
        }
        guard !isRequestingHealthKit else { return }
        Task { @MainActor in
            isRequestingHealthKit = true
            do {
                try await VerificationService.shared.requestAuthorization()
            } catch {
                // HK rarely throws here, but if it does the user just
                // sees an unresponsive button — log so we can debug.
                print("[EnergyView] HealthKit authorization failed: \(error)")
            }
            // Stamp the breadcrumb whether or not the user granted —
            // iOS won't reshow the prompt regardless, so the only
            // meaningful "asked" signal is "we made the call".
            UserDefaults.standard.set(true, forKey: Self.healthKitAskedKey)
            didRequestHealthKit = true
            await service.refresh()
            isRequestingHealthKit = false
            if service.snapshot == nil {
                // Distinguish "we got 1-2 nights — keep tracking" from
                // "we got nothing — likely an access issue". Without
                // this split the user sees "access needed" right after
                // tapping Allow, which feels like a silent failure.
                if let nights = service.lastSleepNightCount, nights > 0 {
                    healthAlertIsAccessIssue = false
                } else {
                    healthAlertIsAccessIssue = true
                }
                showHealthAccessAlert = true
            }
        }
    }

    private var connectButtonTitle: String {
        if isRequestingHealthKit { return "Requesting access…" }
        return didRequestHealthKit ? "Open Health app" : "Connect Apple Health"
    }

    /// Open the Health app via its private URL scheme. Verified working
    /// on iOS 16+; falls back to Settings → Rung when the scheme can't
    /// be opened (e.g. Health app uninstalled — rare but possible on
    /// non-iPhone iPad-OS or restricted devices).
    private func openHealthApp() {
        let healthURL = URL(string: "x-apple-health://")
        let settingsURL = URL(string: UIApplication.openSettingsURLString)
        Task { @MainActor in
            if let healthURL, UIApplication.shared.canOpenURL(healthURL) {
                UIApplication.shared.open(healthURL)
            } else if let settingsURL {
                UIApplication.shared.open(settingsURL)
            }
        }
    }
    #endif

    private var emptyStateIcon: String {
        #if os(macOS)
        return "iphone.gen3"
        #else
        return "moon.zzz"
        #endif
    }

    private var emptyStateTitle: String {
        #if os(macOS)
        return "Track sleep on your iPhone"
        #else
        return "Not enough sleep data yet"
        #endif
    }

    private var emptyStateBody: String {
        #if os(macOS)
        return "Apple Health is only available on iPhone. Open Rung on your phone, grant Health access, and your energy curve will sync here automatically once you've logged a few nights of sleep."
        #else
        return "Rung needs three nights of sleep tracking from Apple Health to model your energy curve. Wear your Apple Watch overnight, or log sleep in the Health app, then check back here."
        #endif
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

// MARK: - Peak shape badge

/// Compact pill below the gauge that names today's curve shape — single
/// broad peak vs likely two-peak day — derived from the model's
/// `bimodalityProbability`. Honest reporting per the deep-research
/// recommendation: don't pretend the same shape always applies; tell
/// the user whether to expect one or two productive windows.
private struct PeakShapeBadge: View {
    let forecast: EnergyForecast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bimodal = forecast.bimodalityProbability >= 0.5
        let icon = bimodal ? "chart.line.uptrend.xyaxis" : "waveform.path"
        let title = bimodal ? "Two-peak day expected" : "Single broad peak"
        let detail = bimodal
            ? "Morning + late-day window — protect both."
            : "One sustained envelope — push hard work into the middle."
        let tint: Color = bimodal
            ? Color(red: 0.18, green: 0.58, blue: 0.86)
            : Color(red: 0.46, green: 0.48, blue: 0.84)
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text("·")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        )
    }
}

// MARK: - Curve

/// Today's energy curve, plotted from the user's typical wake time to
/// their typical bedtime. Three chronobiology windows are annotated:
/// - **Focus** (~3h after wake) — morning cortisol-driven alertness
///   peak. Best for analytical / office work and learning.
/// - **Move** (~7h after wake) — post-prandial / mid-day dip in cognitive
///   demand, but body temperature is climbing. Best for gym, walks,
///   errands, social calls — anything physical or low cog-load.
/// - **Wind-down** (90 min before bed) — circadian alertness has
///   dropped, sleep pressure is high. Best for reading, journaling,
///   planning tomorrow. Avoid intense work and bright screens.
///
/// Sources: Borbély two-process model + Rise Science / Foster
/// chronobiology framework. The window times are heuristics derived
/// from the user's own median wake/bed pair so they shift with the
/// actual schedule instead of using a clock-time default.
private struct EnergyCurveChart: View {
    let forecast: EnergyForecast
    var suggestion: HabitTimeSuggestion.Suggestion? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let chartStart = forecast.wakeTime
            let chartEnd = forecast.bedTime
            let safeRange = chartEnd > chartStart
                ? chartStart...chartEnd
                : chartStart...chartStart.addingTimeInterval(16 * 3600)
            let samples = forecast.curve(from: safeRange.lowerBound, until: safeRange.upperBound, step: 15 * 60)
            let bandSamples = forecast.curveWithBand(from: safeRange.lowerBound, until: safeRange.upperBound, step: 15 * 60)
            let now = Date()
            let windows = EnergyCurveChart.windows(for: forecast)

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

                // Confidence band (mean ± σ). Shaded behind everything else
                // so the curve and annotations sit on top. Wider band when
                // chronotype is unlearned, sample count is low, or sleep
                // debt is high — the model's honest "we're guessing" area.
                Path { path in
                    guard let first = bandSamples.first else { return }
                    let upperFirst = pointFor(
                        sample: (first.time, min(100, first.mean + first.sigma)),
                        in: geo.size, range: safeRange
                    )
                    path.move(to: upperFirst)
                    for sample in bandSamples.dropFirst() {
                        let upper = pointFor(
                            sample: (sample.time, min(100, sample.mean + sample.sigma)),
                            in: geo.size, range: safeRange
                        )
                        path.addLine(to: upper)
                    }
                    for sample in bandSamples.reversed() {
                        let lower = pointFor(
                            sample: (sample.time, max(0, sample.mean - sample.sigma)),
                            in: geo.size, range: safeRange
                        )
                        path.addLine(to: lower)
                    }
                    path.closeSubpath()
                }
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.18 : 0.12))

                // Filled area under the curve.
                Path { path in
                    guard let first = samples.first else { return }
                    let firstPoint = pointFor(sample: first, in: geo.size, range: safeRange)
                    path.move(to: CGPoint(x: firstPoint.x, y: geo.size.height))
                    path.addLine(to: firstPoint)
                    for sample in samples.dropFirst() {
                        path.addLine(to: pointFor(sample: sample, in: geo.size, range: safeRange))
                    }
                    if let last = samples.last {
                        let lastPoint = pointFor(sample: last, in: geo.size, range: safeRange)
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
                    path.move(to: pointFor(sample: first, in: geo.size, range: safeRange))
                    for sample in samples.dropFirst() {
                        path.addLine(to: pointFor(sample: sample, in: geo.size, range: safeRange))
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

                // Annotated windows — Focus, Move, Wind-down. Each one
                // sits on the curve at the energy level for that time so
                // the badge feels glued to the line rather than floating.
                // Wind-down nudges down when it's at the same x as the
                // DLMO marker so the two labels don't pile on top of
                // each other in the top-right corner.
                let dlmoX = pointFor(
                    sample: (forecast.predictedDLMO, 0),
                    in: geo.size,
                    range: safeRange
                ).x
                ForEach(windows.filter { safeRange.contains($0.time) }) { window in
                    let energy = forecast.energy(at: window.time)
                    let point = pointFor(
                        sample: (window.time, energy),
                        in: geo.size,
                        range: safeRange
                    )
                    let collidesWithDLMO = window.kind == .windDown
                        && abs(point.x - dlmoX) < 36
                    annotation(
                        window: window,
                        at: point,
                        nudgeDown: collidesWithDLMO
                    )
                }

                // Now marker — vertical line + filled dot at curve height.
                if now >= safeRange.lowerBound && now <= safeRange.upperBound {
                    let nowEnergy = forecast.energy(at: now)
                    let nowPoint = pointFor(
                        sample: (now, nowEnergy),
                        in: geo.size,
                        range: safeRange
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

                // Predicted DLMO marker — soft purple vertical line +
                // tiny "DLMO" tag at the top. This is when the model
                // expects the user's biological wind-down to begin;
                // surfacing it makes the wind-down recommendation
                // anchor to a real cue instead of a generic "evening".
                let dlmo = forecast.predictedDLMO
                if dlmo >= safeRange.lowerBound && dlmo <= safeRange.upperBound {
                    let dlmoX = pointFor(
                        sample: (dlmo, 0),
                        in: geo.size,
                        range: safeRange
                    ).x
                    let dlmoTint = Color(red: 0.46, green: 0.36, blue: 0.86)
                    Path { path in
                        path.move(to: CGPoint(x: dlmoX, y: 12))
                        path.addLine(to: CGPoint(x: dlmoX, y: geo.size.height))
                    }
                    .stroke(
                        dlmoTint.opacity(0.42),
                        style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                    )
                    Text("DLMO")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(dlmoTint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(dlmoTint.opacity(colorScheme == .dark ? 0.22 : 0.16))
                        )
                        .position(x: dlmoX, y: 8)
                }

                // Calendar-aware "best slot" marker. Sits above the
                // curve at the suggested time so the user can see why
                // we chose that hour — it's at (or near) their peak.
                // Gold = brand colour, distinguishes from indigo "now".
                //
                // Suppressed when the suggested time is within ~30 min
                // of one of the four window pins (Focus / Recover /
                // Move / Wind-down). The window label already conveys
                // "this is your peak / dip / etc." for that time, so
                // stacking a second pill on the same x makes both
                // unreadable. The bottom-of-chart suggestion callout
                // still names the time in plain English either way.
                if let suggestion, safeRange.contains(suggestion.time) {
                    let energy = forecast.energy(at: suggestion.time)
                    let point = pointFor(
                        sample: (suggestion.time, energy),
                        in: geo.size,
                        range: safeRange
                    )
                    let collidesWithWindow = windows.contains { window in
                        abs(window.time.timeIntervalSince(suggestion.time)) < 30 * 60
                    }
                    if !collidesWithWindow {
                        suggestionAnnotation(at: point)
                    }
                }

                // X-axis labels: wake / mid / peak / bed instead of a
                // generic clock-time set, so the chart anchors to the
                // user's actual day.
                axisLabels(geo: geo, range: safeRange)
            }
        }
    }

    private func annotation(
        window: EnergyWindow,
        at point: CGPoint,
        nudgeDown: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(window.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(window.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(window.tint.opacity(colorScheme == .dark ? 0.20 : 0.14))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(window.tint.opacity(0.32), lineWidth: 0.5)
                )
            Circle()
                .fill(window.tint)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
        }
        // When the wind-down annotation lands at the same x as the DLMO
        // marker (a common case — wind-down sits 90 min before bed,
        // DLMO sits ~30 min after that), drop the pill below the curve
        // instead of stacking on the DLMO label at the top of the chart.
        .position(
            x: point.x,
            y: nudgeDown ? min(point.y + 22, point.y + 22) : max(point.y - 14, 14)
        )
    }

    private func suggestionAnnotation(at point: CGPoint) -> some View {
        let gold = Color(red: 0.94, green: 0.74, blue: 0.24)
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                Text("Best slot")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(gold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(gold.opacity(colorScheme == .dark ? 0.22 : 0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(gold.opacity(0.45), lineWidth: 0.5)
            )
            Circle()
                .fill(gold)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.2))
        }
        .position(x: point.x, y: max(point.y - 16, 16))
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
    private func axisLabels(geo: GeometryProxy, range: ClosedRange<Date>) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "h a"
            return f
        }()
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let stops: [(Date, String)] = [
            (range.lowerBound, "Wake"),
            (range.lowerBound.addingTimeInterval(total / 2), formatter.string(from: range.lowerBound.addingTimeInterval(total / 2)).lowercased()),
            (range.upperBound, "Bed"),
        ]
        ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
            let elapsed = stop.0.timeIntervalSince(range.lowerBound)
            let ratio = total > 0 ? elapsed / total : 0
            Text(stop.1)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .position(x: geo.size.width * ratio, y: geo.size.height + 10)
        }
    }

    /// Four time-of-day windows derived from the bimodal energy curve.
    /// The 12-hour harmonic in `EnergyForecast.circadianAlertness` carves
    /// real local extrema into the curve, so we can find each window
    /// numerically instead of guessing — but we fall back to fractional
    /// offsets if the search misses (e.g., a very short waking day).
    ///
    /// - **Focus** (~3 h after wake) — first morning peak, post-cortisol-
    ///   awakening alertness. Best for analytical / office work, learning,
    ///   anything that needs cognition.
    /// - **Recover** (~7 h after wake) — post-prandial / siesta dip. Best
    ///   for chores, errands, low-cognition admin — laundry, dishes,
    ///   cooking, walking the dog. Don't waste a peak on these.
    /// - **Move** (~10 h after wake) — afternoon acrophase. Body
    ///   temperature is highest, peak performance for HIIT, lifting,
    ///   running. Also a strong second-cognition window for work that
    ///   missed the morning slot.
    /// - **Wind-down** (~90 min before bed) — circadian alertness has
    ///   dropped, sleep pressure is high. Best for reading, journaling,
    ///   planning tomorrow. Avoid intense work and bright screens.
    static func windows(for forecast: EnergyForecast) -> [EnergyWindow] {
        let wake = forecast.wakeTime
        let bed = forecast.bedTime
        let dayLength = bed.timeIntervalSince(wake)

        // Numerical extrema — first morning peak, lunch dip, afternoon
        // peak. nextPeak / nextDip walk the curve in 5-min steps so they
        // surface real features when the bimodal harmonic produces them.
        let morningPeak = forecast.nextPeak(after: wake, until: forecast.circadianPeak)
            ?? wake.addingTimeInterval(dayLength * 0.20)
        let lunchDip = forecast.nextDip(after: morningPeak, until: forecast.circadianPeak)
            ?? wake.addingTimeInterval(dayLength * 0.45)
        // Afternoon peak: search just past the lunch dip to bed.
        let afternoonPeak = forecast.nextPeak(after: lunchDip, until: bed)
            ?? wake.addingTimeInterval(dayLength * 0.65)
        let windDownTime = bed.addingTimeInterval(-90 * 60)

        return [
            EnergyWindow(kind: .focus, label: "Focus", time: morningPeak,
                         tint: Color(red: 0.94, green: 0.74, blue: 0.24)),  // gold
            EnergyWindow(kind: .recover, label: "Recover", time: lunchDip,
                         tint: Color(red: 0.94, green: 0.55, blue: 0.18)),  // warm orange
            EnergyWindow(kind: .move, label: "Move", time: afternoonPeak,
                         tint: .green),
            EnergyWindow(kind: .windDown, label: "Wind-down", time: windDownTime,
                         tint: .indigo),
        ]
    }
}

/// Single annotated window on the energy curve. `label` is what the
/// user reads on the badge; the matching `recommendationsSection`
/// reuses `kind` to look up the long-form copy.
///
/// The four-window vocabulary mirrors `HabitTimeSuggestion.TaskShape` so
/// the per-habit chips and the chart annotations agree on what each
/// time-of-day band means: focus = morning peak, recover = afternoon
/// dip, move = afternoon peak, wind-down = pre-bed.
struct EnergyWindow: Identifiable {
    enum Kind { case focus, recover, move, windDown }
    let id = UUID()
    let kind: Kind
    let label: String
    let time: Date
    let tint: Color
}

// MARK: - Chronotype badge

/// Compact pill that confirms we've learned the user's chronotype from
/// their own midpoint variance instead of falling back to the population
/// default. Shows the bucket (lark / neutral / owl) plus the resolved
/// peak time so the user can sanity-check the model.
private struct ChronotypeBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let chronotype: Chronotype
    let midpointLabel: String
    let peakLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: chronotype.systemImage)
                .font(.system(size: 10, weight: .bold))
            Text(chronotype.label)
                .font(.system(size: 11, weight: .semibold))
            Text("·")
                .foregroundStyle(.tertiary)
            Text("Peak \(peakLabel)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
        )
        .accessibilityLabel("Learned chronotype: \(chronotype.label). Sleep midpoint \(midpointLabel). Peak \(peakLabel).")
    }

    private var tint: Color {
        switch chronotype {
        case .lark:    return .orange
        case .neutral: return .indigo
        case .owl:     return .purple
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

    private var insightSecondaryColor: Color {
        // Boost contrast: in dark mode, the system `.secondary` fades to
        // ~40% white, which is unreadable against the energy view's
        // slight indigo tint. Use 78% white in dark / 65% black in light.
        colorScheme == .dark
            ? Color.white.opacity(0.78)
            : Color.black.opacity(0.65)
    }

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
                    // `.secondary` faded to ~40% in iPad dark mode against
                    // the energy view's slight tint — too low contrast to
                    // read at arm's length. Pin to an explicit white-with-
                    // higher-opacity in dark mode and a darker primary in
                    // light mode so the body copy actually reads.
                    .foregroundStyle(insightSecondaryColor)
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
