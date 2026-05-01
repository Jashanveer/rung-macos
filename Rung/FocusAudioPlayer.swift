import AVFoundation
import Combine
import Foundation

/// Singleton that plays bundled royalty-free focus audio for the duration
/// of a focus phase. The `FocusController` calls into this when a focus
/// session starts / pauses / resumes / ends. The player itself owns no
/// scheduling — it's a thin wrapper around `AVAudioPlayer` that keeps
/// the loop running until told to stop.
///
/// Per-platform notes:
/// - **iOS**: configures the audio session with `.playback` (no
///   `.mixWithOthers` option) so we take over playback exclusively while
///   focus is active. Other audio is paused for the duration of the
///   session and the system restores it after we deactivate.
/// - **macOS**: no AVAudioSession needed — the system mixes by default
///   and the user can adjust per-app volume from Sound preferences if
///   they want our music quieter than other audio.
@MainActor
final class FocusAudioPlayer: ObservableObject {
    static let shared = FocusAudioPlayer()

    /// Track currently playing. Nil while stopped or fading out. The
    /// audio settings sheet observes this for the "Now playing" line.
    @Published private(set) var currentTrack: FocusAudioTrack?

    private var player: AVAudioPlayer?
    /// Token that lets a delayed `stop` cancel itself if a new track
    /// starts before the fade-out completes. Without this, a quick
    /// pause/start cycle could silence the new track right after it
    /// began — the old fade-out would land on the new player.
    private var fadeStopToken: UUID?

    private init() {}

    // MARK: - Public API used by FocusController

    /// Pick a track for `mode`, configure the audio session, and start
    /// the loop at `volume`. No-op when `mode == .off` or the bundled
    /// audio file isn't present (which is the build-time state until
    /// the .m4a assets are added to the target).
    func playRandom(for mode: FocusAudioMode, volume: Float) {
        guard mode.isEnabled, let track = pickTrack(for: mode) else {
            stopImmediately()
            return
        }
        play(track: track, volume: volume)
    }

    /// Pause the current loop without unloading it — used when the
    /// user pauses the focus timer. `resume()` picks up at the same
    /// position so the music doesn't restart from zero.
    func pause() {
        player?.pause()
    }

    /// Resume the paused loop. Safe to call when nothing is loaded.
    func resume() {
        player?.play()
    }

    /// Smoothly fade out and stop. The default 1.5s fade is short enough
    /// to feel responsive when the user hits cancel and long enough to
    /// avoid an audible cut at session-end.
    func stop(fadeDuration: TimeInterval = 1.5) {
        guard let player else {
            currentTrack = nil
            deactivateSession()
            return
        }
        let token = UUID()
        fadeStopToken = token
        player.setVolume(0, fadeDuration: fadeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + 0.05) { [weak self] in
            guard let self else { return }
            // A newer track may have started during the fade — bail if
            // our token was superseded so we don't silence the new one.
            guard self.fadeStopToken == token else { return }
            self.stopImmediately()
        }
    }

    /// Real-time volume change — wired to the slider in the settings
    /// sheet. Animated for 0.4s so the slider doesn't sound steppy.
    func setVolume(_ volume: Float) {
        player?.setVolume(volume, fadeDuration: 0.4)
    }

    // MARK: - Private

    private func play(track: FocusAudioTrack, volume: Float) {
        // If we're already playing the same track, just restore volume.
        if currentTrack == track, let player, player.isPlaying {
            fadeStopToken = nil
            player.setVolume(volume, fadeDuration: 0.4)
            return
        }
        guard let url = Self.url(for: track) else {
            // Asset hasn't been added to the bundle yet — fail silently
            // so a developer can ship the catalog before the audio.
            print("[FocusAudioPlayer] missing bundle resource for \(track.id)")
            stopImmediately()
            return
        }
        do {
            activateSessionIfNeeded()
            // Cancel any in-flight fade-out from the prior track so it
            // doesn't kill the new player a beat after it begins.
            fadeStopToken = nil
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1   // loop indefinitely; we stop it on cancel
            next.volume = volume
            next.prepareToPlay()
            next.play()
            self.player = next
            self.currentTrack = track
        } catch {
            print("[FocusAudioPlayer] failed to start \(track.id): \(error)")
            stopImmediately()
        }
    }

    private func stopImmediately() {
        player?.stop()
        player = nil
        currentTrack = nil
        fadeStopToken = nil
        deactivateSession()
    }

    private func pickTrack(for mode: FocusAudioMode) -> FocusAudioTrack? {
        let pool: [FocusAudioTrack]
        switch mode {
        case .off:
            return nil
        case .shuffle:
            pool = FocusAudioLibrary.tracks
        case .category(let cat):
            pool = FocusAudioLibrary.tracks(in: cat)
        case .track(let id):
            return FocusAudioLibrary.track(forID: id)
        }
        return pool.randomElement()
    }

    private static func url(for track: FocusAudioTrack) -> URL? {
        Bundle.main.url(forResource: track.id, withExtension: track.fileExtension)
    }

    // MARK: - Audio session (iOS only)

    private func activateSessionIfNeeded() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[FocusAudioPlayer] activate session: \(error)")
        }
        #endif
    }

    private func deactivateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Deactivation can throw when something else is also using
            // the session — harmless, log only.
            print("[FocusAudioPlayer] deactivate session: \(error)")
        }
        #endif
    }
}
