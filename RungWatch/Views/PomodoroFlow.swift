import SwiftUI
import Combine
#if canImport(WatchKit)
import WatchKit
#endif

/// Pomodoro flow on the watch — long-press a task and you drop straight
/// into the running view (no intermediate confirm sheet). Two screens:
///   • Running — V6 D layout: warm peach dual ring, "FOCUS" caps label,
///     two-line task title that wraps for real-world names, big timer
///     digits, glass pause/+5 controls.
///   • Break  — deep-blue cobalt rest mode. 5-minute cooldown ring with
///     "BREAK" caps label, the same timer typography, and an End pill.
///     Auto-pushed when the focus ring hits zero so the user flows
///     focus → rest without an extra tap.
///
/// When the focus timer hits zero we fire the success haptic and toggle
/// the underlying task done so the long-press itself counts as the
/// commit; the break view never re-toggles the task — it's purely a
/// rest companion.

// MARK: - Running view

/// 25-minute analog timer with a breathing ring + tick marks. Pause /
/// resume / +5 controls live in a glass puck below the ring. Crown
/// scrolls would normally adjust duration on iOS — we keep that simple
/// here and treat the timer as fire-and-forget; the design doc allowed
/// for a more elaborate crown gesture but the user wants to keep the
/// flow shallow.
struct PomodoroRunningView: View {
    let habit: WatchSnapshot.WatchHabit
    let onFinish: () -> Void
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.watchFontScale) private var scale: Double

    /// Total seconds for the session. Default 25:00 — the design's
    /// recommended pomodoro length. Users can extend via the +5 puck.
    @State private var totalSeconds: Int = 25 * 60
    /// Timestamp when the session started (or last resumed). Drives a
    /// monotonic countdown rather than a tick-count to survive crown /
    /// digital-wakeup throttling.
    @State private var startedAt: Date = Date()
    /// Seconds already elapsed before the most recent pause. Adding
    /// `Date().timeIntervalSince(startedAt)` while running gives the
    /// total elapsed time without per-tick drift.
    @State private var pausedElapsed: Double = 0
    @State private var isPaused: Bool = false
    @State private var didFinish: Bool = false

    /// Per-second tick so SwiftUI redraws. The countdown maths uses the
    /// real clock, not this counter — `tick` only forces re-evaluation.
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ringHero
            Spacer(minLength: 0)
            controlPuck
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            tick &+= 1
            if remainingSeconds <= 0 && !didFinish {
                didFinish = true
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.success)
                #endif
                if !habit.isCompleted {
                    session.toggleHabit(id: habit.id)
                }
            }
        }
        .navigationDestination(isPresented: $didFinish) {
            PomodoroBreakView(habit: habit, onClose: {
                onFinish()
                dismiss()
            })
        }
        .watchWashNavigationBackground(.amber)
        .toolbar(.hidden, for: .automatic)
        .overlay(alignment: .topLeading) { backButton }
    }

    /// Glass back chevron pinned to the top-left corner. Sits in the
    /// empty slack between the screen edge and the ring's bounding box
    /// so it doesn't crowd the V6 D layout. Cancels the running session
    /// outright — no commit, no break — and pops the cover back to
    /// Habits. Mirrors the watch's standard left-edge swipe-back, just
    /// made discoverable.
    private var backButton: some View {
        Button {
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.click)
            #endif
            onFinish()
            dismiss()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WatchTheme.ink.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().stroke(WatchTheme.glassStroke, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.top, 2)
    }

    // MARK: - Hero ring

    /// V6 D layout: square peach dual ring with a centered FOCUS caps
    /// label, a two-line task title that wraps for real-world names
    /// like "Q3 launch deck · review", and a big monospaced timer.
    /// Title clamp is 2 lines because the design's V6 D variant is the
    /// "long titles handled gracefully" sub-variant — the whole point
    /// of D over A is title wrapping.
    private var ringHero: some View {
        ZStack {
            GeometryReader { geo in
                let radius = (min(geo.size.width, geo.size.height) - 6) / 2
                ZStack {
                    // Track — faint white hairline
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 6)

                    // Soft outer glow — blurred peach copy of the
                    // progress arc, mirrors the design's filter:blur(3px)
                    // glow underlay.
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [WatchTheme.cPeach, WatchTheme.cAmber, WatchTheme.cRose],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 4)
                        .opacity(0.55)

                    // Crisp progress arc on top
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [WatchTheme.cPeach, WatchTheme.cAmber, WatchTheme.cRose],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: WatchTheme.cAmber.opacity(0.55), radius: 6)
                        .animation(WatchMotion.smooth, value: progressFraction)

                    // 12 tick marks (5-min divisions). Major every 3.
                    ForEach(0..<12) { i in
                        let isMajor = i % 3 == 0
                        Capsule()
                            .fill(Color.white.opacity(isMajor ? 0.4 : 0.18))
                            .frame(width: 1.2, height: isMajor ? 7 : 4)
                            .offset(y: -radius - 2)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                }
            }

            // Center stack — V6 D order: caps label → 2-line title → timer.
            // Padding leaves room inside the ring; the title is the only
            // thing allowed to wrap, and it caps at 2 lines per the design.
            VStack(spacing: 3) {
                Text(isPaused ? "PAUSED" : "FOCUS")
                    .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(WatchTheme.cAmber)
                Text(habit.title)
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.ink.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .lineSpacing(1)
                    .padding(.horizontal, 22)
                Text(timeLabel)
                    .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .kerning(-0.5)
                    .foregroundStyle(WatchTheme.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 6)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 4)
        .scaleEffect(isPaused ? 1.0 : breatheScale)
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: tick / 8)
    }

    // MARK: - Controls

    private var controlPuck: some View {
        HStack(spacing: 10) {
            Button {
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.click)
                #endif
                if isPaused {
                    startedAt = Date()
                    isPaused = false
                } else {
                    pausedElapsed = elapsedSeconds
                    isPaused = true
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .liquidGlassSurface(
                        cornerRadius: 999,
                        tint: WatchTheme.cAmber,
                        strong: true
                    )
            }
            .buttonStyle(WatchPressStyle())

            Button {
                totalSeconds += 5 * 60
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.success)
                #endif
            } label: {
                Text("+5")
                    .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .liquidGlassSurface(cornerRadius: 999)
            }
            .buttonStyle(WatchPressStyle())
        }
        .padding(.top, 6)
    }

    // MARK: - Maths

    private var elapsedSeconds: Double {
        if isPaused { return pausedElapsed }
        return pausedElapsed + Date().timeIntervalSince(startedAt)
    }

    private var remainingSeconds: Int {
        max(0, totalSeconds - Int(elapsedSeconds))
    }

    private var progressFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(totalSeconds - remainingSeconds) / Double(totalSeconds)))
    }

    private var timeLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Subtle breathing scale — the ring inhales 1.5% and back over 4s
    /// while running. Mirrors the design's `@keyframes breathe`.
    private var breatheScale: CGFloat {
        let phase = Double(tick % 8) / 8.0 * .pi * 2
        return 1.0 + 0.012 * CGFloat(sin(phase))
    }
}

// MARK: - Break view

/// 5-minute break countdown with a deep-blue cobalt wash — the rest
/// counterpart to the warm focus mode. Auto-starts when the focus ring
/// finishes; the user can End early or wait for the success haptic.
/// Mirrors PomodoroRunningView's structure (ring + caps label + timer
/// + control puck) so the user re-uses muscle memory across both
/// modes; only the palette and the label differ.
struct PomodoroBreakView: View {
    let habit: WatchSnapshot.WatchHabit
    let onClose: () -> Void
    @Environment(\.watchFontScale) private var scale: Double

    @State private var totalSeconds: Int = 5 * 60
    @State private var startedAt: Date = Date()
    @State private var pausedElapsed: Double = 0
    @State private var isPaused: Bool = false
    @State private var didFinish: Bool = false
    @State private var tick: Int = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ringHero
            Spacer(minLength: 0)
            controlPuck
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            tick &+= 1
            if remainingSeconds <= 0 && !didFinish {
                didFinish = true
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.success)
                #endif
                onClose()
            }
        }
        .watchWashNavigationBackground(.deepBlue)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
        .overlay(alignment: .topLeading) { backButton }
    }

    /// Glass back chevron — closes the entire Pomodoro flow back to
    /// Habits. The focus session already toggled the task done before
    /// pushing here, so going back from the break has nothing left to
    /// commit; tapping back is the same as letting the 5-minute ring
    /// finish naturally.
    private var backButton: some View {
        Button {
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.click)
            #endif
            onClose()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WatchTheme.ink.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().stroke(WatchTheme.glassStroke, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.top, 2)
    }

    // MARK: - Hero ring

    /// Cool cyan→deep-blue dual ring. Same V6 D bone structure as the
    /// focus mode but the gradient leans cool (cyan → deep blue → violet)
    /// and the "BREAK" caps label is cyan instead of amber. Reads
    /// instantly as "rest mode" without any text label.
    private var ringHero: some View {
        ZStack {
            GeometryReader { geo in
                let radius = (min(geo.size.width, geo.size.height) - 6) / 2
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [WatchTheme.cCyan, WatchTheme.cDeepBlue, WatchTheme.cViolet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 4)
                        .opacity(0.55)

                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [WatchTheme.cCyan, WatchTheme.cDeepBlue, WatchTheme.cViolet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: WatchTheme.cCyan.opacity(0.55), radius: 6)
                        .animation(WatchMotion.smooth, value: progressFraction)

                    ForEach(0..<12) { i in
                        let isMajor = i % 3 == 0
                        Capsule()
                            .fill(Color.white.opacity(isMajor ? 0.4 : 0.18))
                            .frame(width: 1.2, height: isMajor ? 7 : 4)
                            .offset(y: -radius - 2)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                }
            }

            VStack(spacing: 3) {
                Text(isPaused ? "PAUSED" : "BREAK")
                    .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(WatchTheme.cCyan)
                Text("Stand · breathe")
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.ink.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                Text(timeLabel)
                    .font(.system(size: 26 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .kerning(-0.5)
                    .foregroundStyle(WatchTheme.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 6)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 4)
        .scaleEffect(isPaused ? 1.0 : breatheScale)
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: tick / 8)
    }

    // MARK: - Controls

    /// Pause toggle on the left, End pill on the right. End closes the
    /// whole Pomodoro flow back to the Habits tab — the focus session
    /// already toggled the task done before pushing here, so there's
    /// nothing left to commit.
    private var controlPuck: some View {
        HStack(spacing: 10) {
            Button {
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.click)
                #endif
                if isPaused {
                    startedAt = Date()
                    isPaused = false
                } else {
                    pausedElapsed = elapsedSeconds
                    isPaused = true
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .liquidGlassSurface(
                        cornerRadius: 999,
                        tint: WatchTheme.cCyan,
                        strong: true
                    )
            }
            .buttonStyle(WatchPressStyle())

            Button {
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.click)
                #endif
                onClose()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .heavy))
                    Text("End")
                        .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                }
                .tracking(0.4)
                .foregroundStyle(WatchTheme.cCyan)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .liquidGlassSurface(cornerRadius: 999)
            }
            .buttonStyle(WatchPressStyle())
        }
        .padding(.top, 6)
    }

    // MARK: - Maths

    private var elapsedSeconds: Double {
        if isPaused { return pausedElapsed }
        return pausedElapsed + Date().timeIntervalSince(startedAt)
    }

    private var remainingSeconds: Int {
        max(0, totalSeconds - Int(elapsedSeconds))
    }

    private var progressFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(totalSeconds - remainingSeconds) / Double(totalSeconds)))
    }

    private var timeLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var breatheScale: CGFloat {
        let phase = Double(tick % 8) / 8.0 * .pi * 2
        return 1.0 + 0.012 * CGFloat(sin(phase))
    }
}
