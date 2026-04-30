import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// One pomodoro segment. Drives the colour scheme + length of the timer.
enum FocusPhase: String, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    /// Default cadence: 25/5/15. Caller can override via `FocusController.start(...)`.
    var defaultDuration: TimeInterval {
        switch self {
        case .focus:      return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak:  return 15 * 60
        }
    }

    var label: String {
        switch self {
        case .focus:      return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak:  return "Long break"
        }
    }

    /// SF Symbol shown in the centre of the timer ring.
    var icon: String {
        switch self {
        case .focus:      return "bolt.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak:  return "leaf.fill"
        }
    }

    /// Three-stop gradient palette per phase. Tuned **deep + desaturated**
    /// rather than fluorescent — the original palette was painfully bright
    /// in low-light evening sessions. White SF Symbols and digits on top
    /// still read fine against these darker stops.
    var palette: [Color] {
        switch self {
        case .focus:
            return [
                Color(red: 0.42, green: 0.16, blue: 0.10),  // deep amber
                Color(red: 0.32, green: 0.07, blue: 0.16),  // burgundy
                Color(red: 0.18, green: 0.04, blue: 0.20),  // dark plum
            ]
        case .shortBreak:
            return [
                Color(red: 0.10, green: 0.22, blue: 0.42),  // deep indigo
                Color(red: 0.05, green: 0.14, blue: 0.32),  // night blue
                Color(red: 0.03, green: 0.08, blue: 0.20),  // midnight
            ]
        case .longBreak:
            return [
                Color(red: 0.07, green: 0.32, blue: 0.24),  // emerald
                Color(red: 0.04, green: 0.22, blue: 0.18),  // forest
                Color(red: 0.02, green: 0.14, blue: 0.14),  // pine
            ]
        }
    }
}

/// One in-flight focus session. The task title is captured at start time so
/// renaming or completing the underlying habit mid-session doesn't yank the
/// label out from under the user.
struct FocusSession: Equatable {
    var phase: FocusPhase
    var taskTitle: String
    /// Total duration the session was started with.
    var duration: TimeInterval
    /// Wall-clock start time. Used to recompute `remaining` every tick so a
    /// brief background pause / system clock tick doesn't drift the timer.
    var startedAt: Date
    /// True when the user paused — `remaining` freezes and no completion
    /// fires until `resume()` adjusts `startedAt` to compensate.
    var isPaused: Bool
    /// While paused, captures the remaining-time snapshot so resume can
    /// restore it cleanly.
    var pausedRemaining: TimeInterval?
}

/// Shared singleton controller. SwiftUI views observe this; the immersive
/// focus view binds to it and the status-bar (macOS) / Live Activity (iOS)
/// presenters subscribe to the same source of truth.
@MainActor
final class FocusController: ObservableObject {
    static let shared = FocusController()

    /// Active session, nil when nothing is running. Setting to nil dismisses
    /// the immersive view via the binding the dashboard installs.
    @Published private(set) var session: FocusSession?

    /// Live remaining-seconds value. Recomputed every 0.5s while a session
    /// is active. Drives both the ring fill and the digit display.
    @Published private(set) var remaining: TimeInterval = 0

    /// True while the immersive view is presented. The dashboard reads this
    /// via the `isImmersivePresented` binding to decide whether to show the
    /// overlay; the FocusController owns it so all entry points (toolbar
    /// button, Live Activity tap, status bar click) toggle the same flag.
    @Published var isImmersivePresented: Bool = false

    /// Cumulative completed focus pomodoros today — drives the long/short
    /// break decision (every fourth break is a long one, traditional
    /// Pomodoro Technique cadence).
    @Published private(set) var completedFocusCount: Int = 0

    private var timer: AnyCancellable?

    private init() {}

    /// Begin a new session. Existing sessions are cancelled silently so the
    /// caller doesn't need to remember to stop first.
    func start(taskTitle: String, phase: FocusPhase = .focus, duration: TimeInterval? = nil) {
        let length = duration ?? phase.defaultDuration
        let now = Date()
        session = FocusSession(
            phase: phase,
            taskTitle: taskTitle,
            duration: length,
            startedAt: now,
            isPaused: false,
            pausedRemaining: nil
        )
        remaining = length
        isImmersivePresented = true
        startTimer()

        // Mirror the session into ActivityKit so the lock screen and
        // Dynamic Island show the same countdown when the user steps
        // away from the app.
        FocusLiveActivityManager.start(
            taskTitle: taskTitle,
            phaseRaw: phase.rawValue,
            endsAt: now.addingTimeInterval(length),
            isPaused: false
        )
    }

    func pause() {
        guard var session, !session.isPaused else { return }
        session.pausedRemaining = remaining
        session.isPaused = true
        self.session = session
        timer?.cancel()

        FocusLiveActivityManager.update(
            phaseRaw: session.phase.rawValue,
            endsAt: Date().addingTimeInterval(remaining),
            isPaused: true
        )
    }

    func resume() {
        guard var session, session.isPaused else { return }
        let snapshot = session.pausedRemaining ?? remaining
        session.startedAt = Date().addingTimeInterval(-(session.duration - snapshot))
        session.isPaused = false
        session.pausedRemaining = nil
        self.session = session
        startTimer()

        FocusLiveActivityManager.update(
            phaseRaw: session.phase.rawValue,
            endsAt: Date().addingTimeInterval(snapshot),
            isPaused: false
        )
    }

    /// User chose to bail. Doesn't increment `completedFocusCount` so a
    /// half-finished pomodoro doesn't trigger the next break.
    func cancel() {
        timer?.cancel()
        timer = nil
        session = nil
        remaining = 0
        isImmersivePresented = false
        Task { await FocusLiveActivityManager.endAll() }
    }

    /// Called when the timer hits zero. Auto-advances into the next phase
    /// and bumps the focus counter so every fourth focus session earns a
    /// long break.
    func skip() {
        guard let current = session else { return }
        timer?.cancel()
        timer = nil
        if current.phase == .focus {
            completedFocusCount += 1
        }
        let next = nextPhase(after: current.phase)
        start(taskTitle: current.taskTitle, phase: next)
    }

    /// Toggle convenience for the immersive view's primary CTA.
    func togglePause() {
        guard let session else { return }
        session.isPaused ? resume() : pause()
    }

    /// Title of the next phase the user will roll into when the current
    /// timer expires. Surfaced in the immersive UI as "Up next: …".
    var upcomingPhase: FocusPhase? {
        guard let session else { return nil }
        return nextPhase(after: session.phase)
    }

    /// Fraction completed in `[0, 1]`. Used as the ring fill.
    var progress: Double {
        guard let session, session.duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / session.duration))
    }

    // MARK: - Private

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard let session, !session.isPaused else { return }
        let elapsed = Date().timeIntervalSince(session.startedAt)
        let next = max(0, session.duration - elapsed)
        remaining = next
        if next == 0 {
            // Auto-advance into the next phase. Mirrors `skip()` so the
            // counter and palette logic stays in one place.
            skip()
        }
    }

    private func nextPhase(after phase: FocusPhase) -> FocusPhase {
        switch phase {
        case .focus:
            // Every 4th focus session opens a long break, otherwise short.
            return (completedFocusCount % 4 == 0 && completedFocusCount > 0)
                ? .longBreak
                : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }
}

// MARK: - Immersive View

/// Full-screen immersive focus mode. Hides the dashboard, takes over the
/// whole window, and renders a breathing gradient + pulsing timer. The
/// view itself owns no state — every value comes from `FocusController`.
struct FocusModeView: View {
    @ObservedObject var controller: FocusController
    @Environment(\.colorScheme) private var colorScheme

    @State private var animateBlobs = false
    @State private var animateRing = false

    var body: some View {
        if let session = controller.session {
            ZStack {
                // Hard black floor so the gradient never washes brighter
                // than the colour stops — guarantees an evening-friendly
                // ceiling even on max-bright OLED panels.
                Color.black.ignoresSafeArea()

                animatedBackground(for: session.phase)
                    .ignoresSafeArea()

                FocusBlobs(palette: session.phase.palette, animate: animateBlobs)
                    .ignoresSafeArea()
                    .blendMode(.softLight)
                    .opacity(0.30)

                content(session: session)
            }
            // Intentionally NOT forcing .preferredColorScheme(.dark) — the
            // immersive surface is colour-driven, not scheme-driven, and
            // forcing dark would yank the rest of the app dark on dismiss.
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    animateBlobs = true
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    animateRing = true
                }
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
            }
            .onDisappear {
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
            }
            .transition(.opacity.combined(with: .scale(scale: 1.04)))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func animatedBackground(for phase: FocusPhase) -> some View {
        LinearGradient(
            colors: phase.palette,
            startPoint: animateBlobs ? .topLeading : .bottomLeading,
            endPoint: animateBlobs ? .bottomTrailing : .topTrailing
        )
    }

    @ViewBuilder
    private func content(session: FocusSession) -> some View {
        VStack(spacing: 28) {
            topBar(session: session)

            Spacer()

            FocusTimerRing(
                progress: controller.progress,
                remaining: controller.remaining,
                phase: session.phase,
                pulse: animateRing
            )
            .frame(maxWidth: 360, maxHeight: 360)

            VStack(spacing: 8) {
                Text(session.taskTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 32)
                if let upcoming = controller.upcomingPhase {
                    Text("Up next: \(upcoming.label)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }

            Spacer()

            controlBar(session: session)
                .padding(.bottom, 32)
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private func topBar(session: FocusSession) -> some View {
        HStack {
            Label(session.phase.label, systemImage: session.phase.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )

            Spacer()

            Button {
                controller.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit focus mode")
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func controlBar(session: FocusSession) -> some View {
        HStack(spacing: 18) {
            Button(action: controller.skip) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip phase")

            Button(action: controller.togglePause) {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(session.phase.palette.first ?? .red)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(.white))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

            Button(action: controller.cancel) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop session")
        }
    }
}

/// Animated organic blobs that drift across the focus background. Pure
/// SwiftUI shapes — no Metal, no custom shaders — so they render on every
/// supported OS without compatibility checks.
private struct FocusBlobs: View {
    let palette: [Color]
    let animate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                blob(color: palette.first ?? .red,
                     center: animate ? CGPoint(x: geo.size.width * 0.18, y: geo.size.height * 0.32)
                                     : CGPoint(x: geo.size.width * 0.32, y: geo.size.height * 0.18),
                     radius: geo.size.width * 0.55)

                blob(color: palette.dropFirst().first ?? .pink,
                     center: animate ? CGPoint(x: geo.size.width * 0.78, y: geo.size.height * 0.22)
                                     : CGPoint(x: geo.size.width * 0.62, y: geo.size.height * 0.36),
                     radius: geo.size.width * 0.50)

                blob(color: palette.last ?? .purple,
                     center: animate ? CGPoint(x: geo.size.width * 0.45, y: geo.size.height * 0.78)
                                     : CGPoint(x: geo.size.width * 0.58, y: geo.size.height * 0.62),
                     radius: geo.size.width * 0.65)
            }
            .blur(radius: 80)
        }
    }

    private func blob(color: Color, center: CGPoint, radius: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .opacity(0.85)
    }
}

/// Circular timer ring with a pulsing breath. The fill grows clockwise as
/// `progress` advances; the trailing dot marks the current head so users
/// can read it at a glance even if they don't see the digital countdown.
private struct FocusTimerRing: View {
    let progress: Double
    let remaining: TimeInterval
    let phase: FocusPhase
    let pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)

            VStack(spacing: 6) {
                Image(systemName: phase.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(timeString)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(phase.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .scaleEffect(pulse ? 1.02 : 1.0)
    }

    private var timeString: String {
        let total = max(0, Int(remaining.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Entry-point button

/// Compact button suitable for placing on a HabitCard or task row. Fires
/// the immersive focus mode for the supplied title.
struct FocusStartButton: View {
    let taskTitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            FocusController.shared.start(taskTitle: taskTitle)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .bold))
                Text("Focus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start focus session for \(taskTitle)")
    }
}
