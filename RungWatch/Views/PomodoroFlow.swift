import SwiftUI
import Combine
#if canImport(WatchKit)
import WatchKit
#endif

/// Pomodoro flow on the watch — long-press a task and you drop straight
/// into the running view (no intermediate confirm sheet). Two screens:
///   • Running — analog ring with 25-minute breathing countdown,
///     pause/resume + extend pucks
///   • Done — mint celebration with a 5-minute break suggestion
/// When the timer hits zero we fire the success haptic and toggle the
/// underlying task done so the long-press itself counts as the commit.

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
        // Stack ring above the puck — explicit vertical layout means
        // the ring's size is governed by the available width, not by
        // a GeometryReader that subtracts an arbitrary 50pt for the
        // puck (which made the ring collapse to ~120pt on the small
        // 41mm face and clipped the timer to "2…").
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
            PomodoroDoneView(habit: habit) {
                onFinish()
                dismiss()
            }
        }
        .watchWashNavigationBackground(.amber)
        // No `navigationTitle` — the inline status bar already prints
        // "Focus" at the top and an extra system title pushed the
        // hero down so the ring shrank below readable size.
        .toolbar(.hidden, for: .automatic)
    }

    // MARK: - Hero ring

    private var ringHero: some View {
        // Square + aspect-ratio frame keeps the ring round at any
        // available width (the parent VStack hands us a width-bounded
        // slot). No GeometryReader needed.
        ZStack {
            // Track + progress + tick marks live in their own
            // breathing-scaled GeometryReader so the tick offsets
            // know the actual radius without us recomputing it.
            GeometryReader { geo in
                let radius = (min(geo.size.width, geo.size.height) - 6) / 2
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 6)
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

                    // 12 hour-style tick marks (5-min divisions). The
                    // offset puts each tick on the ring's perimeter.
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

            // Center stack — small caps + monospaced timer + task
            // title. Caps tracking pulled in to keep "FOCUS" tight,
            // timer uses a smaller 24pt so even "24:25" fits inside
            // the smaller 41mm ring without truncating to "2…".
            VStack(spacing: 1) {
                Text(isPaused ? "PAUSED" : "FOCUS")
                    .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(WatchTheme.cAmber)
                Text(timeLabel)
                    .font(.system(size: 24 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WatchTheme.ink)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(habit.title)
                    .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 18)
            }
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
        // tick is half-second based, so cycle every 8 ticks (4s) with
        // a sine-based easing to match SwiftUI's repeatForever timing.
        let phase = Double(tick % 8) / 8.0 * .pi * 2
        return 1.0 + 0.012 * CGFloat(sin(phase))
    }
}

// MARK: - Done view

/// Mint celebration screen with an XP toast + a glass row suggesting a
/// 5-minute break. Tap to dismiss back to the task list.
struct PomodoroDoneView: View {
    let habit: WatchSnapshot.WatchHabit
    let onClose: () -> Void
    @Environment(\.watchFontScale) private var scale: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [WatchTheme.cMint, WatchTheme.cCyan.opacity(0.6)],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 36
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: WatchTheme.cMint.opacity(0.55), radius: 10)
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text("Session done")
                    .font(WatchTheme.font(.title, scale: scale, weight: .heavy))
                    .foregroundStyle(WatchTheme.ink)
                Text("25 min · +12 XP")
                    .font(WatchTheme.font(.caption, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.inkSoft)

                Button(action: onClose) {
                    HStack(spacing: 8) {
                        Text("☕")
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Take 5")
                                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                                .foregroundStyle(WatchTheme.ink)
                            Text("Stand · breathe")
                                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(WatchTheme.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(WatchTheme.cAmber)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .liquidGlassSurface(cornerRadius: 12, strong: true)
                }
                .buttonStyle(WatchPressStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .watchWashNavigationBackground(.mint)
        .navigationTitle("Done")
    }
}
