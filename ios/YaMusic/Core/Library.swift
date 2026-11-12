import Foundation
import Observation

/// A cacheable piece of the user's library: where to keep it and how to fetch it.
nonisolated struct LibraryKey<Value: Codable & Sendable>: Sendable {
    let name: String
    let fetch: @Sendable (any MusicService) async throws -> Value
}

extension LibraryKey where Value == HomeFeed {
    static var home: Self { .init(name: "home") { try await $0.home() } }
}

extension LibraryKey where Value == [String] {
    static var likedIds: Self { .init(name: "liked-ids") { try await $0.likedIds() } }
}

extension LibraryKey where Value == [Playlist] {
    static var playlists: Self { .init(name: "playlists") { try await $0.myPlaylists() } }
}

extension LibraryKey where Value == [Album] {
    static var likedAlbums: Self { .init(name: "liked-albums") { try await $0.likedAlbums() } }
}

extension LibraryKey where Value == [Artist] {
    static var likedArtists: Self { .init(name: "liked-artists") { try await $0.likedArtists() } }
}

extension LibraryKey where Value == [Track] {
    static var liked: Self { .init(name: "liked") { try await $0.likedTracks() } }

    /// Track list of a playlist / album / artist / history. (`.liked` maps to `liked`.)
    static func tracks(_ d: Destination) -> Self {
        let id: String
        switch d {
        case .liked: return .liked
        case .history: id = "history"
        case .downloads: id = "downloads"
        case .playlist(let p): id = "playlist-\(p.id)"
        case .album(let a): id = "album-\(a.id)"
        case .artist(let a): id = "artist-\(a.id)"
        }
        return .init(name: "tracks-\(id)") { try await $0.tracks(of: d) }
    }
}

/// Disk-backed cache of library data, so the app opens instantly and still has something
/// to show (and play) with no network.
///
/// Usage from a view:
/// ```swift
/// if let cached = app.library.cached(.liked) { tracks = cached }      // instant
/// if let fresh = try? await app.library.load(.liked) { tracks = fresh } // then refresh
/// ```
/// `load` throws only when the fetch failed *and* there is nothing cached.
@Observable
final class Library {
    var service: any MusicService

    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var memory: [String: Any] = [:]

    init(service: any MusicService) {
        self.service = service
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Last known value, without touching the network.
    func cached<T>(_ key: LibraryKey<T>) -> T? {
        if let hit = memory[key.name] as? T { return hit }
        guard let data = try? Data(contentsOf: file(key.name)),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        memory[key.name] = value
        return value
    }

    /// Fetch and remember. On a connectivity failure falls back to the cached value if there is one.
    func load<T>(_ key: LibraryKey<T>) async throws -> T {
        do {
            let value = try await key.fetch(service)
            store(value, for: key)
            return value
        } catch {
            if error.isNetworkFailure, let stale = cached(key) { return stale }
            throw error
        }
    }

    /// Replace a cached value locally (e.g. after an optimistic like).
    func store<T>(_ value: T, for key: LibraryKey<T>) {
        memory[key.name] = value
        let url = file(key.name)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Drop everything (sign-out).
    func wipe() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ name: String) -> URL {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return dir.appendingPathComponent(String(safe) + ".json")
    }
}
