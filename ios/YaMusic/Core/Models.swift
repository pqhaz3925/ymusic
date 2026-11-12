import Foundation

// App-level models. The Rust bridge maps its FFI records (prefixed `Ffi*`) into these.

nonisolated struct ArtistRef: Hashable, Sendable, Codable {
    let id: String
    var name: String
}

nonisolated struct Track: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var version: String? = nil
    var artists: [ArtistRef] = []
    var albumId: String? = nil
    var coverURI: String? = nil
    var durationMs: Int = 0
    var explicit: Bool = false

    var artistLine: String { artists.map(\.name).joined(separator: ", ") }
    var fullTitle: String { version.map { "\(title) (\($0))" } ?? title }
    func coverURL(_ size: Int = 400) -> URL? { CoverURL.make(coverURI, size: size) }
}

nonisolated struct Album: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var artists: [ArtistRef] = []
    var coverURI: String? = nil
    var year: Int? = nil
    var trackCount: Int? = nil
    func coverURL(_ size: Int = 400) -> URL? { CoverURL.make(coverURI, size: size) }
}

nonisolated struct Artist: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var name: String
    var coverURI: String? = nil
    func coverURL(_ size: Int = 400) -> URL? { CoverURL.make(coverURI, size: size) }
}

nonisolated struct Playlist: Identifiable, Hashable, Sendable, Codable {
    /// "ownerUid:kind"
    let id: String
    var title: String
    var ownerName: String? = nil
    var coverURI: String? = nil
    var trackCount: Int? = nil
    func coverURL(_ size: Int = 400) -> URL? { CoverURL.make(coverURI, size: size) }
}

nonisolated enum CoverURL {
    /// Yandex cover URIs look like `avatars.yandex.net/get-music-content/.../%%`.
    static func make(_ uri: String?, size: Int) -> URL? {
        guard var s = uri, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "%%", with: "\(size)x\(size)")
        if !s.hasPrefix("http") { s = "https://" + s }
        return URL(string: s)
    }
}

/// A "My Wave" station or seed, e.g. id `user:onyourwave`, `track:12345`, title "pyro - slowed".
nonisolated struct WaveSeed: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
}

/// Capsule cards under the wave ("Для вас", "Тренды"): a wave mode with avatar stack.
nonisolated struct MixCard: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var coverURIs: [String] = []
    var stationId: String
}

nonisolated enum Destination: Hashable, Sendable, Codable {
    case liked
    case history
    /// Tracks stored on the device for offline listening (served by `TrackStore`, not the API).
    case downloads
    case playlist(Playlist)
    case album(Album)
    case artist(Artist)
}

/// Quick-access tiles ("Мне нравится", "История", ...).
nonisolated struct QuickTile: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var subtitle: String?
    var coverURI: String?
    var destination: Destination
}

nonisolated enum ShelfItem: Identifiable, Hashable, Sendable, Codable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
    case track(Track)

    var id: String {
        switch self {
        case .album(let a): "album:\(a.id)"
        case .playlist(let p): "playlist:\(p.id)"
        case .artist(let a): "artist:\(a.id)"
        case .track(let t): "track:\(t.id)"
        }
    }
}

nonisolated struct Shelf: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var items: [ShelfItem]
}

nonisolated struct HomeFeed: Sendable, Codable {
    var wave: WaveSeed
    /// Active wave seed chips under the title (the "pyro - slowed ×" pill).
    var waveSeeds: [WaveSeed]
    var mixes: [MixCard]
    var quickAccess: [QuickTile]
    var shelves: [Shelf]
}

nonisolated struct SearchResults: Sendable {
    var best: ShelfItem?
    var tracks: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []
    var playlists: [Playlist] = []
}

nonisolated enum WaveFeedback: Sendable {
    case radioStarted
    case trackStarted
    case trackFinished(playedSeconds: Double)
    case skip(playedSeconds: Double)
    case like
    case dislike
}

/// Stream / download quality, lowest to highest. Raw values are what the core takes.
///
/// Measured on real files: `lq` = HE-AAC 64 kbit/s (~1.7 MB a track), `nq` = AAC 192,
/// `hq` = AAC 256, `lossless` = FLAC ~940 kbit/s (~25 MB). All are fast-start MP4.
nonisolated enum AudioQuality: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case lq, nq, hq, lossless

    var id: Self { self }

    var title: String {
        switch self {
        case .lq: "Экономное"
        case .nq: "Стандартное"
        case .hq: "Высокое"
        case .lossless: "Lossless"
        }
    }

    var detail: String {
        switch self {
        case .lq: "HE-AAC 64 кбит/с · ~2 МБ на трек"
        case .nq: "AAC 192 кбит/с · ~5 МБ на трек"
        case .hq: "AAC 256 кбит/с · ~7 МБ на трек"
        case .lossless: "FLAC без потерь · ~25 МБ на трек"
        }
    }

    /// Short badge for the player.
    var badge: String {
        switch self {
        case .lq: "ЭКО"
        case .nq: "SD"
        case .hq: "HQ"
        case .lossless: "LOSSLESS"
        }
    }

    /// Typical bitrate, for network-fitness decisions when the server didn't report one.
    var nominalKbps: Double {
        switch self {
        case .lq: 64
        case .nq: 192
        case .hq: 256
        case .lossless: 1000
        }
    }

    private var rank: Int {
        switch self {
        case .lq: 0
        case .nq: 1
        case .hq: 2
        case .lossless: 3
        }
    }

    var lower: AudioQuality? { Self.allCases.last { $0 < self } }
    var higher: AudioQuality? { Self.allCases.first { $0 > self } }

    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// A resolved audio stream.
nonisolated struct StreamSource: Sendable, Hashable {
    var url: URL
    /// Hex AES-128-CTR key (zero IV) when the file is encrypted (`encraw`), else nil.
    var key: String? = nil
    /// `flac` | `flac-mp4` | `aac-mp4` | `he-aac-mp4` | `aac` | `he-aac` | `mp3` (may be empty).
    var codec: String = ""
    var bitrateKbps: Int? = nil
    /// Quality the server actually granted.
    var quality: AudioQuality = .hq
}

/// "Настроить Мою волну": optional filters sent to the rotor as extra seeds next to
/// `user:onyourwave` (seed names verified against the API).
nonisolated struct WaveTuning: Codable, Equatable, Sendable {
    enum Activity: String, Codable, CaseIterable, Identifiable, Sendable {
        case wakeUp = "wake-up", road = "road-trip", work = "work-background"
        var id: Self { self }
        var title: String {
            switch self {
            case .wakeUp: "Просыпаюсь"
            case .road: "В дороге"
            case .work: "Работаю"
            }
        }
    }

    enum Character: String, Codable, CaseIterable, Identifiable, Sendable {
        case favorite, discover, popular
        var id: Self { self }
        var title: String {
            switch self {
            case .favorite: "Любимое"
            case .discover: "Незнакомое"
            case .popular: "Популярное"
            }
        }
    }

    enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
        case active, fun, calm, sad
        var id: Self { self }
        var title: String {
            switch self {
            case .active: "Бодрое"
            case .fun: "Весёлое"
            case .calm: "Спокойное"
            case .sad: "Грустное"
            }
        }
    }

    enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
        case russian, foreign = "not-russian", instrumental = "without-words"
        var id: Self { self }
        var title: String {
            switch self {
            case .russian: "Русский"
            case .foreign: "Иностранный"
            case .instrumental: "Без слов"
            }
        }
    }

    var activity: Activity?
    var character: Character?
    var mood: Mood?
    var language: Language?

    static let base = "user:onyourwave"

    var isDefault: Bool { self == WaveTuning() }

    /// What the player gets: the base station plus one seed per chosen filter, comma-separated
    /// (the core splits it into the session's seed list).
    var stationId: String {
        var seeds = [Self.base]
        if let activity { seeds.append("activity:\(activity.rawValue)") }
        if let character { seeds.append("settingDiversity:\(character.rawValue)") }
        if let mood { seeds.append("settingMoodEnergy:\(mood.rawValue)") }
        if let language { seeds.append("settingLanguage:\(language.rawValue)") }
        return seeds.joined(separator: ",")
    }

    /// "Спокойное · Русский", or nil when nothing is chosen.
    var summary: String? {
        let parts = [activity?.title, character?.title, mood?.title, language?.title].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `stationId` is My Wave, tuned or not.
    static func isMyWave(_ stationId: String?) -> Bool {
        guard let stationId else { return false }
        return stationId == base || stationId.hasPrefix(base + ",")
    }
}
