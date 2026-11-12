import AVFoundation
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Playback engine. Public API is fixed (UI codes against it).
/// Pipeline: `TrackStore` asset (file on disk or cache-through stream) -> `AVPlayerItem` -> one `AVPlayer`.
///
/// Nothing here runs per frame. State follows KVO and notifications; the clock is a 0.5 s time
/// observer that exists only while the app is in the foreground; the spectrum is computed on the
/// audio thread by a tap, and only while a visualiser is on screen.
@Observable
final class Player {
    var service: any MusicService

    private(set) var queue: [Track] = []
    private(set) var index: Int = 0
    /// What the user asked for: stays true while buffering, stalled or retrying.
    private(set) var isPlaying = false
    /// Refreshed twice a second in the foreground and on every state change; not in the background.
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Band energies for the wave backdrop (polled by the renderer, not observed).
    @ObservationIgnored let spectrumSource = SpectrumSource()
    /// Station id when playing "My Wave", else nil.
    private(set) var waveStationId: String?
    /// True while the current track is being fetched, or playback waits for data.
    private(set) var buffering = false

    /// What is actually playing (set when a track starts).
    private(set) var currentQuality: AudioQuality?
    /// `flac-mp4`, `aac-mp4`, `he-aac-mp4`, … (may be empty).
    private(set) var currentCodec = ""
    private(set) var currentBitrateKbps: Int?
    /// The current track plays from a file on disk (download or cache): no network involved.
    private(set) var isLocalPlayback = false
    /// Short user-facing status, e.g. "Нет сети — играет скачанное". `nil` = nothing to say.
    private(set) var notice: String?

    enum RepeatMode: Sendable { case off, all, one }
    var repeatMode: RepeatMode = .off

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var progress: Double { duration > 0 ? elapsed / duration : 0 }

    /// Output volume, 0...1. Not observed, not persisted.
    var volume: Float {
        get { avPlayer.volume }
        set { avPlayer.volume = newValue }
    }

    // MARK: Internals

    // The "downloaded only" switch is not a network failure: say which of the two it is.
    private static let noticeNoNetPlayingDownloaded = "Нет сети — играет скачанное"
    private static let noticeNoNet = "Нет сети. Скачанные треки — в Коллекции"
    private static let noticeModePlayingDownloaded = "Офлайн-режим — играет скачанное"
    private static let noticeMode = "Офлайн-режим: трек не скачан"
    private static var playingDownloadedNotices: Set<String> { [noticeNoNetPlayingDownloaded, noticeModePlayingDownloaded] }
    private var noticePlayingDownloaded: String {
        settings.offlineMode ? Self.noticeModePlayingDownloaded : Self.noticeNoNetPlayingDownloaded
    }
    private var noticeOffline: String { settings.offlineMode ? Self.noticeMode : Self.noticeNoNet }
    private static let noticeWaiting = "Нет сети — ждём соединения"
    /// Delays before retrying a failed track in place.
    private static let backoff: [Double] = [0.5, 1.5, 3]

    /// Work parked until the network returns.
    private enum Deferred {
        /// Start the current track from the top.
        case startTrack
        /// Go on past the current track (a wave waiting for its refill).
        case advance
        /// (Re)start a wave that couldn't fetch its first tracks.
        case wave(String)
        /// Continue a track that died mid-way; only if nothing else happened since.
        case load(Track, generation: Int)
    }

    private let store: TrackStore
    private let quality: QualityController
    private let network: NetworkMonitor
    private let settings: AppSettings
    private let avPlayer = AVPlayer()
    private let nowPlaying = NowPlaying()
    /// Tells the spectrum analysers (audio thread) where the playhead is.
    private let playhead = PlayheadClock()

    // Current item.
    @ObservationIgnored private var item: AVPlayerItem?
    /// `item` reached `readyToPlay` at least once, so its clock means something.
    @ObservationIgnored private var itemReady = false
    /// Keeps the store's streaming machinery alive for as long as `item` is.
    @ObservationIgnored private var retainer: AnyObject?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var playerObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?

    /// Bumped whenever what should be sounding changes (new track, reload, stop). Every async
    /// continuation captures it and backs off when it is stale, so rapid skips can't play an old track.
    @ObservationIgnored private var generation = 0
    /// No track in progress (never started, queue finished, or parked offline).
    @ObservationIgnored private var idle = true
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    /// Where the next item built for the current track begins.
    @ObservationIgnored private var resumePosition: TimeInterval = 0
    /// Target of a seek that hasn't landed yet (the player still reports the old time).
    @ObservationIgnored private var seekTarget: TimeInterval?
    @ObservationIgnored private var seekSerial = 0

    // The listen in progress.
    /// The track that actually produced sound; `nil` until it does.
    @ObservationIgnored private var session: Track?
    /// Seconds heard before `segmentStart` (seeks and reloads split a listen into segments).
    @ObservationIgnored private var listened: TimeInterval = 0
    @ObservationIgnored private var segmentStart: TimeInterval = 0
    /// In-place retries spent on the current track / tracks given up on in a row.
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var failures = 0

    // Weak network.
    /// A stream's header is being fetched: no item yet, but already waiting for data.
    @ObservationIgnored private var loadingStream = false
    @ObservationIgnored private var stallReported = false
    /// When the current item last ran out of data mid-play.
    @ObservationIgnored private var lastDry: ContinuousClock.Instant?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    /// The stall outlived the downgrade deadline; a path change is worth a reload.
    @ObservationIgnored private var stalledLong = false
    /// Backstop for an item that neither plays nor fails. Outlives short bursts of sound.
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    /// Since when sound has been coming out without a break.
    @ObservationIgnored private var soundSince: ContinuousClock.Instant?
    /// What to do once the network is usable again. Dropped by any newer transport action.
    @ObservationIgnored private var whenOnline: Deferred?
    @ObservationIgnored private var networkWatch: Task<Void, Never>?

    // My Wave.
    @ObservationIgnored private var refilling = false
    @ObservationIgnored private var waveTask: Task<Void, Never>?
    @ObservationIgnored private var awaitingRefill = false

    @ObservationIgnored private var resumeAfterInterruption = false

    init(service: any MusicService, store: TrackStore, quality: QualityController,
         network: NetworkMonitor, settings: AppSettings) {
        self.service = service
        self.store = store
        self.quality = quality
        self.network = network
        self.settings = settings
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.actionAtItemEnd = .pause
        // Audio-only: AirPlay goes through the audio route, which keeps the tap working.
        avPlayer.allowsExternalPlayback = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        // The store's loader can die without the item ever failing (the player just plays
        // out its buffer and waits): it tells us instead.
        store.onStreamFailure = { [weak self] trackId, _ in self?.streamFailed(trackId) }
        installRemoteCommands()
        observePlayer()
        observeSession()
        observeAppLifecycle()
        watchNetwork()
    }

    // MARK: Public API

    func playWave(_ stationId: String) {
        waveTask?.cancel()
        closeSession()
        generation += 1
        teardownItem()
        waveStationId = stationId
        queue = []
        index = 0
        idle = false
        awaitingRefill = false
        whenOnline = nil
        failures = 0
        isPlaying = true
        duration = 0
        resetPosition()
        clearStreamInfo()
        updateBuffering()
        guard networkUsable else {
            parkOffline(resume: .wave(stationId))
            return
        }
        let svc = service
        waveTask = Task {
            await svc.waveFeedback(stationId: stationId, track: nil, event: .radioStarted)
            var batch: [Track] = []
            var offline = false
            do {
                batch = try await svc.waveTracks(stationId: stationId, queue: [])
            } catch {
                offline = !networkUsable || error.isNetworkFailure
            }
            guard !Task.isCancelled, waveStationId == stationId else { return }
            guard !batch.isEmpty else {
                if offline { parkOffline(resume: .wave(stationId)) } else { finishQueue() }
                return
            }
            queue = batch
            index = 0
            start(autoplay: isPlaying)
        }
    }

    func play(_ tracks: [Track], startAt: Int = 0) {
        guard !tracks.isEmpty else { return }
        waveTask?.cancel()
        waveStationId = nil
        queue = tracks
        index = min(max(startAt, 0), tracks.count - 1)
        failures = 0
        start()
    }

    /// Insert right after the current track.
    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            play(tracks)
        } else {
            queue.insert(contentsOf: tracks, at: min(index + 1, queue.count))
            prefetchNext()
        }
    }

    /// Append to the end of the queue.
    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            play(tracks)
        } else {
            let wasLast = index == queue.count - 1
            queue.append(contentsOf: tracks)
            if wasLast { prefetchNext() }
        }
    }

    func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    func next() {
        reportLeaving(finished: false)
        advance()
    }

    func previous() {
        // `position`, not `elapsed`: the latter isn't kept fresh in the background.
        if position > 3 || index == 0 {
            seek(to: 0)
        } else {
            reportLeaving(finished: false)
            index -= 1
            start()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard !idle, current != nil else { return }
        let t = max(0, min(seconds, max(duration - 0.1, 0)))
        listened += max(0, position - segmentStart)
        segmentStart = t
        // Also where a reload (or an item still being fetched) will begin.
        resumePosition = t
        elapsed = t
        playhead.stop()
        if let item {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if item.status == .readyToPlay {
                seekSerial += 1
                let serial = seekSerial
                seekTarget = t
                item.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.seekFinished(serial) }
                }
            } else {
                item.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
            }
        }
        publishNowPlaying()
    }

    func dislikeCurrent() {
        guard let track = current else { return }
        if let station = waveStationId {
            let svc = service
            Task { await svc.waveFeedback(stationId: station, track: track, event: .dislike) }
        }
        advance()
    }

    // MARK: Transport

    func pause() {
        avPlayer.pause()
        // Parked offline: a pause means "don't start by yourself when the network is back".
        if idle { whenOnline = nil }
        guard isPlaying else { return }
        isPlaying = false
        elapsed = position
        updateBuffering()
        publishNowPlaying()
    }

    func resume() {
        if idle {
            // Nothing loaded (queue finished, or parked offline): start over.
            if current != nil { start() } else if let station = waveStationId { playWave(station) }
            return
        }
        // Mid-fetch / mid-retry there is no item yet; it starts by itself once it arrives.
        isPlaying = true
        if item != nil {
            activateSession()
            go()
        }
        updateBuffering()
        publishNowPlaying()
    }

    /// Begin the current queue entry from the top. `autoplay: false` keeps a pause the user asked for
    /// when the start isn't their doing (a refill landing, a failed track being skipped).
    private func start(autoplay: Bool = true) {
        closeSession()
        generation += 1
        teardownItem()
        guard let track = current else { finishQueue(); return }
        idle = false
        awaitingRefill = false
        whenOnline = nil
        retries = 0
        isPlaying = autoplay
        duration = Double(track.durationMs) / 1000
        resetPosition()
        clearStreamInfo()
        updateBuffering()
        publishNowPlaying()
        load(track)
    }

    /// Ask the store for something playable and hand it to the player. Used for a fresh start
    /// and for every retry / quality change (those resume at `resumePosition`).
    private func load(_ track: Track) {
        let gen = generation
        // Restoring quality needs nothing special: every (re)start takes whatever the
        // controller allows right now.
        let wanted = quality.effective
        let allowNetwork = networkUsable
        loadTask?.cancel()
        loadTask = Task {
            do {
                let playable = try await store.playable(for: track, quality: wanted, allowNetwork: allowNetwork)
                guard gen == generation else { return }
                adopt(playable)
                // The tap has to be on the item before it plays (adding it later restarts the
                // audio pipeline: an audible gap) and it needs the asset's audio track. The item
                // needs that same header anyway, so waiting for it here costs no time.
                let mix = try await spectrumMix(for: playable.asset)
                guard gen == generation else { return }
                attach(playable.asset, mix: mix)
            } catch {
                guard gen == generation else { return }
                loadFailed(error, track: track)
            }
        }
    }

    /// The store answered: this is what will play. Its header is fetched next.
    private func adopt(_ playable: PlayableAsset) {
        retainer = playable.retainer
        currentQuality = playable.quality
        currentCodec = playable.codec
        currentBitrateKbps = playable.bitrateKbps
        isLocalPlayback = playable.isLocal
        if !playable.isLocal {
            // No item yet, so the player can't tell us it is waiting: a slow header is a stall too.
            loadingStream = true
            beginStall(confirmed: false)
        }
    }

    private func attach(_ asset: AVURLAsset, mix: AVAudioMix?) {
        let gen = generation
        let item = AVPlayerItem(asset: asset)
        item.audioMix = mix
        self.item = item
        loadingStream = false
        lastDry = nil
        if resumePosition > 0 {
            item.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        }
        observe(item, generation: gen)
        avPlayer.replaceCurrentItem(with: item)
        if isPlaying {
            activateSession()
            go()
        }
        updateBuffering()
    }

    /// Start (or resume) sound as soon as there is anything to play.
    ///
    /// Plain `play()` leaves the decision to `AVPlayer`, and with progressive downloads it is
    /// very cautious: it wants about half a minute buffered, which on a link twice as fast as
    /// the bitrate means 15-18 s of silence before every track. `playImmediately` starts with
    /// the first few seconds instead. Automatic waiting stays on, so if the data does run out
    /// the player falls back to waiting by itself (see `itemStalled`).
    private func go() {
        avPlayer.playImmediately(atRate: 1)
    }

    /// Stop sound and forget the item. Callers bump `generation` first.
    private func teardownItem() {
        loadTask?.cancel(); loadTask = nil
        retryTask?.cancel(); retryTask = nil
        loadingStream = false
        endStall()
        watchdog?.cancel()
        watchdog = nil
        soundSince = nil
        statusObservation?.invalidate()
        statusObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        seekSerial += 1
        seekTarget = nil
        itemReady = false
        playhead.stop()
        retainer = nil
        guard let old = item else { return }
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        // Lets go of the tap (and its analyser) now rather than whenever the item is freed.
        old.audioMix = nil
        item = nil
    }

    private func advance(autoplay: Bool = true) {
        if index + 1 < queue.count {
            index += 1
            start(autoplay: autoplay)
        } else if waveStationId != nil {
            // Wave ran dry: hold in buffering state until the refill lands.
            closeSession()
            generation += 1
            teardownItem()
            idle = false
            awaitingRefill = true
            whenOnline = nil
            isPlaying = autoplay
            resetPosition()
            updateBuffering()
            refillIfNeeded()
        } else if repeatMode == .all, !queue.isEmpty {
            index = 0
            start(autoplay: autoplay)
        } else {
            finishQueue()
        }
    }

    private func finishQueue() {
        closeSession()
        generation += 1
        teardownItem()
        idle = true
        awaitingRefill = false
        whenOnline = nil
        isPlaying = false
        resetPosition()
        updateBuffering()
        publishNowPlaying()
    }

    private func resetPosition() {
        resumePosition = 0
        segmentStart = 0
        elapsed = 0
    }

    private func clearStreamInfo() {
        currentQuality = nil
        currentCodec = ""
        currentBitrateKbps = nil
        isLocalPlayback = false
    }

    // MARK: Player events

    private func observePlayer() {
        // KVO may fire off the main thread, and mid-mutation: hop, then read the live state.
        playerObservations = [
            avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.timeControlChanged() }
            },
            avPlayer.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.timeControlChanged() }
            },
        ]
    }

    private func observe(_ item: AVPlayerItem, generation gen: Int) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.itemStatusChanged(gen) }
        }
        // No `queue: .main` for anything AVFoundation posts: that makes the posting thread wait
        // for the main thread, and it may be holding a lock the main thread is about to want.
        let nc = NotificationCenter.default
        itemObservers = [
            nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.itemEnded(gen) }
            },
            nc.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.itemFailed(gen) }
            },
            nc.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.itemStalled(gen) }
            },
        ]
    }

    private func itemStatusChanged(_ gen: Int) {
        guard gen == generation, let item else { return }
        switch item.status {
        case .readyToPlay:
            if !itemReady, let timebase = item.timebase {
                // The exact moment sound starts or stops: drives `buffering`, the stall clock
                // and the analyser's clock. Posted with the timebase locked: hop, never touch
                // the timebase in place.
                itemObservers.append(NotificationCenter.default.addObserver(
                    forName: CMTimebase.effectiveRateChanged, object: timebase, queue: nil) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.timeControlChanged() }
                    })
            }
            itemReady = true
            let d = item.duration.seconds
            if d.isFinite, d > 0 { duration = d }
            // The push given at attach time doesn't always survive until the item is ready.
            if isPlaying, !isAdvancing { go() }
            timeControlChanged()
            publishNowPlaying()
        case .failed:
            recover()
        default:
            break
        }
    }

    /// The player's status or the item's clock changed. Reads the live state, so it doesn't
    /// matter which event brought us here or how late.
    private func timeControlChanged() {
        guard item != nil else { return }
        switch avPlayer.timeControlStatus {
        case .playing:
            // After `playImmediately` the status says "playing" before any sound: trust the clock.
            if isAdvancing {
                if soundSince == nil { soundSince = .now }
                endStall()
                playbackBegan()
            } else {
                beginStall(confirmed: false)
            }
        case .waitingToPlayAtSpecifiedRate:
            if avPlayer.reasonForWaitingToPlay == .toMinimizeStalls { beginStall(confirmed: false) }
        case .paused:
            endStall()
        @unknown default:
            break
        }
        syncPlayhead()
        updateBuffering()
    }

    /// The item's clock is running: sound is actually coming out.
    private var isAdvancing: Bool {
        guard itemReady, let timebase = item?.timebase else { return false }
        return avPlayer.timeControlStatus == .playing && timebase.effectiveRate != 0
    }

    /// Sound is coming out. The first time for a track, that's its start.
    private func playbackBegan() {
        // Notices are all about a missing network; only "playing downloaded" still holds.
        if notice != nil, !(notice.map(Self.playingDownloadedNotices.contains) == true && isLocalPlayback && !networkUsable) {
            notice = nil
        }
        guard session == nil, let track = current else { return }
        session = track
        failures = 0
        sendWaveFeedback(.trackStarted, track: track)
        refillIfNeeded()
        prefetchNext()
    }

    private func itemEnded(_ gen: Int) {
        guard gen == generation else { return }
        reportLeaving(finished: true)
        guard repeatMode == .one, let item else { advance(); return }
        // Same item again: no refetch. The next `.playing` opens a new listen.
        closeSession()
        resetPosition()
        seekSerial += 1
        seekTarget = nil
        playhead.stop()
        item.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
        if isPlaying { go() }
        publishNowPlaying()
    }

    private func itemFailed(_ gen: Int) {
        guard gen == generation else { return }
        recover()
    }

    /// The store gave up on a stream (file changed, service refused, disk error).
    private func streamFailed(_ trackId: String) {
        guard !idle, !isLocalPlayback, item != nil || loadingStream, current?.id == trackId else { return }
        recover()
    }

    /// The item ran out of data mid-play.
    private func itemStalled(_ gen: Int) {
        guard gen == generation, isPlaying, !isLocalPlayback else { return }
        let now = ContinuousClock.now
        // The notification comes in bursts.
        if let lastDry, now - lastDry < .seconds(1) { return }
        let again = lastDry.map { now - $0 < .seconds(20) } ?? false
        lastDry = now
        guard again else {
            // First time in a while, and often not the network at all: a few seconds in, the
            // player's reader switches to half-minute blocks and starves the playhead while data
            // keeps arriving. Push it. If there really is nothing, the stall clock deals with it.
            beginStall(confirmed: false)
            go()
            return
        }
        // Dry again right after a push: the link can't carry this quality.
        beginStall(confirmed: true)
        if let playing = currentQuality, quality.effective < playing {
            reload()
            return
        }
        // Nothing lower to switch to: let some buffer build up, then push again.
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, gen == generation, isStalled else { return }
            go()
        }
    }

    private func updateBuffering() {
        let now: Bool
        if idle {
            now = false
        } else if let item {
            now = item.status == .unknown || (isPlaying && !isAdvancing)
        } else {
            // Resolving the asset, between retries, or waiting for a wave refill.
            now = true
        }
        guard now != buffering else { return }
        buffering = now
        if !now, seekTarget == nil { elapsed = position }
        // The lock screen extrapolates time from the rate: stop / re-anchor its clock.
        publishNowPlaying()
    }

    // MARK: Position and clock

    /// Live playback position. `elapsed` is the published copy of it.
    private var position: TimeInterval {
        if let seekTarget { return seekTarget }
        // An item that never got ready (still loading, or failed outright) has no time of its own.
        guard let item, itemReady else { return resumePosition }
        let t = item.currentTime().seconds
        guard t.isFinite else { return resumePosition }
        return max(0, duration > 0 ? min(t, duration) : t)
    }

    private func seekFinished(_ serial: Int) {
        guard serial == seekSerial else { return }
        seekTarget = nil
        // Landed somewhere unbuffered: don't let the player sit out its long wait there either.
        if isPlaying, !isAdvancing { go() }
        syncPlayhead()
        elapsed = position
        publishNowPlaying()
    }

    private func installClock() {
        guard timeObserver == nil else { return }
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshElapsed() }
        }
        refreshElapsed()
    }

    private func removeClock() {
        guard let timeObserver else { return }
        avPlayer.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func refreshElapsed() {
        guard !idle, seekTarget == nil else { return }
        let t = position
        if t != elapsed { elapsed = t }
        syncPlayhead()
    }

    /// Re-anchor the analyser's idea of the playhead (or say that it stands still).
    /// State changes and the foreground clock only; the audio thread extrapolates in between.
    private func syncPlayhead() {
        if itemReady, seekTarget == nil, let timebase = item?.timebase, timebase.effectiveRate == 1 {
            let now: CMTime = timebase.time
            playhead.run(from: now.seconds)
        } else {
            playhead.stop()
        }
    }

    /// The clock only matters while somebody can see it. In the background nothing in the
    /// app runs periodically; position is read on demand.
    private func observeAppLifecycle() {
        installClock()
        #if canImport(UIKit)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeClock() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.installClock() }
        }
        #endif
    }

    // MARK: Weak network

    /// Playback may use the network at all.
    private var networkUsable: Bool { network.isOnline && !settings.offlineMode }

    private var isStalled: Bool {
        isPlaying && (loadingStream || (item != nil && !isAdvancing))
    }

    /// Playback ran dry (`confirmed`) or is waiting for data. One stall = one report to the
    /// quality controller, sent once the wait has lasted; a long one gets a lower-quality item.
    private func beginStall(confirmed: Bool) {
        guard isPlaying, loadingStream || (item != nil && !isLocalPlayback) else { return }
        if confirmed { reportStallOnce() }
        guard stallTask == nil else { return }
        let gen = generation
        armWatchdog()
        stallTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, gen == generation, isStalled else { return }
            // No route at all: nothing will arrive on this item. Park the track until there is one.
            guard networkUsable else { reload(); return }
            reportStallOnce()
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, gen == generation, isStalled else { return }
                // Hardly anything of this track was heard, and the controller already asks for less:
                // there is no reason to keep waiting for the heavier file.
                if position < 5, let playing = currentQuality, quality.effective < playing {
                    reload()
                    return
                }
            }
            stalledLong = true
            // The controller has stepped down by now (if it may): continue this track at that level.
            if let playing = currentQuality, quality.effective < playing { reload() }
        }
    }

    /// An item can sit there ready, error-free and silent for ever. Half a minute without
    /// sound is treated as a failure: same retries, then the next track.
    private func armWatchdog() {
        // Sound held for a while since it was armed: that shortage is over, this is a new one.
        if let soundSince, ContinuousClock.now - soundSince >= .seconds(10) {
            watchdog?.cancel()
            watchdog = nil
        }
        soundSince = nil
        guard watchdog == nil else { return }
        let gen = generation
        watchdog = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, gen == generation else { return }
            watchdog = nil
            // Caught in a short burst of sound: the next stall arms it again.
            if isStalled { recover() }
        }
    }

    private func endStall() {
        stallTask?.cancel()
        stallTask = nil
        pushTask?.cancel()
        pushTask = nil
        stallReported = false
        stalledLong = false
    }

    private func reportStallOnce() {
        // Running dry with no network says nothing about the link's speed.
        guard !stallReported, networkUsable else { return }
        stallReported = true
        quality.reportStall()
    }

    /// Drop the item but stay on the track, remembering where to pick up.
    private func suspendItem() {
        let at = position
        listened += max(0, at - segmentStart)
        generation += 1
        teardownItem()
        resumePosition = at
        segmentStart = at
        updateBuffering()
    }

    /// Rebuild the current track's item in place (lower quality, or a fresh connection).
    private func reload() {
        guard let track = current else { return }
        suspendItem()
        if !waitsForNetwork(track) { load(track) }
    }

    /// A stream can't be (re)built without a usable network: park the track with a notice and
    /// pick it up when the network is back. False when there is nothing to wait for.
    private func waitsForNetwork(_ track: Track) -> Bool {
        guard !networkUsable, !store.hasLocalCopy(track.id) else { return false }
        notice = Self.noticeWaiting
        whenOnline = .load(track, generation: generation)
        return true
    }

    /// The item died. Retry the same track from where it was; the store re-resolves expired URLs.
    private func recover() {
        guard let track = current else { finishQueue(); return }
        // The last attempt got somewhere, so this is a new incident with a fresh budget.
        if position - segmentStart > 10 { retries = 0 }
        suspendItem()
        scheduleRetry(for: track)
    }

    private func loadFailed(_ error: Error, track: Track) {
        // Nothing got attached, but a header fetch may have left its stall clock and retainer.
        teardownItem()
        if let e = error as? TrackStoreError, case .notAvailableOffline = e, session == nil {
            playDownloadedOrPark()
        } else {
            // Includes "not available offline" for a track that was already sounding:
            // that one waits for the network instead of being abandoned mid-way.
            scheduleRetry(for: track)
        }
    }

    private func scheduleRetry(for track: Track) {
        // Retrying can't work without a route; keep the attempts for when there is one.
        if waitsForNetwork(track) { return }
        let gen = generation
        guard retries < Self.backoff.count else {
            failures += 1
            if failures >= 4 { finishQueue() } else { advance(autoplay: isPlaying) }
            return
        }
        let delay = Self.backoff[retries]
        retries += 1
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, gen == generation else { return }
            load(track)
        }
    }

    /// The current track isn't on disk and the network is off limits: play the next
    /// downloaded one, or park.
    private func playDownloadedOrPark() {
        var candidates = Array(queue.indices.dropFirst(index + 1))
        if repeatMode == .all, waveStationId == nil { candidates += queue.indices.prefix(index) }
        // `failures` bounds this if the store claims copies it then can't play.
        failures += 1
        if failures < 4, let local = candidates.first(where: { store.hasLocalCopy(queue[$0].id) }) {
            index = local
            notice = noticePlayingDownloaded
            start(autoplay: isPlaying)
        } else {
            parkOffline(resume: .startTrack)
        }
    }

    /// Nothing can play without the network: stay on the current track, paused, and pick up
    /// with `resume` when the network returns — if the user wanted sound.
    private func parkOffline(resume: Deferred) {
        let wanted = isPlaying
        closeSession()
        generation += 1
        teardownItem()
        idle = true
        awaitingRefill = false
        failures = 0
        isPlaying = false
        resetPosition()
        notice = noticeOffline
        whenOnline = wanted ? resume : nil
        updateBuffering()
        publishNowPlaying()
    }

    /// One long-lived observer of the network path and the offline switch; no polling.
    private func watchNetwork() {
        networkWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let network = self?.network, let settings = self?.settings else { return }
                self?.networkChanged()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = network.generation
                        _ = settings.offlineMode
                    } onChange: { c.resume() }
                }
            }
        }
    }

    private func networkChanged() {
        guard networkUsable else { return }
        if notice != nil { notice = nil }
        if let deferred = whenOnline {
            whenOnline = nil
            switch deferred {
            case .startTrack: start()
            case .advance: advance()
            case .wave(let station): playWave(station)
            case .load(let track, let gen): if gen == generation { load(track) }
            }
        } else if stalledLong, isStalled {
            // Stuck on a connection from the old path: start a new one.
            reload()
        }
    }

    // MARK: My Wave

    private func sendWaveFeedback(_ event: WaveFeedback, track: Track?) {
        guard let station = waveStationId else { return }
        let svc = service
        Task { await svc.waveFeedback(stationId: station, track: track, event: event) }
    }

    /// Reports how the current track ended (finished vs. skipped) to the wave.
    /// Tracks that never got to sound are not reported.
    private func reportLeaving(finished: Bool) {
        guard waveStationId != nil, let track = session else { return }
        let at = position
        if finished {
            sendWaveFeedback(.trackFinished(playedSeconds: max(at, duration)), track: track)
        } else {
            sendWaveFeedback(.skip(playedSeconds: at), track: track)
        }
    }

    private func refillIfNeeded() {
        guard let station = waveStationId, !refilling, queue.count - index - 1 < 2 else { return }
        guard networkUsable else {
            if awaitingRefill { parkOffline(resume: .advance) }
            return
        }
        refilling = true
        let svc = service
        let ids = queue.map(\.id)
        Task {
            var batch: [Track] = []
            var offline = false
            do {
                batch = try await svc.waveTracks(stationId: station, queue: ids)
            } catch {
                offline = !networkUsable || error.isNetworkFailure
            }
            refilling = false
            guard waveStationId == station else { return }
            let known = Set(queue.map(\.id))
            let fresh = batch.filter { !known.contains($0.id) }
            queue.append(contentsOf: fresh.isEmpty ? batch : fresh)
            if awaitingRefill {
                awaitingRefill = false
                if index + 1 < queue.count {
                    advance(autoplay: isPlaying)
                } else if offline {
                    parkOffline(resume: .advance)
                } else {
                    finishQueue()
                }
            } else {
                prefetchNext()
            }
        }
    }

    private func likeCurrent() {
        guard let track = current else { return }
        sendWaveFeedback(.like, track: track)
        let svc = service
        Task { try? await svc.setLiked(true, track: track) }
    }

    // MARK: Reporting and prefetch

    /// The listen in progress is over (finished, skipped, replaced): tell the service if it
    /// was a real one. Must run while the old item is still attached.
    private func closeSession() {
        defer { listened = 0 }
        guard let track = session else { return }
        session = nil
        let played = listened + max(0, position - segmentStart)
        guard played >= 10 else { return }
        let svc = service
        let fromCache = isLocalPlayback
        Task { await svc.reportPlay(track: track, playedSeconds: played, fromCache: fromCache) }
    }

    private func prefetchNext() {
        guard session != nil, networkUsable, repeatMode != .one else { return }
        var next: Track?
        if queue.indices.contains(index + 1) {
            next = queue[index + 1]
        } else if repeatMode == .all, waveStationId == nil, queue.count > 1 {
            next = queue[0]
        }
        if let next { store.prefetch(next, quality: quality.effective) }
    }

    // MARK: Spectrum

    /// Audio mix that feeds the wave backdrop, or `nil` (no audio track, tap refused): then
    /// the track just plays without it. Throws when the asset itself can't be read.
    private func spectrumMix(for asset: AVURLAsset) async throws -> AVAudioMix? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        return SpectrumTap.audioMix(for: track, publishingTo: spectrumSource, clock: playhead)
    }

    // MARK: System integration

    /// State changes only; the system keeps time by itself in between.
    private func publishNowPlaying() {
        nowPlaying.update(track: current, elapsed: position, duration: duration,
                          playing: isPlaying && !buffering)
    }

    private func installRemoteCommands() {
        nowPlaying.install(.init(
            play: { [weak self] in if self?.isPlaying == false { self?.togglePlay() } },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlay() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] t in self?.seek(to: t) },
            like: { [weak self] in self?.likeCurrent() },
            dislike: { [weak self] in self?.dislikeCurrent() }))
    }

    private func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func observeSession() {
        #if os(iOS)
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] n in
            let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opts = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in self?.handleInterruption(type, opts) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] n in
            let reason = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in self?.handleRouteChange(reason) }
        }
        #endif
    }

    #if os(iOS)
    private func handleInterruption(_ typeRaw: UInt?, _ optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if resumeAfterInterruption && opts.contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ reasonRaw: UInt?) {
        guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        // Headphones unplugged / Bluetooth gone: don't blast the speaker.
        if reason == .oldDeviceUnavailable && isPlaying { pause() }
    }
    #endif
}
