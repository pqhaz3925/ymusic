import Foundation
import YmBindings

/// Everything the UI needs from the backend. `RustMusicService` implements it over the
/// Rust core; `MockMusicService` is used when signed out and in previews.
protocol MusicService: Sendable {
    func home() async throws -> HomeFeed
    /// Next batch of tracks for a wave station. `queue` = ids already played/queued.
    func waveTracks(stationId: String, queue: [String]) async throws -> [Track]
    func waveFeedback(stationId: String, track: Track?, event: WaveFeedback) async
    /// Resolve a stream at (up to) `quality`. `codecs` narrows what the server may answer
    /// with; empty = anything. The URL is signed and short-lived: resolve again, don't store.
    func stream(for track: Track, quality: AudioQuality, codecs: [String]) async throws -> StreamSource
    func search(_ query: String) async throws -> SearchResults
    func likedTracks() async throws -> [Track]
    /// Ids only, newest first. Cheap; used to paint hearts.
    func likedIds() async throws -> [String]
    func setLiked(_ liked: Bool, track: Track) async throws
    func myPlaylists() async throws -> [Playlist]
    func likedAlbums() async throws -> [Album]
    func likedArtists() async throws -> [Artist]
    /// Not valid for `.downloads` (that one is served by `TrackStore`).
    func tracks(of destination: Destination) async throws -> [Track]
    /// Tell the service a track was listened to (feeds history / recommendations).
    func reportPlay(track: Track, playedSeconds: Double, fromCache: Bool) async
}

extension MusicService {
    func stream(for track: Track, quality: AudioQuality) async throws -> StreamSource {
        try await stream(for: track, quality: quality, codecs: [])
    }
}

extension Error {
    /// The failure is about connectivity (offline, timeout, gateway) rather than the request
    /// itself, so cached data is an acceptable answer and a retry later makes sense.
    var isNetworkFailure: Bool {
        if let e = self as? FfiError, case .Network = e { return true }
        if self is URLError { return true }
        return (self as NSError).domain == NSURLErrorDomain
    }
}

struct MockMusicService: MusicService {
    private static func cover(_ seed: String) -> String { "https://picsum.photos/seed/\(seed)/400" }

    static let sampleTracks: [Track] = [
        ("Loser (Slowed)", "VIZIOFF"), ("pyro - slowed", "nkeeei"), ("Нули", "9mice"),
        ("Ночь", "мартин"), ("Сайфер", "TAKETAKE"), ("Lights", "Savfalse"),
    ].enumerated().map { i, t in
        Track(id: "\(1000 + i)", title: t.0, artists: [ArtistRef(id: "\(i)", name: t.1)],
              coverURI: cover("t\(i)"), durationMs: 150_000 + i * 9_000)
    }

    func home() async throws -> HomeFeed {
        let albums = (0..<8).map { Album(id: "a\($0)", title: "Альбом \($0 + 1)",
                                          artists: [ArtistRef(id: "x", name: "Исполнитель")],
                                          coverURI: Self.cover("a\($0)")) }
        let playlists = (0..<8).map { Playlist(id: "1:\($0)", title: "Плейлист дня \($0 + 1)",
                                                coverURI: Self.cover("p\($0)")) }
        return HomeFeed(
            wave: WaveSeed(id: "user:onyourwave", title: "Моя волна"),
            waveSeeds: [WaveSeed(id: "track:1001", title: "pyro - slowed")],
            mixes: [
                MixCard(id: "foryou", title: "Для вас", subtitle: "nkeeei, 9mice",
                        coverURIs: [Self.cover("m1"), Self.cover("m2")], stationId: "personal:recent-tracks"),
                MixCard(id: "trends", title: "Тренды", subtitle: "мартин, TAKETAKE",
                        coverURIs: [Self.cover("m3"), Self.cover("m4")], stationId: "personal:hits"),
                MixCard(id: "new", title: "Новое", subtitle: "Savfalse, VIZIOFF",
                        coverURIs: [Self.cover("m5"), Self.cover("m6")], stationId: "personal:never-heard"),
            ],
            quickAccess: [
                QuickTile(id: "liked", title: "Мне нравится", subtitle: nil, coverURI: Self.cover("liked"), destination: .liked),
                QuickTile(id: "history", title: "История", subtitle: "Savfalse", coverURI: Self.cover("hist"), destination: .history),
                QuickTile(id: "pl0", title: playlists[0].title, subtitle: nil, coverURI: playlists[0].coverURI, destination: .playlist(playlists[0])),
                QuickTile(id: "al0", title: albums[0].title, subtitle: "Исполнитель", coverURI: albums[0].coverURI, destination: .album(albums[0])),
            ],
            shelves: [
                Shelf(id: "daily", title: "Собрано для вас", items: playlists.map(ShelfItem.playlist)),
                Shelf(id: "new", title: "Новые релизы", items: albums.map(ShelfItem.album)),
                Shelf(id: "tracks", title: "Популярные треки", items: Self.sampleTracks.map(ShelfItem.track)),
            ])
    }

    func waveTracks(stationId: String, queue: [String]) async throws -> [Track] { Self.sampleTracks.shuffled() }
    func waveFeedback(stationId: String, track: Track?, event: WaveFeedback) async {}
    func stream(for track: Track, quality: AudioQuality, codecs: [String]) async throws -> StreamSource {
        let n = (Int(track.id) ?? 0) % 16 + 1
        return StreamSource(url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-\(n).mp3")!,
                            codec: "mp3", bitrateKbps: 192, quality: min(quality, .hq))
    }
    func search(_ query: String) async throws -> SearchResults {
        let t = Self.sampleTracks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artistLine.localizedCaseInsensitiveContains(query) }
        return SearchResults(best: t.first.map(ShelfItem.track), tracks: t)
    }
    func likedTracks() async throws -> [Track] { Self.sampleTracks }
    func likedIds() async throws -> [String] { Self.sampleTracks.map(\.id) }
    func likedAlbums() async throws -> [Album] {
        (0..<6).map { Album(id: "a\($0)", title: "Альбом \($0 + 1)", artists: [ArtistRef(id: "x", name: "Исполнитель")],
                            coverURI: Self.cover("a\($0)"), year: 2020 + $0, trackCount: 8 + $0) }
    }
    func likedArtists() async throws -> [Artist] {
        (0..<6).map { Artist(id: "ar\($0)", name: "Исполнитель \($0 + 1)", coverURI: Self.cover("ar\($0)")) }
    }
    func reportPlay(track: Track, playedSeconds: Double, fromCache: Bool) async {}
    func setLiked(_ liked: Bool, track: Track) async throws {}
    func myPlaylists() async throws -> [Playlist] {
        (0..<5).map { Playlist(id: "1:\($0)", title: "Мой плейлист \($0 + 1)", coverURI: Self.cover("my\($0)"), trackCount: 10 + $0) }
    }
    func tracks(of destination: Destination) async throws -> [Track] { Self.sampleTracks }
}
