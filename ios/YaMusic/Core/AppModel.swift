import Foundation
import Observation

enum AppTab: Hashable { case home, collection, search }

/// App-wide state and wiring: service, player, settings, network, storage, library cache.
@Observable
final class AppModel {
    var tab: AppTab = .home
    var showNowPlaying = false
    var showAuth = false
    var showSettings = false
    /// Ids of liked tracks (for hearts). Loaded from cache at start, refreshed from the API.
    private(set) var likedIds: Set<String> = []

    private(set) var service: any MusicService
    let settings: AppSettings
    let network: NetworkMonitor
    let quality: QualityController
    let store: TrackStore
    let library: Library
    let player: Player

    /// Likes made while offline, flushed when the network is back. id -> desired state.
    @ObservationIgnored private var pendingLikes: [String: Bool] = [:]
    @ObservationIgnored private var networkWatch: Task<Void, Never>?
    private static let pendingKey = "ym.pending-likes"

    init() {
        #if DEBUG
        // Dev sign-in without the OAuth sheet: `-ymToken <token>` as a launch argument
        // (launch arguments land in the UserDefaults argument domain).
        if let t = UserDefaults.standard.string(forKey: "ymToken"), t.count >= 20 { TokenStore.save(t) }
        PerfProbe.startIfRequested()
        #endif
        let token = TokenStore.load()
        let service: any MusicService = Self.makeService(token: token)
        isSignedIn = token != nil
        let settings = AppSettings()
        let network = NetworkMonitor()
        let quality = QualityController(settings: settings, network: network)
        let store = TrackStore(service: service, settings: settings, network: network, quality: quality)
        self.service = service
        self.settings = settings
        self.network = network
        self.quality = quality
        self.store = store
        self.library = Library(service: service)
        self.player = Player(service: service, store: store, quality: quality, network: network, settings: settings)
        pendingLikes = (UserDefaults.standard.dictionary(forKey: Self.pendingKey) as? [String: Bool]) ?? [:]
        if let ids = library.cached(.likedIds) { likedIds = Set(ids) }
        applyPendingLocally()
        watchNetwork()
        Task { await refreshLikes() }
        #if DEBUG
        PerfProbe.status = { [player, quality, network, store] in
            "playing=\(player.isPlaying ? 1 : 0) buf=\(player.buffering ? 1 : 0) t=\(Int(player.elapsed)) "
                + "q=\(player.currentQuality?.rawValue ?? "-") local=\(player.isLocalPlayback ? 1 : 0) "
                + "want=\(quality.effective.rawValue) net=\(network.link.rawValue) "
                + "kbps=\(Int(quality.throughputKbps ?? 0)) dl=\(store.downloaded.count) "
                + "track=\(player.current?.id ?? "-") notice=\(player.notice ?? "-")"
        }
        // Dev launch arguments for repeatable on-device checks (see scripts/perf-ios.sh):
        //   -autoplay                      start My Wave
        //   -ymPlay wave|liked|downloads   start that source
        //   -ymOffline YES|NO              set the "downloaded only" switch (persists!)
        //   -ymQuality lq|nq|hq|lossless   set the Wi-Fi streaming quality (persists!)
        let d = UserDefaults.standard
        if d.object(forKey: "ymOffline") != nil { settings.offlineMode = d.bool(forKey: "ymOffline") }
        if let q = d.string(forKey: "ymQuality").flatMap(AudioQuality.init(rawValue:)) { settings.streamQualityWiFi = q }
        //   -ymThrottleKbps N [-ymThrottleSeconds S]   simulate a weak link for audio fetches
        //   -ymSkipEvery S                 press "next" every S seconds
        if d.double(forKey: "ymThrottleKbps") > 0 {
            let secs = d.double(forKey: "ymThrottleSeconds")
            FetchEngine.debugThrottle = (d.double(forKey: "ymThrottleKbps") * 1000 / 8,
                                         secs > 0 ? FetchEngine.now + secs : 0)
        }
        if d.double(forKey: "ymSkipEvery") > 0 {
            let every = d.double(forKey: "ymSkipEvery")
            Task { @MainActor [player] in
                while true {
                    try? await Task.sleep(for: .seconds(every))
                    player.next()
                }
            }
        }
        let source = d.string(forKey: "ymPlay")
            ?? (ProcessInfo.processInfo.arguments.contains("-autoplay") ? "wave" : nil)
        if let source {
            Task { @MainActor [self] in
                try? await Task.sleep(for: .seconds(1))
                switch source {
                case "downloads": player.play(store.downloaded)
                case "liked": player.play((try? await library.load(.liked)) ?? [])
                default: player.playWave("user:onyourwave")
                }
            }
        }
        #endif
    }

    /// Stored (not a Keychain read) so views update when it changes.
    private(set) var isSignedIn = false

    /// Playback may only use what's on disk: no route, or the user asked for it.
    var isOffline: Bool { !network.isOnline || settings.offlineMode }

    func signIn(token: String) {
        TokenStore.save(token)
        isSignedIn = true
        setService(Self.makeService(token: token))
        Task { await refreshLikes() }
    }

    func signOut() {
        TokenStore.clear()
        isSignedIn = false
        library.wipe()
        likedIds = []
        pendingLikes = [:]
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        setService(MockMusicService())
    }

    private func setService(_ s: any MusicService) {
        service = s
        player.service = s
        store.service = s
        library.service = s
    }

    // MARK: Likes

    func isLiked(_ track: Track) -> Bool { likedIds.contains(track.id) }

    func toggleLike(_ track: Track) {
        let on = !likedIds.contains(track.id)
        if on { likedIds.insert(track.id) } else { likedIds.remove(track.id) }
        // Keep the cached "liked" list in step so the collection is right even offline.
        if var list = library.cached(.liked) {
            list.removeAll { $0.id == track.id }
            if on { list.insert(track, at: 0) }
            library.store(list, for: .liked)
        }
        if on, settings.autoDownloadLiked { store.download([track]) }
        let svc = service
        Task {
            do {
                try await svc.setLiked(on, track: track)
            } catch where error.isNetworkFailure {
                pendingLikes[track.id] = on
                savePending()
            } catch {}
        }
    }

    /// Pull liked ids (cheap) and replay likes that were made offline.
    func refreshLikes() async {
        await flushPendingLikes()
        if let ids = try? await library.load(.likedIds) {
            likedIds = Set(ids)
            applyPendingLocally()
        }
    }

    private func flushPendingLikes() async {
        guard !pendingLikes.isEmpty, network.isOnline else { return }
        let svc = service
        for (id, on) in pendingLikes {
            do {
                try await svc.setLiked(on, track: Track(id: id, title: ""))
                pendingLikes[id] = nil
            } catch where error.isNetworkFailure {
                break
            } catch {
                pendingLikes[id] = nil
            }
        }
        savePending()
    }

    private func applyPendingLocally() {
        for (id, on) in pendingLikes {
            if on { likedIds.insert(id) } else { likedIds.remove(id) }
        }
    }

    private func savePending() {
        UserDefaults.standard.set(pendingLikes, forKey: Self.pendingKey)
    }

    // MARK: Network

    /// React to link changes: let the quality controller re-evaluate, flush offline likes.
    private func watchNetwork() {
        networkWatch = Task { [weak self] in
            var last = -1
            while !Task.isCancelled {
                guard let self else { return }
                let gen = self.network.generation
                if gen != last {
                    last = gen
                    self.quality.linkChanged()
                    if self.network.isOnline { await self.flushPendingLikes() }
                }
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    withObservationTracking { _ = self.network.generation } onChange: { c.resume() }
                }
            }
        }
    }

    // MARK: Library helpers

    /// Tracks of a destination: downloads come from the store, the rest from the library
    /// cache/API (cached copy is returned when the network is down).
    func tracks(of destination: Destination) async throws -> [Track] {
        if case .downloads = destination { return store.downloaded }
        return try await library.load(.tracks(destination))
    }

    /// Instant (possibly stale) version of `tracks(of:)`.
    func cachedTracks(of destination: Destination) -> [Track]? {
        if case .downloads = destination { return store.downloaded }
        return library.cached(.tracks(destination))
    }

    static func makeService(token: String?) -> any MusicService {
        guard let token else { return MockMusicService() }
        return (try? RustMusicService(token: token)) ?? MockMusicService()
    }
}

/// OAuth token in the Keychain.
enum TokenStore {
    private static let account = "ym-oauth-token"

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        clear()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                                kSecValueData as String: Data(token.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
