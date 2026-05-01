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

    /// Snapshot of the most recently *finished* focus phase, capped to one
    /// entry. The toggle path queries this when the user marks the same
    /// task done shortly after — we attribute the focus length as the
    /// completion duration so the stats card shows real numbers without
    /// asking the user to time anything by hand.
    private var lastCompletedFocus: (taskTitle: String, duration: TimeInterval, finishedAt: Date)?

    private var timer: AnyCancellable?

    private init() {}

    /// Returns the duration (in seconds) of a focus session that just
    /// finished for `taskTitle`, if and only if it was within the last
    /// 5 minutes. Consumed by `ContentView.toggleHabit` so the duration
    /// feeds straight into the next `setCheck` call. Returns nil when the
    /// snapshot doesn't match or has aged out.
    func recentlyCompletedDuration(for taskTitle: String) -> Int? {
        guard let snap = lastCompletedFocus else { return nil }
        guard snap.taskTitle.caseInsensitiveCompare(taskTitle) == .orderedSame else { return nil }
        guard Date().timeIntervalSince(snap.finishedAt) <= 5 * 60 else { return nil }
        return Int(snap.duration.rounded())
    }

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

        // Play bundled focus music for the focus phase only — break
        // phases stay silent so the user can actually rest.
        if phase == .focus {
            startBundledAudio()
        } else {
            FocusAudioPlayer.shared.stop()
        }
    }

    func pause() {
        guard var session, !session.isPaused else { return }
        session.pausedRemaining = remaining
        session.isPaused = true
        self.session = session
        timer?.cancel()
        FocusAudioPlayer.shared.pause()

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
        FocusAudioPlayer.shared.resume()

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
        FocusAudioPlayer.shared.stop()
        Task { await FocusLiveActivityManager.endAll() }
    }

    /// Reads the user's `@AppStorage` audio settings and asks the
    /// shared `FocusAudioPlayer` to start a track. We read the keys
    /// directly from `UserDefaults` (rather than declaring an
    /// `@AppStorage` property on the controller) because
    /// `FocusController` is `ObservableObject` — adding settings as
    /// stored properties would needlessly republish on every tweak.
    private func startBundledAudio() {
        let defaults = UserDefaults.standard
        let modeRaw = defaults.string(forKey: "Settings.focusMusicMode") ?? FocusAudioMode.shuffle.rawValue
        let volume = Float(defaults.object(forKey: "Settings.focusMusicVolume") as? Double ?? 0.6)
        FocusAudioPlayer.shared.playRandom(for: FocusAudioMode(rawValue: modeRaw), volume: volume)
    }

    /// Called when the timer hits zero. Auto-advances into the next phase
    /// and bumps the focus counter so every fourth focus session earns a
    /// long break. Also stamps `lastCompletedFocus` so a follow-up toggle
    /// from the dashboard can attribute the focus length as the habit's
    /// completion duration.
    func skip() {
        guard let current = session else { return }
        timer?.cancel()
        timer = nil
        if current.phase == .focus {
            completedFocusCount += 1
            // Only focus phases (not breaks) get attributed as habit time.
            // Use elapsed-since-start so a manually skipped session credits
            // the actual focused minutes, not the original target length.
            let elapsed = max(0, current.duration - remaining)
            lastCompletedFocus = (current.taskTitle, elapsed, Date())
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
    /// Drives the music settings sheet anchored to the gear button on
    /// the top-right of the immersive HUD.
    @State private var showAudioSettings = false

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
        HStack(spacing: 10) {
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

            // Music / settings gear — opens a sheet with the on/off
            // toggle, mode picker (Shuffle / Lo-fi / Nature / specific
            // track), and volume slider. The user explicitly asked for
            // the button to live on the top-right of the focus HUD.
            Button {
                showAudioSettings = true
            } label: {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Music settings")

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
        .sheet(isPresented: $showAudioSettings) {
            FocusAudioSettingsSheet()
        }
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

// MARK: - Audio settings sheet

/// Compact settings panel surfaced via the music gear on the focus HUD.
/// Lets the user toggle music, pick a mode (Shuffle / Lo-fi / Nature /
/// specific track) and adjust volume in real time.
///
/// The mode change does not interrupt the currently-playing track —
/// per the user's spec, the music doesn't change mid-session. The
/// new mode applies the next time a focus phase begins.
struct FocusAudioSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("Settings.focusMusicMode") private var modeRaw: String = FocusAudioMode.shuffle.rawValue
    @AppStorage("Settings.focusMusicVolume") private var volume: Double = 0.6

    @ObservedObject private var player = FocusAudioPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play music during focus")
                        .font(.subheadline.weight(.semibold))
                    Text("Starts when a focus phase begins, stops on breaks and when you cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            volumeSection

            modeSection

            if let nowPlaying = player.currentTrack {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.indigo)
                    Text("Now playing: \(nowPlaying.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 380, minHeight: 460, idealHeight: 540)
        .onChange(of: volume) { _, newValue in
            player.setVolume(Float(newValue))
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Focus music")
                    .font(.headline)
                Text("Bundled royalty-free tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Slider(value: $volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    optionRow(
                        title: "Shuffle (any track)",
                        systemImage: "shuffle",
                        target: .shuffle
                    )
                    ForEach(FocusAudioTrack.Category.allCases) { cat in
                        optionRow(
                            title: "\(cat.rawValue) — random",
                            systemImage: cat.systemImage,
                            target: .category(cat)
                        )
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(FocusAudioLibrary.tracks) { track in
                        optionRow(
                            title: track.displayName,
                            systemImage: track.category.systemImage,
                            target: .track(track.id)
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 240)

            Text("Mode changes apply on the next focus session — the current track keeps playing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func optionRow(title: String, systemImage: String, target: FocusAudioMode) -> some View {
        let isSelected = modeRaw == target.rawValue
        return Button {
            modeRaw = target.rawValue
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.indigo)
                }
            }
            .foregroundStyle(isSelected ? Color.indigo : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? Color.indigo.opacity(colorScheme == .dark ? 0.18 : 0.10)
                          : Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
            )
        }
        .buttonStyle(.plain)
    }

    /// Toggle wrapper that flips between `.off` and `.shuffle` (default
    /// "on" mode) so the user can disable music without losing their
    /// previously-selected mode if they only ever used Shuffle.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { FocusAudioMode(rawValue: modeRaw).isEnabled },
            set: { newValue in
                if newValue {
                    if !FocusAudioMode(rawValue: modeRaw).isEnabled {
                        modeRaw = FocusAudioMode.shuffle.rawValue
                    }
                } else {
                    modeRaw = FocusAudioMode.off.rawValue
                }
            }
        )
    }
}
