import Foundation
import YmBindings

/// `MusicService` over the Rust core (`YmClient`). Maps `Ffi*` records into app models.
nonisolated final class RustMusicService: MusicService {
    private let client: YmClient

    init(token: String) throws {
        self.client = try YmClient(token: token)
    }

    // MARK: MusicService

    func home() async throws -> HomeFeed {
        Self.map(try await client.home())
    }

    func waveTracks(stationId: String, queue: [String]) async throws -> [Track] {
        try await client.waveTracks(stationId: stationId, queue: queue).map(Self.map)
    }

    func waveFeedback(stationId: String, track: Track?, event: WaveFeedback) async {
        let kind: String
        var played = 0.0
        switch event {
        case .radioStarted: kind = "radioStarted"
        case .trackStarted: kind = "trackStarted"
        case .trackFinished(let s): kind = "trackFinished"; played = s
        case .skip(let s): kind = "skip"; played = s
        case .like: kind = "like"
        case .dislike: kind = "dislike"
        }
        try? await client.waveFeedback(stationId: stationId, trackId: track?.id, kind: kind, playedSeconds: played)
    }

    func stream(for track: Track, quality: AudioQuality, codecs: [String]) async throws -> StreamSource {
        let s = try await client.streamUrl(trackId: track.id, quality: quality.rawValue, codecs: codecs)
        guard let url = URL(string: s.url) else { throw URLError(.badURL) }
        return StreamSource(url: url, key: s.key, codec: s.codec, bitrateKbps: s.bitrate.map(Int.init).flatMap { $0 > 0 ? $0 : nil },
                            quality: AudioQuality(rawValue: s.quality) ?? quality)
    }

    func reportPlay(track: Track, playedSeconds: Double, fromCache: Bool) async {
        try? await client.reportPlay(trackId: track.id, albumId: track.albumId,
                                     durationSeconds: Double(track.durationMs) / 1000,
                                     playedSeconds: playedSeconds, fromCache: fromCache)
    }

    func likedIds() async throws -> [String] { try await client.likedIds() }

    func likedAlbums() async throws -> [Album] { try await client.likedAlbums().map(Self.map) }

    func likedArtists() async throws -> [Artist] { try await client.likedArtists().map(Self.map) }

    func search(_ query: String) async throws -> SearchResults {
        let s = try await client.search(query: query)
        return SearchResults(best: s.best.flatMap(Self.map),
                             tracks: s.tracks.map(Self.map),
                             albums: s.albums.map(Self.map),
                             artists: s.artists.map(Self.map),
                             playlists: s.playlists.map(Self.map))
    }

    func likedTracks() async throws -> [Track] {
        try await client.likedTracks().map(Self.map)
    }

    func setLiked(_ liked: Bool, track: Track) async throws {
        try await client.setLiked(trackId: track.id, liked: liked)
    }

    func myPlaylists() async throws -> [Playlist] {
        try await client.myPlaylists().map(Self.map)
    }

    func tracks(of destination: Destination) async throws -> [Track] {
        let (kind, id): (String, String)
        switch destination {
        case .liked: (kind, id) = ("liked", "")
        case .history: (kind, id) = ("history", "")
        case .downloads: return []
        case .playlist(let p): (kind, id) = ("playlist", p.id)
        case .album(let a): (kind, id) = ("album", a.id)
        case .artist(let a): (kind, id) = ("artist", a.id)
        }
        return try await client.tracksOf(kind: kind, id: id).map(Self.map)
    }

    // MARK: Mapping

    private static func map(_ a: FfiArtistRef) -> ArtistRef { ArtistRef(id: a.id, name: a.name) }

    private static func map(_ t: FfiTrack) -> Track {
        Track(id: t.id, title: t.title, version: t.version, artists: t.artists.map(map),
              albumId: t.albumId, coverURI: t.coverUri, durationMs: Int(t.durationMs), explicit: t.explicit)
    }

    private static func map(_ a: FfiAlbum) -> Album {
        Album(id: a.id, title: a.title, artists: a.artists.map(map), coverURI: a.coverUri,
              year: a.year.map(Int.init), trackCount: a.trackCount.map(Int.init))
    }

    private static func map(_ a: FfiArtist) -> Artist {
        Artist(id: a.id, name: a.name, coverURI: a.coverUri)
    }

    private static func map(_ p: FfiPlaylist) -> Playlist {
        Playlist(id: p.id, title: p.title, ownerName: p.ownerName, coverURI: p.coverUri,
                 trackCount: p.trackCount.map(Int.init))
    }

    private static func map(_ s: FfiWaveSeed) -> WaveSeed { WaveSeed(id: s.id, title: s.title) }

    private static func map(_ i: FfiShelfItem) -> ShelfItem? {
        switch i.kind {
        case "track": i.track.map { .track(map($0)) }
        case "album": i.album.map { .album(map($0)) }
        case "playlist": i.playlist.map { .playlist(map($0)) }
        case "artist": i.artist.map { .artist(map($0)) }
        default: nil
        }
    }

    private static func destination(for t: FfiQuickTile) -> Destination? {
        switch t.destKind {
        case "liked": return .liked
        case "history": return .history
        case "playlist": return .playlist(Playlist(id: t.destId, title: t.title, coverURI: t.coverUri))
        case "album": return .album(Album(id: t.destId, title: t.title, coverURI: t.coverUri))
        case "artist": return .artist(Artist(id: t.destId, name: t.title, coverURI: t.coverUri))
        default: return nil
        }
    }

    private static func map(_ h: FfiHome) -> HomeFeed {
        HomeFeed(
            wave: map(h.wave),
            waveSeeds: h.waveSeeds.map(map),
            mixes: h.mixes.map { MixCard(id: $0.id, title: $0.title, subtitle: $0.subtitle,
                                         coverURIs: $0.coverUris, stationId: $0.stationId) },
            quickAccess: h.quickAccess.compactMap { t in
                destination(for: t).map {
                    QuickTile(id: t.id, title: t.title, subtitle: t.subtitle, coverURI: t.coverUri, destination: $0)
                }
            },
            shelves: h.shelves.map { Shelf(id: $0.id, title: $0.title, items: $0.items.compactMap(map)) })
    }
}
