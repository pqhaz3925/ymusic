import AVFoundation
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Something `AVPlayer` can play for a track, plus what it actually is.
struct PlayableAsset {
    let asset: AVURLAsset
    let quality: AudioQuality
    /// `flac-mp4`, `aac-mp4`, `he-aac-mp4`, `mp3`, … (may be empty).
    let codec: String
    let bitrateKbps: Int?
    /// Fully on disk: plays with no network at all.
    let isLocal: Bool
    /// Keeps the streaming machinery (resource-loader delegate, download) alive.
    /// Hold on to it for as long as the asset is in use.
    let retainer: AnyObject?
}

/// Offline state of one track.
nonisolated enum DownloadState: Equatable, Sendable {
    case queued
    /// 0...1
    case downloading(Double)
    case downloaded
    case failed(String)
}

nonisolated enum TrackStoreError: LocalizedError {
    /// Not on disk and the network may not be used (offline, or "downloaded only" mode).
    case notAvailableOffline

    var errorDescription: String? {
        switch self {
        case .notAvailableOffline: "Трек не скачан, а сети нет"
        }
    }
}

/// The one place audio bytes come from: explicit downloads, the streaming cache, and
/// cache-through streaming for everything else.
///
/// This class is the main-actor bookkeeping: which files exist (`StoredEntry`, persisted as
/// `StoreIndex`), who is using them (leases), and the download queue. The bytes themselves
/// move off the main thread: every file being fetched is a `Transfer` on the `FetchEngine`
/// queue, and a player reads a partial one through a `StreamLoader`.
///
/// A file is identified by track and *granted* quality. Whatever needs it (a player, the
/// prefetch of the next track, an offline download) takes a lease on the same transfer, so
/// a track is never fetched twice at once, and a download of the track that is playing
/// simply keeps the file being streamed.
@Observable
final class TrackStore {
    var service: any MusicService
    let settings: AppSettings
    let network: NetworkMonitor
    let quality: QualityController

    /// Offline state per track id. Absent = not requested for offline.
    private(set) var states: [String: DownloadState] = [:]
    /// Tracks fully downloaded for offline listening, newest first.
    private(set) var downloaded: [Track] = []
    /// Bytes used by explicit downloads / by the transient streaming cache.
    private(set) var downloadsBytes: Int64 = 0
    private(set) var cacheBytes: Int64 = 0
    /// Bumped when a complete copy appears or disappears, so `hasLocalCopy` is observable.
    private var localRevision = 0

    /// A stream handed out by `playable` died for good while a player was holding it: the
    /// remote file changed, the service refused to sign a new URL, or the disk is full.
    /// (Never for network trouble; that is retried for as long as the asset is held.)
    ///
    /// The asset will not load any further, and AVPlayer does not report that by itself
    /// (measured: the item stays `readyToPlay`, plays out its buffer and stalls). Build a
    /// new item with `playable` and seek to where the old one was.
    @ObservationIgnored var onStreamFailure: ((_ trackId: String, _ error: any Error) -> Void)?

    /// What a lease is for. Decides how much of the file is fetched and where it ends up.
    fileprivate nonisolated enum Use: Sendable {
        /// A player streams it: fetch everything, whatever the link.
        case player
        /// A player plays the finished cache file: just don't evict it.
        case local
        case download
        case prefetchAll
        case prefetchHead
    }

    /// Marks a file as in use. Players hold it as `PlayableAsset.retainer` and release it
    /// by letting go; the store ends its own (downloads, prefetch) explicitly.
    fileprivate nonisolated final class Lease: @unchecked Sendable {
        let key: String
        let use: Use
        /// The resource-loader delegate of the asset this lease was made for.
        var loader: StreamLoader?
        private var ended = false
        private let onDrop: @Sendable (String, Use) -> Void

        init(key: String, use: Use, onDrop: @escaping @Sendable (String, Use) -> Void) {
            self.key = key
            self.use = use
            self.onDrop = onDrop
        }

        /// True the first time (main actor only).
        func end() -> Bool {
            guard !ended else { return false }
            ended = true
            return true
        }

        deinit {
            if !ended { onDrop(key, use) }
        }
    }

    private struct Live {
        /// nil for a finished file that is only being played.
        var transfer: Transfer?
        var uses: [Use: Int] = [:]
    }

    private struct Job {
        let track: Track
        var key: String?
        var lease: Lease?
        var task: Task<Void, Never>?
        /// Times the file changed under the download and it had to start over.
        var restarts = 0
    }

    private struct Prefetch {
        let trackId: String
        let quality: AudioQuality
        var key: String?
        var lease: Lease?
        var task: Task<Void, Never>?
    }

    private struct OpenRequest: Hashable {
        let trackId: String
        let quality: AudioQuality
    }

    private static let prefetchHeadBytes: Int64 = 512 << 10
    private static let maxDownloads = 2

    @ObservationIgnored private let directories: AudioDirectories
    @ObservationIgnored private let engine = FetchEngine()
    @ObservationIgnored private let indexQueue = DispatchQueue(label: "ym.audio-index", qos: .utility)
    /// Every file we have or are fetching, by `StoredEntry.key`.
    @ObservationIgnored private var entries: [String: StoredEntry] = [:]
    /// Downloads not finished yet, oldest first (failed ones stay, to be retried next launch).
    @ObservationIgnored private var pending: [PendingDownload] = []
    /// Files in use. An entry here is never evicted.
    @ObservationIgnored private var live: [String: Live] = [:]
    /// Just-resolved locations waiting for their transfer to be created.
    @ObservationIgnored private var fresh: [String: RemoteStream] = [:]
    @ObservationIgnored private var opening: [OpenRequest: Task<String, any Error>] = [:]
    @ObservationIgnored private var jobs: [String: Job] = [:]
    @ObservationIgnored private var prefetching: Prefetch?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// The first path update is in: `network` says something real.
    @ObservationIgnored private var networkKnown = false
    #if canImport(UIKit)
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    #endif

    init(service: any MusicService, settings: AppSettings, network: NetworkMonitor, quality: QualityController,
         directories: AudioDirectories = .standard) {
        self.service = service
        self.settings = settings
        self.network = network
        self.quality = quality
        self.directories = directories

        // One small file, read once: everything below (and every caller) can then rely on
        // the store knowing what is on disk from the very first call.
        directories.prepare()
        let index = directories.load()
        for var e in index.entries {
            // A download is complete by definition; anything else in that state is debris.
            if e.kind == .download, !e.complete { e.kind = .cache }
            entries[e.key] = e
        }
        for e in entries.values where e.kind == .download { states[e.track.id] = .downloaded }
        for p in index.pending where states[p.track.id] == nil {
            states[p.track.id] = .queued
            pending.append(p)
        }
        refreshTotals()
        refreshDownloaded()

        engine.onThroughput = { [weak self] rate in
            DispatchQueue.main.async { self?.reportThroughput(rate) }
        }
        // First thing on the I/O queue, before any transfer can create a file there.
        let snapshot = Array(entries.values)
        engine.queue.async { [weak self, directories] in
            let audit = directories.audit(snapshot)
            DispatchQueue.main.async { self?.apply(audit) }
        }
        watch()
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        #endif
    }

    // MARK: Playback

    /// Asset for `track`. A complete local copy (download or cache) of any quality wins;
    /// otherwise a cache-through stream at `quality`. Throws `notAvailableOffline` when the
    /// track isn't local and `allowNetwork` is false.
    ///
    /// With the network allowed, a cached copy only counts if it is at least `quality`
    /// (an explicit download always counts); without it, anything complete will do.
    func playable(for track: Track, quality: AudioQuality, allowNetwork: Bool) async throws -> PlayableAsset {
        if let asset = localAsset(track.id, atLeast: allowNetwork ? quality : nil) { return asset }
        guard allowNetwork else { throw TrackStoreError.notAvailableOffline }
        var key: String
        do {
            key = try await open(track, quality)
            if entries[key]?.complete == true {
                if let asset = localAsset(key: key) { return asset }
                // The file had vanished (and the entry with it): this time it's a fresh one.
                key = try await open(track, quality)
            }
        } catch where error.isNetworkFailure {
            // Couldn't even ask the server: any complete copy beats an error.
            if let asset = localAsset(track.id, atLeast: nil) { return asset }
            throw error
        }
        guard let entry = entries[key] else { throw TrackStoreError.notAvailableOffline }
        let lease = acquire(key, .player)
        guard let transfer = live[key]?.transfer else {
            drop(lease)
            if let asset = localAsset(key: key) { return asset }
            throw TrackStoreError.notAvailableOffline
        }
        let loader = StreamLoader(transfer: transfer)
        lease.loader = loader
        touch(key)
        let type = AudioContainer.type(forCodec: entry.codec) ?? AudioContainer.m4a
        let name = AudioDirectories.name(track.id, entry.quality) + "." + AudioContainer.fileExtension(for: type)
        return PlayableAsset(asset: bind(lease, to: loader.makeAsset(name: name)), quality: entry.quality,
                             codec: entry.codec, bitrateKbps: entry.bitrateKbps, isLocal: false, retainer: lease)
    }

    /// Start pulling `track` into the cache so it starts instantly later: all of it on an
    /// unmetered link (the next track then needs no network), only the beginning otherwise.
    /// One prefetch at a time; a newer one replaces an older one nobody started playing.
    func prefetch(_ track: Track, quality: AudioQuality) {
        if let p = prefetching, p.trackId == track.id, p.quality == quality { return }
        cancelPrefetch()
        var slot = Prefetch(trackId: track.id, quality: quality)
        if let e = bestLocal(track.id, atLeast: quality) {
            // Already here in full; just make sure it still is when its turn comes.
            slot.key = e.key
            prefetching = slot
            syncPrefetch()
            return
        }
        guard network.isOnline, !settings.offlineMode else { return }
        slot.task = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                do {
                    guard let self, self.isPrefetching(track.id, quality) else { return }
                    let key = try await self.open(track, quality)
                    guard !Task.isCancelled, self.isPrefetching(track.id, quality) else { return }
                    self.prefetching?.key = key
                    self.syncPrefetch()
                    return
                } catch where error.isNetworkFailure {
                    // The link hiccuped; the track is still next, so try again shortly.
                } catch {
                    if let self, self.isPrefetching(track.id, quality) { self.prefetching = nil }
                    return
                }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 8)
            }
        }
        prefetching = slot
    }

    private func isPrefetching(_ trackId: String, _ quality: AudioQuality) -> Bool {
        prefetching?.trackId == trackId && prefetching?.quality == quality
    }

    /// A complete local copy exists (explicit download or finished cache entry).
    func hasLocalCopy(_ trackId: String) -> Bool {
        _ = localRevision
        return bestLocal(trackId, atLeast: nil) != nil
    }

    // MARK: Offline

    func state(of trackId: String) -> DownloadState? { states[trackId] }
    func isDownloaded(_ trackId: String) -> Bool { states[trackId] == .downloaded }

    /// Queue tracks for offline. Already downloaded / queued ones are skipped.
    func download(_ tracks: [Track]) {
        for track in tracks {
            switch states[track.id] {
            case .downloaded, .queued, .downloading: continue
            case .failed, nil: break
            }
            // A failed one keeps its place in the queue; it only needs another go.
            if !pending.contains(where: { $0.track.id == track.id }) { pending.append(PendingDownload(track: track)) }
            states[track.id] = .queued
        }
        scheduleSave()
        pumpDownloads()
    }

    /// Cancel queued/running downloads and delete downloaded files for these ids.
    func remove(_ trackIds: [String]) {
        for id in trackIds {
            if let job = jobs.removeValue(forKey: id) { end(job) }
            pending.removeAll { $0.track.id == id }
            for q in AudioQuality.allCases {
                let key = StoredEntry.key(id, q)
                guard let e = entries[key] else { continue }
                // The finished download goes, and so does a half-fetched file nobody else
                // (a player, the prefetch) is using.
                if e.kind == .download || (!e.complete && live[key] == nil) { delete(key) }
            }
            states[id] = nil
        }
        refreshTotals()
        refreshDownloaded()
        scheduleSave()
        pumpDownloads()
    }

    func removeAllDownloads() {
        remove(Array(states.keys))
    }

    /// Drop the transient streaming cache (explicit downloads stay). Files in use right
    /// now (playing, being downloaded) are kept.
    func clearCache() async {
        for (key, e) in entries where e.kind == .cache && live[key] == nil { delete(key) }
        refreshTotals()
        scheduleSave()
        // Return once the files are really gone, so the caller can show the freed space.
        let queue = engine.queue
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() }
        }
    }

    // MARK: Lookup

    private static func trackId(of key: String) -> String {
        String(key[..<(key.lastIndex(of: "|") ?? key.endIndex)])
    }

    private func entries(of trackId: String) -> [StoredEntry] {
        AudioQuality.allCases.compactMap { entries[StoredEntry.key(trackId, $0)] }
    }

    /// The complete file to play for a track. `wanted` nil = anything will do.
    private func bestLocal(_ trackId: String, atLeast wanted: AudioQuality?) -> StoredEntry? {
        let complete = entries(of: trackId).filter(\.complete)
        // An explicit download is the user's own choice of file: it always wins.
        if let download = complete.first(where: { $0.kind == .download }) { return download }
        return complete.filter { e in wanted.map(e.satisfies) ?? true }.max { $0.quality < $1.quality }
    }

    private func localAsset(_ trackId: String, atLeast wanted: AudioQuality?) -> PlayableAsset? {
        // Each failed attempt removes the entry it tried, so this ends.
        while let e = bestLocal(trackId, atLeast: wanted) {
            if let asset = localAsset(key: e.key) { return asset }
        }
        return nil
    }

    private func localAsset(key: String) -> PlayableAsset? {
        guard let e = entries[key], e.complete else { return nil }
        let url = directories.directory(e.kind).appendingPathComponent(e.file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lost(key)
            return nil
        }
        touch(key)
        // A cache file could be evicted from under the player; a download can't.
        let lease = e.kind == .cache ? acquire(key, .local) : nil
        return PlayableAsset(asset: bind(lease, to: AVURLAsset(url: url)), quality: e.quality, codec: e.codec,
                             bitrateKbps: e.bitrateKbps, isLocal: true, retainer: lease)
    }

    private nonisolated(unsafe) static let leaseKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// Belt and braces for `retainer`: the asset itself also keeps its lease (and with it
    /// the loader and the transfer), so an item can't outlive what feeds it.
    private func bind(_ lease: Lease?, to asset: AVURLAsset) -> AVURLAsset {
        if let lease { objc_setAssociatedObject(asset, Self.leaseKey, lease, .OBJC_ASSOCIATION_RETAIN) }
        return asset
    }

    /// The entry a request for `track` at `quality` maps to, asking the server only when
    /// nothing on disk already answers that (so a prefetched or half-cached track starts
    /// without a round trip, even on a dead link).
    private func open(_ track: Track, _ quality: AudioQuality) async throws -> String {
        let mine = entries(of: track.id)
        if let e = mine.filter({ $0.complete && $0.satisfies(quality) }).max(by: { $0.quality < $1.quality }) {
            return e.key
        }
        if let e = mine.filter({ !$0.complete && $0.continues(quality) }).max(by: { $0.quality < $1.quality }) {
            return e.key
        }
        let request = OpenRequest(trackId: track.id, quality: quality)
        if let running = opening[request] { return try await running.value }
        let service = self.service
        let task = Task { () throws -> String in
            defer { self.opening[request] = nil }
            let stream = try await service.stream(for: track, quality: quality)
            return try self.adopt(stream, for: track, asked: quality)
        }
        opening[request] = task
        return try await task.value
    }

    private func adopt(_ stream: StreamSource, for track: Track, asked: AudioQuality) throws -> String {
        var remote = RemoteStream(url: stream.url)
        if let hex = stream.key {
            guard let key = StreamCipher.key(hex: hex) else { throw TransferError.badKey }
            remote.key = key
        }
        let bitrate = stream.bitrateKbps.flatMap { $0 > 0 ? $0 : nil }
        let key = StoredEntry.key(track.id, stream.quality)
        var e = entries[key] ?? StoredEntry(track: track, quality: stream.quality, asked: stream.quality,
                                            codec: stream.codec, bitrateKbps: bitrate)
        e.track = track
        e.asked = max(e.asked, asked)
        if !e.complete, live[key]?.transfer == nil {
            e.codec = stream.codec
            e.bitrateKbps = bitrate
            fresh[key] = remote
        }
        entries[key] = e
        scheduleSave()
        return key
    }

    /// A transfer's URL stopped working: sign a new one for the very same file.
    private func resolveAgain(_ key: String) async -> ResolveOutcome {
        guard let e = entries[key] else { return .refused(TransferError.closed) }
        do {
            let s = try await service.stream(for: e.track, quality: e.quality, codecs: e.codec.isEmpty ? [] : [e.codec])
            guard s.quality == e.quality, s.codec == e.codec || e.codec.isEmpty else { return .changed }
            var remote = RemoteStream(url: s.url)
            if let hex = s.key {
                guard let key = StreamCipher.key(hex: hex) else { return .refused(TransferError.badKey) }
                remote.key = key
            }
            return .resolved(remote)
        } catch where error.isNetworkFailure {
            return .unreachable
        } catch {
            return .refused(error)
        }
    }

    // MARK: Leases

    private func acquire(_ key: String, _ use: Use) -> Lease {
        var l = live[key] ?? Live()
        if l.transfer == nil, let e = entries[key], !e.complete {
            let transfer = Transfer(
                engine: engine, name: AudioDirectories.name(e.track.id, e.quality),
                workDirectory: directories.cache, destination: directories.cache, codec: e.codec,
                remote: fresh.removeValue(forKey: key),
                resolver: { [weak self] in await self?.resolveAgain(key) ?? .refused(TransferError.closed) },
                onEvent: { [weak self] transfer, event in
                    // The main queue keeps the events in the order they happened.
                    DispatchQueue.main.async { self?.handle(event, from: transfer, key: key) }
                })
            transfer.start()
            l.transfer = transfer
        }
        l.uses[use, default: 0] += 1
        live[key] = l
        applyUses(key)
        return Lease(key: key, use: use) { [weak self] key, use in
            DispatchQueue.main.async { self?.release(key, use) }
        }
    }

    private func drop(_ lease: Lease?) {
        guard let lease, lease.end() else { return }
        release(lease.key, lease.use)
    }

    private func release(_ key: String, _ use: Use) {
        guard var l = live[key] else { return }
        let n = (l.uses[use] ?? 0) - 1
        l.uses[use] = n > 0 ? n : nil
        guard l.uses.isEmpty else {
            live[key] = l
            applyUses(key)
            return
        }
        live[key] = nil
        l.transfer?.stop()
        if let e = entries[key], e.kind == .download {
            // Promoted while it was playing from the cache: that name is no longer needed.
            let stale = directories.cache.appendingPathComponent(e.file)
            engine.queue.async { try? FileManager.default.removeItem(at: stale) }
        }
        evictIfNeeded()
    }

    /// Tell the transfer what its current users need from it.
    private func applyUses(_ key: String) {
        guard let l = live[key], let transfer = l.transfer else { return }
        func has(_ use: Use) -> Bool { (l.uses[use] ?? 0) > 0 }
        if has(.player) || has(.download) || has(.prefetchAll) {
            transfer.setFill(.everything)
        } else if has(.prefetchHead) {
            transfer.setFill(.head(Self.prefetchHeadBytes))
        } else {
            transfer.setFill(.onDemand)
        }
        // A file someone is downloading lands straight in Downloads when it completes.
        transfer.setDestination(has(.download) ? directories.downloads : directories.cache)
    }

    // MARK: Transfer events

    private func handle(_ event: Transfer.Event, from transfer: Transfer, key: String) {
        let current = live[key]?.transfer === transfer
        switch event {
        case .progress(let have, let total):
            guard current, var e = entries[key], !e.complete else { return }
            cacheBytes += have - e.bytes
            e.bytes = have
            e.totalBytes = total
            entries[key] = e
            if total > 0, let id = jobs.first(where: { $0.value.key == key })?.key {
                states[id] = .downloading(min(1, Double(have) / Double(total)))
            }
            if cacheBytes > settings.cacheLimitBytes { evictIfNeeded() }

        case .completed(let file, let directory, let total):
            // Even from a transfer we already let go of: the file is finished either way.
            guard var e = entries[key], !e.complete else { return }
            e.complete = true
            e.bytes = total
            e.totalBytes = total
            e.file = file.lastPathComponent
            e.kind = directory == directories.downloads ? .download : .cache
            e.added = Date()
            entries[key] = e
            localRevision += 1
            let id = e.track.id
            if let job = jobs[id], job.key == key {
                // The job may have attached after the transfer picked its destination.
                if e.kind == .download || promote(key) {
                    finishJob(id)
                } else {
                    failJob(id, TransferError.disk(EIO).localizedDescription)
                }
            } else if e.kind == .download {
                // Landed in Downloads but the download was cancelled meanwhile.
                demote(key)
            }
            // A finished prefetch keeps only a plain hold, so it isn't evicted before it plays.
            syncPrefetch()
            dropLesserCopies(of: key)
            refreshTotals()
            refreshDownloaded()
            evictIfNeeded()
            scheduleSave()

        case .failed(let error):
            guard current else { return }
            live[key]?.transfer = nil
            if case .remoteChanged = error {
                // The transfer already deleted its files; forget the entry with them.
                entries[key] = nil
                fresh[key] = nil
                refreshTotals()
                scheduleSave()
            }
            if prefetching?.key == key { cancelPrefetch() }
            if case .disk = error {
                // Most likely out of space: give back whatever cache nobody is using.
                for (k, e) in entries where e.kind == .cache && live[k] == nil { delete(k) }
                refreshTotals()
                scheduleSave()
            }
            if (live[key]?.uses[.player] ?? 0) > 0 { onStreamFailure?(Self.trackId(of: key), error) }
            guard let (id, job) = jobs.first(where: { $0.value.key == key }) else { return }
            if case .remoteChanged = error, job.restarts < 2 {
                // Not the user's problem: fetch the new file from the start.
                end(job)
                var next = Job(track: job.track)
                next.restarts = job.restarts + 1
                jobs[id] = next
                states[id] = .downloading(0)
                jobs[id]?.task = Task { [weak self] in await self?.run(id) }
            } else {
                failJob(id, error.localizedDescription)
            }
        }
    }

    /// A better (or equal) file for the track is complete: cached lower-quality copies of
    /// it are dead weight.
    private func dropLesserCopies(of key: String) {
        guard let done = entries[key] else { return }
        for e in entries(of: done.track.id)
        where e.key != key && e.kind == .cache && e.quality <= done.quality && live[e.key] == nil {
            delete(e.key)
        }
    }

    // MARK: Prefetch

    private func cancelPrefetch() {
        guard let p = prefetching else { return }
        prefetching = nil
        p.task?.cancel()
        drop(p.lease)
    }

    /// (Re)take the prefetch lease that fits the current link.
    private func syncPrefetch() {
        guard let p = prefetching, let key = p.key, let e = entries[key] else { return }
        let metered = network.isExpensive || network.isConstrained
        // Once complete, only a cache file needs holding (so it survives until it plays).
        let use: Use? = e.complete ? (e.kind == .cache ? .local : nil) : metered ? .prefetchHead : .prefetchAll
        guard p.lease?.use != use else { return }
        prefetching?.lease = use.map { acquire(key, $0) }
        drop(p.lease)
    }

    // MARK: Downloads

    private var downloadsAllowed: Bool {
        networkKnown && network.isOnline && (!network.isExpensive || settings.downloadOverCellular)
    }

    /// Start, or put back in the queue, whatever the current link and settings call for.
    private func pumpDownloads() {
        if downloadsAllowed {
            for p in pending where jobs.count < Self.maxDownloads {
                let id = p.track.id
                guard jobs[id] == nil, states[id] == .queued else { continue }
                jobs[id] = Job(track: p.track)
                states[id] = .downloading(0)
                jobs[id]?.task = Task { [weak self] in await self?.run(id) }
            }
        } else {
            // Wait for a link we may use. What was fetched stays on disk and is continued.
            for (id, job) in jobs {
                end(job)
                states[id] = .queued
            }
            jobs = [:]
        }
        updateBackgroundTask()
    }

    /// First half of a download: find or create the file and attach to its transfer.
    /// The second half is the transfer's `.completed` event.
    private func run(_ id: String) async {
        guard let track = jobs[id]?.track else { return }
        let wanted = settings.downloadQuality
        var delay = 0.5
        while !Task.isCancelled, jobs[id] != nil {
            // Already cached in full at this quality or better: just keep that file.
            if let e = bestLocal(id, atLeast: wanted), promote(e.key) {
                finishJob(id)
                return
            }
            do {
                let key = try await open(track, wanted)
                guard !Task.isCancelled, jobs[id] != nil else { return }
                if let e = entries[key], !e.complete {
                    jobs[id]?.key = key
                    jobs[id]?.lease = acquire(key, .download)
                    if e.totalBytes > 0 { states[id] = .downloading(min(1, Double(e.bytes) / Double(e.totalBytes))) }
                    return
                }
                if promote(key) {
                    finishJob(id)
                    return
                }
                // The finished file had vanished; its entry is gone now, so go round again.
                try? await Task.sleep(for: .milliseconds(200))
            } catch where error.isNetworkFailure {
                // The link is supposed to be up (else the job would be parked): try again soon.
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 8)
            } catch {
                failJob(id, error.localizedDescription)
                return
            }
        }
    }

    private func end(_ job: Job) {
        job.task?.cancel()
        drop(job.lease)
    }

    private func finishJob(_ id: String) {
        if let job = jobs.removeValue(forKey: id) { end(job) }
        pending.removeAll { $0.track.id == id }
        states[id] = .downloaded
        refreshTotals()
        refreshDownloaded()
        scheduleSave()
        pumpDownloads()
    }

    private func failJob(_ id: String, _ message: String) {
        if let job = jobs.removeValue(forKey: id) { end(job) }
        states[id] = .failed(message)
        pumpDownloads()
    }

    /// Turn a complete cache file into a download. False if the file is gone.
    private func promote(_ key: String) -> Bool {
        guard var e = entries[key], e.complete else { return false }
        if e.kind == .download { return true }
        let fm = FileManager.default
        let from = directories.cache.appendingPathComponent(e.file)
        let to = directories.downloads.appendingPathComponent(e.file)
        // Same volume, so these are instant; done here so the entry never points at a
        // file that isn't there yet.
        do {
            try? fm.createDirectory(at: directories.downloads, withIntermediateDirectories: true)
            try? fm.removeItem(at: to)
            if live[key] != nil {
                // A player has the cache file open by path: leave that name in place
                // (removed when the player lets go) and give the download a second one.
                do { try fm.linkItem(at: from, to: to) } catch { try fm.copyItem(at: from, to: to) }
            } else {
                try fm.moveItem(at: from, to: to)
            }
        } catch {
            lost(key)
            return false
        }
        e.kind = .download
        e.added = Date()
        entries[key] = e
        return true
    }

    /// A file that completed as a download nobody wants any more becomes plain cache.
    private func demote(_ key: String) {
        guard var e = entries[key], e.kind == .download else { return }
        let from = directories.downloads.appendingPathComponent(e.file)
        let to = directories.cache.appendingPathComponent(e.file)
        try? FileManager.default.removeItem(at: to)
        guard (try? FileManager.default.moveItem(at: from, to: to)) != nil else {
            delete(key)
            return
        }
        e.kind = .cache
        entries[key] = e
    }

    private func updateBackgroundTask() {
        #if canImport(UIKit)
        if jobs.isEmpty {
            endBackgroundTask()
        } else if backgroundTask == .invalid {
            // Lets the downloads in flight finish (or get as far as iOS allows) after the
            // app goes to the background; whatever is left continues on the next launch.
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ym.downloads") { [weak self] in
                MainActor.assumeIsolated {
                    self?.saveNow()
                    self?.endBackgroundTask()
                }
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    #endif

    // MARK: Disk bookkeeping

    private func touch(_ key: String) {
        entries[key]?.lastUsed = Date()
        scheduleSave()
    }

    /// Forget an entry and remove its files. A transfer still attached to it is stopped
    /// (its readers fail); callers only do that for entries nobody uses.
    private func delete(_ key: String) {
        guard let e = entries.removeValue(forKey: key) else { return }
        fresh[key] = nil
        if e.complete { localRevision += 1 }
        if let transfer = live[key]?.transfer {
            live[key]?.transfer = nil
            transfer.stop()
        }
        let files = Transfer.leftovers(name: AudioDirectories.name(e.track.id, e.quality), in: directories.cache)
            + (e.file.isEmpty ? [] : [directories.directory(e.kind).appendingPathComponent(e.file)])
        // On the I/O queue: after the transfer's own shutdown, which still writes its map.
        engine.queue.async {
            for url in files { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// A complete file turned out to be gone (Caches purged, deleted behind our back).
    private func lost(_ key: String) {
        guard let e = entries[key] else { return }
        delete(key)
        if e.kind == .download, entries(of: e.track.id).allSatisfy({ $0.kind != .download }) {
            // The user still wants it offline: fetch it again.
            states[e.track.id] = .queued
            if !pending.contains(where: { $0.track.id == e.track.id }) { pending.append(PendingDownload(track: e.track)) }
        }
        refreshTotals()
        refreshDownloaded()
        scheduleSave()
    }

    private func apply(_ audit: AudioDirectories.Audit) {
        for key in audit.missing {
            // Unless it has been fetched again in the meantime.
            guard let e = entries[key], e.complete, !FileManager.default.fileExists(
                atPath: directories.directory(e.kind).appendingPathComponent(e.file).path) else { continue }
            lost(key)
        }
        let wanted = Set(pending.map(\.track.id))
        for (key, bytes) in audit.partial {
            guard var e = entries[key], !e.complete, live[key] == nil else { continue }
            if bytes == 0, !wanted.contains(e.track.id), fresh[key] == nil {
                // Never got anywhere (a prefetch that was cancelled at once): no point keeping it.
                entries[key] = nil
                continue
            }
            e.bytes = bytes
            entries[key] = e
        }
        refreshTotals()
        refreshDownloaded()
        scheduleSave()
        pumpDownloads()
    }

    /// Keep the cache within the user's limit: least recently used first, never a file in
    /// use, never the partial file of a queued download, never a download.
    private func evictIfNeeded() {
        let limit = settings.cacheLimitBytes
        guard cacheBytes > limit else { return }
        let wanted = Set(pending.map(\.track.id))
        let victims = entries.values
            .filter { $0.kind == .cache && live[$0.key] == nil && ($0.complete || !wanted.contains($0.track.id)) }
            .sorted { $0.lastUsed < $1.lastUsed }
        var size = cacheBytes
        for e in victims where size > limit {
            delete(e.key)
            size -= e.bytes
        }
        refreshTotals()
        scheduleSave()
    }

    private func refreshTotals() {
        var cache: Int64 = 0, downloads: Int64 = 0
        for e in entries.values {
            if e.kind == .download { downloads += e.bytes } else { cache += e.bytes }
        }
        if cacheBytes != cache { cacheBytes = cache }
        if downloadsBytes != downloads { downloadsBytes = downloads }
    }

    private func refreshDownloaded() {
        let list = entries.values.filter { $0.kind == .download }.sorted { $0.added > $1.added }.map(\.track)
        if list != downloaded { downloaded = list }
    }

    /// Persist the index soon; changes arriving together make one write.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let index = StoreIndex(entries: Array(entries.values), pending: pending)
        indexQueue.async { [directories] in directories.save(index) }
    }

    // MARK: Signals

    private func reportThroughput(_ bytesPerSecond: Double) {
        // Compare against the stream a player is waiting on, if there is one.
        let playing = live.compactMap { key, l -> Int? in
            guard l.transfer != nil, (l.uses[.player] ?? 0) > 0, let e = entries[key], !e.complete else { return nil }
            if let kbps = e.bitrateKbps { return kbps }
            guard e.totalBytes > 0, e.track.durationMs > 0 else { return nil }
            return Int(e.totalBytes * 8 / Int64(e.track.durationMs))
        }.max()
        quality.reportThroughput(bytesPerSecond: bytesPerSecond, bitrateKbps: playing.map(Double.init))
    }

    /// React to the link and to settings: retry at once on a path change, park or resume
    /// downloads, widen or narrow the prefetch, re-check the cache limit.
    private func watch() {
        // `NetworkMonitor` starts out optimistic; its first update says what the link really
        // is. Downloads wait for it so none slips onto cellular (but not forever).
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.networkKnown else { return }
            self.networkKnown = true
            self.pumpDownloads()
        }
        watchTask = Task { [weak self, network, settings] in
            var lastGeneration = network.generation
            while !Task.isCancelled {
                do {
                    guard let self else { return }
                    let generation = network.generation
                    if generation > 0 { self.networkKnown = true }
                    if generation != lastGeneration {
                        lastGeneration = generation
                        self.engine.queue.async { [engine = self.engine] in engine.linkChanged() }
                        for l in self.live.values { l.transfer?.networkChanged() }
                    }
                    self.pumpDownloads()
                    self.syncPrefetch()
                    self.evictIfNeeded()
                }
                await withCheckedContinuation { (changed: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = network.generation
                        _ = network.isOnline
                        _ = network.isExpensive
                        _ = network.isConstrained
                        _ = settings.downloadOverCellular
                        _ = settings.cacheLimitBytes
                    } onChange: {
                        changed.resume()
                    }
                }
            }
        }
    }
}
