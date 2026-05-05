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
    /// User's habits + tasks. Drives the per-task pins on the energy
    /// chart so the curve shows where the user's actual day lands
    /// against their alertness rather than generic "Focus / Move" stamps.
    var habits: [Habit] = []

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
        // Tick every minute so the "now" line, suggestion time, and any
        // task pin whose time has passed all stay fresh while the user
        // sits on this tab. Without this, opening the view at 11 AM and
        // checking back at 1 PM would show stale annotations.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(spacing: 18) {
                    if let snapshot = service.snapshot, let forecast = service.forecast {
                        headerSection(snapshot: snapshot, forecast: forecast, now: context.date)
                        let suggestion = HabitTimeSuggestion.suggest(
                            events: calendarService.todaysEvents,
                            forecast: forecast,
                            now: context.date
                        )
                        PeakShapeBadge(forecast: forecast)
                        EnergyCurveChart(
                            forecast: forecast,
                            now: context.date,
                            tasks: taskPins(forecast: forecast, now: context.date)
                        )
                            .frame(height: 200)
                        if let suggestion, suggestion.time > context.date {
                            suggestionCallout(suggestion)
                        }
                        staleDataNoticeIfNeeded()
                        sleepDebtSection(snapshot: snapshot)
                        bedtimeSection(snapshot: snapshot)
                        melatoninWindowSection(forecast: forecast)
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            // Refresh on appear so the gauge reflects new sleep data the
            // moment the user opens the tab. Cheap — the service is a
            // singleton and HK queries are cached internally.
            await service.refresh()
        }
    }

    /// Build chart pins for tasks (with `dueAt` today) and habits with a
    /// reminder window today. Only future times are surfaced — a pin in
    /// the past is just chart clutter, and the user explicitly asked for
    /// the suggested time to land after the current time.
    private func taskPins(forecast: EnergyForecast, now: Date) -> [EnergyTaskPin] {
        let calendar = Calendar.current
        let chartStart = forecast.wakeTime
        let chartEnd = forecast.bedTime
        let todayKey = calendar.startOfDay(for: now)

        var pins: [EnergyTaskPin] = []
        for habit in habits where !habit.isArchived {
            // Tasks: pin at dueAt when the due is today and still ahead.
            if habit.entryType == .task,
               let due = habit.dueAt,
               calendar.isDate(due, inSameDayAs: now),
               due > now,
               due >= chartStart, due <= chartEnd {
                pins.append(EnergyTaskPin(name: habit.title, time: due, color: .pink))
                continue
            }
            // Habits with a reminder window: pin at the window's hour
            // when it's today and still ahead and not yet completed.
            if habit.entryType == .habit,
               let raw = habit.reminderWindow,
               let window = HabitReminderWindow(rawValue: raw) {
                guard let pinned = calendar.date(
                    bySettingHour: window.hour, minute: 0, second: 0, of: todayKey
                ), pinned > now,
                  pinned >= chartStart, pinned <= chartEnd else { continue }
                let dayKey = DateKey.key(for: now)
                if habit.isSatisfied(on: dayKey) { continue }
                pins.append(EnergyTaskPin(name: habit.title, time: pinned, color: .indigo))
            }
        }
        // Earliest first so adjacency-based collision logic in the chart
        // can dodge labels in render order.
        return pins.sorted { $0.time < $1.time }
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
    private func headerSection(snapshot: SleepSnapshot, forecast: EnergyForecast, now: Date) -> some View {
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
            // iPad gets the same stay-where-you-are message as macOS —
            // Apple Watch pairs to iPhone, so iPad's HealthKit store is
            // almost always empty. Skip the connect button there.
            if UIDevice.current.userInterfaceIdiom != .pad {
            // Only iPhone can read HealthKit on a native app. macOS / iPad
            // users get a stay-where-you-are message above instead of a
            // button that wouldn't actually do anything.
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
        if UIDevice.current.userInterfaceIdiom == .pad { return "iphone.gen3" }
        return "moon.zzz"
        #endif
    }

    private var emptyStateTitle: String {
        #if os(macOS)
        return "Track sleep on your iPhone"
        #else
        if UIDevice.current.userInterfaceIdiom == .pad { return "Track sleep on your iPhone" }
        return "Not enough sleep data yet"
        #endif
    }

    private var emptyStateBody: String {
        #if os(macOS)
        return "Apple Health is only available on iPhone. Open Rung on your phone, grant Health access, and your energy curve will sync here automatically once you've logged a few nights of sleep."
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "Apple Health pairs with iPhone, not iPad. Open Rung on your phone, grant Health access, and your energy curve will sync here automatically once you've logged a few nights of sleep."
        }
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
        // Stack title + detail vertically so the detail can wrap to a
        // second line on iPhone instead of getting tail-truncated, and
        // raise the foreground style to `.primary` (not `.secondary`)
        // so the message reads cleanly on dark iPad — `.secondary`
        // there resolves to a near-transparent gray that vanishes
        // against the deep navy background.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(detailColor(tint: tint))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Capsule clipped a multi-line label off — move to a rounded
        // rectangle that grows with the wrapping text.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.40 : 0.22), lineWidth: 0.5)
        )
    }

    /// Detail-line foreground that stays legible in both modes. `.primary`
    /// at 0.85 opacity in dark mode reads cleanly against the tinted
    /// fill; `.secondary` was washing out on iPadOS dark.
    private func detailColor(tint: Color) -> Color {
        colorScheme == .dark
            ? Color.primary.opacity(0.85)
            : Color.primary.opacity(0.62)
    }
}

// MARK: - Curve

/// One pin on the energy chart for a user task or habit. Drawn as a
/// vertical line + the task's title above the curve so the user sees
/// where their actual day lands against their alertness rather than
/// generic "Focus / Move" stamps.
struct EnergyTaskPin: Identifiable {
    let id = UUID()
    let name: String
    let time: Date
    let color: Color
}

/// Today's energy curve, plotted from the user's typical wake time to
/// their typical bedtime. Three biological anchors are annotated so the
/// curve stays readable:
///
/// - **Wake** — left axis label, anchors the morning end of the curve.
/// - **Peak** — circadian acrophase derived from chronotype + wake.
/// - **Melatonin (DLMO)** — predicted dim-light melatonin onset, the
///   biological start of the wind-down window.
///
/// Plus the user's own tasks and habits at their scheduled times — pins
/// only render when their time is still ahead of `now`, so the chart
/// reflects "what's still on the board today" instead of dragging
/// already-past clutter forward.
private struct EnergyCurveChart: View {
    let forecast: EnergyForecast
    /// Frozen "now" for this render pass — passed in by the parent's
    /// TimelineView so the now line, future-only filtering, and pin
    /// labels all agree on a single timestamp.
    let now: Date
    var tasks: [EnergyTaskPin] = []

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
                // so the curve and annotations sit on top.
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

                // Biological anchors: wake (already at the left axis),
                // peak, and DLMO. Render in tag-row order so labels can
                // dodge each other along the top strip.
                let anchorTags: [AnchorTag] = anchorPositions(in: geo.size, range: safeRange)
                ForEach(anchorTags) { anchor in
                    Path { path in
                        path.move(to: CGPoint(x: anchor.x, y: 16))
                        path.addLine(to: CGPoint(x: anchor.x, y: geo.size.height))
                    }
                    .stroke(
                        anchor.color.opacity(0.42),
                        style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                    )
                    Text(anchor.label)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(anchor.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(anchor.color.opacity(colorScheme == .dark ? 0.22 : 0.16))
                        )
                        .position(x: anchor.x, y: 8)
                }

                // User task pins. Each shows the task title at the top
                // of the chart and a dot on the curve at that time. Only
                // future-time pins are passed in by the parent — past
                // tasks would just be chart clutter.
                let taskLayouts = layoutTaskPins(geo: geo, range: safeRange, anchors: anchorTags)
                ForEach(taskLayouts) { layout in
                    let pin = layout.pin
                    Path { path in
                        path.move(to: CGPoint(x: layout.x, y: layout.labelY + 8))
                        path.addLine(to: CGPoint(x: layout.x, y: geo.size.height))
                    }
                    .stroke(
                        pin.color.opacity(0.32),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                    )
                    Circle()
                        .fill(pin.color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                        .position(x: layout.x, y: layout.curveY)
                    Text(pin.name)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(pin.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(pin.color.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(pin.color.opacity(0.32), lineWidth: 0.5)
                        )
                        .frame(maxWidth: layout.maxLabelWidth)
                        .position(x: layout.x, y: layout.labelY)
                }

                // X-axis labels: wake / mid / bed.
                axisLabels(geo: geo, range: safeRange)
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

    private func anchorPositions(
        in size: CGSize,
        range: ClosedRange<Date>
    ) -> [AnchorTag] {
        var anchors: [AnchorTag] = []
        if range.contains(forecast.circadianPeak) {
            let x = pointFor(sample: (forecast.circadianPeak, 0), in: size, range: range).x
            anchors.append(AnchorTag(
                label: "Peak",
                x: x,
                color: Color(red: 0.20, green: 0.62, blue: 0.42)
            ))
        }
        if range.contains(forecast.predictedDLMO) {
            let x = pointFor(sample: (forecast.predictedDLMO, 0), in: size, range: range).x
            anchors.append(AnchorTag(
                label: "Melatonin",
                x: x,
                color: Color(red: 0.46, green: 0.36, blue: 0.86)
            ))
        }
        return anchors.sorted { $0.x < $1.x }
    }

    private func layoutTaskPins(
        geo: GeometryProxy,
        range: ClosedRange<Date>,
        anchors: [AnchorTag]
    ) -> [TaskLayout] {
        let topPadding: CGFloat = 22
        let labelHeight: CGFloat = 16
        let minSpacing: CGFloat = 4

        struct PlacedRow {
            var rightEdge: CGFloat
            var rowIndex: Int
        }
        var placedRows: [PlacedRow] = []

        return tasks.compactMap { pin -> TaskLayout? in
            guard range.contains(pin.time) else { return nil }
            let curvePoint = pointFor(
                sample: (pin.time, forecast.energy(at: pin.time)),
                in: geo.size, range: range
            )
            let approxLabelWidth = min(96, max(52, CGFloat(pin.name.count) * 5.5 + 14))
            let halfLabel = approxLabelWidth / 2
            let leftEdge = curvePoint.x - halfLabel
            let rightEdge = curvePoint.x + halfLabel

            // Avoid stomping the anchor labels by row-stacking when too close.
            let collidesWithAnchor = anchors.contains { abs($0.x - curvePoint.x) < halfLabel + 24 }
            var chosenRow = 0
            if collidesWithAnchor {
                chosenRow = 1
            }
            // Search for an open row that doesn't overlap any prior label.
            while placedRows.contains(where: { $0.rowIndex == chosenRow && leftEdge < $0.rightEdge + minSpacing }) {
                chosenRow += 1
            }
            placedRows.append(PlacedRow(rightEdge: rightEdge, rowIndex: chosenRow))

            let labelY = topPadding + CGFloat(chosenRow) * (labelHeight + 2)
            return TaskLayout(
                pin: pin,
                x: curvePoint.x,
                curveY: curvePoint.y,
                labelY: labelY,
                maxLabelWidth: approxLabelWidth
            )
        }
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
}

private struct AnchorTag: Identifiable {
    let id = UUID()
    let label: String
    let x: CGFloat
    let color: Color
}

private struct TaskLayout: Identifiable {
    let id = UUID()
    let pin: EnergyTaskPin
    let x: CGFloat
    let curveY: CGFloat
    let labelY: CGFloat
    let maxLabelWidth: CGFloat
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
