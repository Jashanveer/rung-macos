import Foundation

/// Bundled royalty-free focus tracks. The actual audio files live in the
/// app target under `Resources/FocusAudio/<id>.<extension>` and must be
/// added to "Copy Bundle Resources" in the project's build phase. The
/// player gracefully degrades to silence when a file is missing — that's
/// what lets the app keep building before the binary assets land.
struct FocusAudioTrack: Identifiable, Hashable, Codable {
    /// Stable identifier used for `Bundle.main.url(forResource:)` and
    /// `@AppStorage` persistence (`Settings.focusMusicMode = <id>`).
    let id: String
    /// Human-readable label shown in the picker and "Now playing" line.
    let displayName: String
    let category: Category
    /// File extension on disk. We default to `.m4a` (AAC) for the best
    /// compression-to-quality ratio at sub-2 MB per ~2 minute loop.
    let fileExtension: String

    enum Category: String, Codable, CaseIterable, Identifiable {
        case lofi = "Lo-fi"
        case nature = "Nature"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .lofi:   return "music.note"
            case .nature: return "leaf.fill"
            }
        }
    }
}

/// Catalog of bundled tracks. Edit this list when dropping new audio
/// files into the bundle — the picker, shuffle pool, and mode filter
/// all derive from here.
enum FocusAudioLibrary {
    /// 10 default tracks: 5 lo-fi loops + 5 ambient nature soundscapes.
    /// All entries assume an `.m4a` companion file under
    /// `Resources/FocusAudio/<id>.m4a` in the app bundle.
    static let tracks: [FocusAudioTrack] = [
        // MARK: Lo-fi (instrumental beats / ambient)
        FocusAudioTrack(id: "lofi-01", displayName: "Lo-fi · Soft Mornings", category: .lofi, fileExtension: "m4a"),
        FocusAudioTrack(id: "lofi-02", displayName: "Lo-fi · Slow Burn",     category: .lofi, fileExtension: "m4a"),
        FocusAudioTrack(id: "lofi-03", displayName: "Lo-fi · Late Library",  category: .lofi, fileExtension: "m4a"),
        FocusAudioTrack(id: "lofi-04", displayName: "Lo-fi · Rainy Café",    category: .lofi, fileExtension: "m4a"),
        FocusAudioTrack(id: "lofi-05", displayName: "Lo-fi · Night Drive",   category: .lofi, fileExtension: "m4a"),

        // MARK: Earthly / nature soundscapes
        FocusAudioTrack(id: "nature-rain",    displayName: "Steady Rainfall",  category: .nature, fileExtension: "m4a"),
        FocusAudioTrack(id: "nature-ocean",   displayName: "Ocean Waves",      category: .nature, fileExtension: "m4a"),
        FocusAudioTrack(id: "nature-forest",  displayName: "Forest at Dawn",   category: .nature, fileExtension: "m4a"),
        FocusAudioTrack(id: "nature-thunder", displayName: "Thunder & Rain",   category: .nature, fileExtension: "m4a"),
        FocusAudioTrack(id: "nature-stream",  displayName: "Mountain Stream",  category: .nature, fileExtension: "m4a"),
    ]

    static func track(forID id: String) -> FocusAudioTrack? {
        tracks.first { $0.id == id }
    }

    static func tracks(in category: FocusAudioTrack.Category) -> [FocusAudioTrack] {
        tracks.filter { $0.category == category }
    }
}

/// User-facing playback mode. Persisted as the raw string in `@AppStorage`
/// so the picker survives app restarts. `track(<id>)` is the explicit
/// "always play this one" option exposed per-track in the picker.
enum FocusAudioMode: Hashable {
    case off
    case shuffle
    case category(FocusAudioTrack.Category)
    case track(String)

    /// Encode/decode through `String` so `@AppStorage` only ever sees
    /// primitives. Format:
    /// - "off"         → .off
    /// - "shuffle"     → .shuffle
    /// - "cat:lofi"    → .category(.lofi)
    /// - "track:<id>"  → .track(id)
    init(rawValue: String) {
        switch rawValue {
        case "off":     self = .off
        case "shuffle": self = .shuffle
        default:
            if rawValue.hasPrefix("cat:"),
               let cat = FocusAudioTrack.Category(rawValue: String(rawValue.dropFirst(4))) {
                self = .category(cat)
            } else if rawValue.hasPrefix("track:") {
                self = .track(String(rawValue.dropFirst(6)))
            } else {
                self = .shuffle
            }
        }
    }

    var rawValue: String {
        switch self {
        case .off:                 return "off"
        case .shuffle:             return "shuffle"
        case .category(let cat):   return "cat:\(cat.rawValue)"
        case .track(let id):       return "track:\(id)"
        }
    }

    var isEnabled: Bool {
        if case .off = self { return false }
        return true
    }
}
