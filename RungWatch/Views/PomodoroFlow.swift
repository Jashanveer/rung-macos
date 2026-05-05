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
        ZStack {
            // Breathing analog ring fills most of the watch face.
            ringHero
            controlPuck
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .onReceive(timer) { _ in
            tick &+= 1
            if remainingSeconds <= 0 && !didFinish {
                didFinish = true
                #if canImport(WatchKit)
                WKInterfaceDevice.current().play(.success)
                #endif
                // Tap the underlying habit done — Pomodoro completion
                // is the user's actionable commitment for this entry.
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
        .navigationTitle("Focus")
    }

    // MARK: - Hero ring

    private var ringHero: some View {
        GeometryReader { geo in
            let ringSize = min(geo.size.width, geo.size.height - 50)
            let radius = (ringSize - 10) / 2
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

                // Tick marks every 5 minutes — 12 ticks total like the
                // hour markers on an analog watch dial.
                ForEach(0..<12) { i in
                    let isMajor = i % 3 == 0
                    Capsule()
                        .fill(Color.white.opacity(isMajor ? 0.4 : 0.18))
                        .frame(width: 1.2, height: isMajor ? 7 : 4)
                        .offset(y: -radius - 2)
                        .rotationEffect(.degrees(Double(i) * 30))
                }

                VStack(spacing: 2) {
                    Text(isPaused ? "PAUSED" : "FOCUS")
                        .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                        .tracking(2.0)
                        .foregroundStyle(WatchTheme.cAmber)
                    Text(timeLabel)
                        .font(.system(size: 32 * scale, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.ink)
                    Text(habit.title)
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(WatchTheme.inkSoft)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPaused ? 1.0 : breatheScale)
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: tick / 8)
        }
        .padding(.bottom, 38)
    }

    // MARK: - Controls

    private var controlPuck: some View {
        VStack {
            Spacer()
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
            .padding(.bottom, 4)
        }
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
