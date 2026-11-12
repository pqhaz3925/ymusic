import Foundation

/// One audio file the store knows about: a track at a quality, finished or still partial.
nonisolated struct StoredEntry: Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        /// Transient: evicted when the cache is over its limit, purgeable by the system.
        case cache
        /// Kept for offline listening until the user removes it. Always complete.
        case download
    }

    /// The whole track, so downloads can be listed with no network at all.
    var track: Track
    /// What the server granted, i.e. what the file really is.
    var quality: AudioQuality
    /// Highest quality that was asked for when the server answered with `quality`.
    /// Anything up to here is known to resolve to this very file.
    var asked: AudioQuality
    var codec: String
    var bitrateKbps: Int?
    /// 0 until the server has told us.
    var totalBytes: Int64 = 0
    /// Bytes on disk (`totalBytes` once complete).
    var bytes: Int64 = 0
    var complete = false
    var kind = Kind.cache
    /// File name inside the kind's directory. Empty until complete.
    var file = ""
    /// When the entry was created; for a download, when it became one.
    var added = Date()
    var lastUsed = Date()

    var key: String { Self.key(track.id, quality) }

    static func key(_ trackId: String, _ quality: AudioQuality) -> String {
        trackId + "|" + quality.rawValue
    }

    /// A request for `wanted` is fully served by this file: it is at least that good, or
    /// it is what the server gives when asked for that much.
    func satisfies(_ wanted: AudioQuality) -> Bool {
        quality >= wanted || wanted <= asked
    }

    /// This partial file is the one a stream at `wanted` would continue. Unlike
    /// `satisfies`, better isn't good enough: a lower quality is asked for precisely
    /// because the link can't carry more bytes.
    func continues(_ wanted: AudioQuality) -> Bool {
        quality == wanted || (quality < wanted && wanted <= asked)
    }
}

/// A track the user asked to keep offline that isn't fully on disk yet.
nonisolated struct PendingDownload: Codable, Sendable {
    var track: Track
    var added = Date()
}

/// What is persisted between launches.
nonisolated struct StoreIndex: Codable, Sendable {
    var version = 1
    var entries: [StoredEntry] = []
    var pending: [PendingDownload] = []

    init(entries: [StoredEntry] = [], pending: [PendingDownload] = []) {
        self.entries = entries
        self.pending = pending
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        // One unreadable record (say, written by a newer build) shouldn't cost the rest.
        entries = ((try? c.decode([Lossy<StoredEntry>].self, forKey: .entries)) ?? []).compactMap(\.value)
        pending = ((try? c.decode([Lossy<PendingDownload>].self, forKey: .pending)) ?? []).compactMap(\.value)
    }

    private nonisolated struct Lossy<T: Codable & Sendable>: Codable, Sendable {
        var value: T?
        init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
        func encode(to encoder: any Encoder) throws { try value?.encode(to: encoder) }
    }
}

/// Where audio lives on disk, and the blocking file work (run it off the main thread).
///
///     Application Support/Audio/index.json     what we have (this file's `StoreIndex`)
///     Application Support/Audio/Downloads/     explicit downloads; not backed up
///     Caches/Audio/                            streaming cache and all partial files
nonisolated struct AudioDirectories: Sendable {
    let index: URL
    let downloads: URL
    let cache: URL

    static var standard: AudioDirectories {
        let fm = FileManager.default
        let support = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory).appendingPathComponent("Audio", isDirectory: true)
        let caches = (fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory).appendingPathComponent("Audio", isDirectory: true)
        return AudioDirectories(support: support, cache: caches)
    }

    init(support: URL, cache: URL) {
        index = support.appendingPathComponent("index.json")
        downloads = support.appendingPathComponent("Downloads", isDirectory: true)
        self.cache = cache
    }

    func directory(_ kind: StoredEntry.Kind) -> URL {
        kind == .download ? downloads : cache
    }

    /// File name (no extension) for a track at a quality. Track ids are numeric in
    /// practice; anything else is flattened so it can't escape the directory.
    static func name(_ trackId: String, _ quality: AudioQuality) -> String {
        let safe = String(trackId.unicodeScalars.map { s -> Character in
            (s.isASCII && (CharacterSet.alphanumerics.contains(s) || s == "-")) ? Character(s) : "_"
        })
        return safe + "." + quality.rawValue
    }

    func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        // Downloads can always be fetched again; they have no business in a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = downloads
        try? dir.setResourceValues(values)
    }

    func load() -> StoreIndex {
        guard let data = try? Data(contentsOf: index),
              let loaded = try? JSONDecoder().decode(StoreIndex.self, from: data) else { return StoreIndex() }
        return loaded
    }

    func save(_ value: StoreIndex) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: index, options: .atomic)
    }

    nonisolated struct Audit: Sendable {
        /// Keys of complete entries whose file is gone or has the wrong size.
        var missing: [String] = []
        /// Bytes actually on disk for partial entries, by key.
        var partial: [String: Int64] = [:]
    }

    /// Compare the index with the disk: report what vanished (the system may purge Caches,
    /// a crash may lose a file) and delete files nothing refers to.
    func audit(_ entries: [StoredEntry]) -> Audit {
        let fm = FileManager.default
        var audit = Audit()
        var known: [StoredEntry.Kind: Set<String>] = [.cache: [], .download: []]
        for e in entries {
            let name = Self.name(e.track.id, e.quality)
            if e.complete {
                let path = directory(e.kind).appendingPathComponent(e.file).path
                let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber
                if e.file.isEmpty || size?.int64Value != e.totalBytes {
                    audit.missing.append(e.key)
                } else {
                    known[e.kind]?.insert(e.file)
                }
            } else {
                audit.partial[e.key] = Transfer.bytesOnDisk(name: name, in: cache)
                for url in Transfer.leftovers(name: name, in: cache) { known[.cache]?.insert(url.lastPathComponent) }
            }
        }
        for kind in [StoredEntry.Kind.cache, .download] {
            let dir = directory(kind)
            for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where known[kind]?.contains(file) != true {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
            }
        }
        return audit
    }
}
