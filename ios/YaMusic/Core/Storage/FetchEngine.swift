import Foundation

/// Receives the callbacks of one HTTP fetch. Always called on `FetchEngine.queue`.
nonisolated protocol FetchClient: AnyObject {
    /// Return false to drop the fetch (no further callbacks for it).
    func fetch(_ id: Int, didReceive response: HTTPURLResponse) -> Bool
    func fetch(_ id: Int, didReceive data: Data)
    func fetch(_ id: Int, didCompleteWith error: (any Error)?)
}

/// The shared plumbing under every audio transfer: one `URLSession`, one serial queue that
/// all transfer state, file I/O and resource-loader callbacks live on (so none of it needs
/// locks), and a link-throughput meter.
nonisolated final class FetchEngine: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "ym.audio-io", qos: .userInitiated)

    /// Bytes per second over the last ~1 s of active receiving, summed over all fetches.
    /// Called on `queue`. Set once, before the first fetch.
    var onThroughput: (@Sendable (Double) -> Void)?

    private struct Route {
        weak var client: (any FetchClient)?
        let task: URLSessionDataTask
    }

    private var session: URLSession!
    private var routes: [Int: Route] = [:]

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        // The cache file is the cache; URLCache would only duplicate megabytes.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        // Idle timeout: a connection that went silent is dropped and resumed with Range.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 24 * 3600
        // Retrying is ours to do (with the path monitor), not URLSession's.
        config.waitsForConnectivity = false
        // A player's two range requests must never queue behind downloads and a prefetch
        // (the default on iOS is 4 connections per host).
        config.httpMaximumConnectionsPerHost = 8
        let callbacks = OperationQueue()
        callbacks.underlyingQueue = queue
        callbacks.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: callbacks)
    }

    // MARK: Fetches (call on `queue`)

    /// Start a request; `client` is called back with the returned id.
    /// `urgent`: someone is waiting for these bytes right now.
    func start(_ request: URLRequest, urgent: Bool, for client: any FetchClient) -> Int {
        let task = session.dataTask(with: request)
        task.priority = urgent ? URLSessionTask.highPriority : URLSessionTask.defaultPriority
        routes[task.taskIdentifier] = Route(client: client, task: task)
        task.resume()
        return task.taskIdentifier
    }

    /// Stop a fetch. `abort` tears the connection down; without it a request that has
    /// already received all it asked for is left to end on its own, keeping the connection.
    func drop(_ id: Int, abort: Bool = true) {
        guard let route = routes.removeValue(forKey: id) else { return }
        if abort { route.task.cancel() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let id = dataTask.taskIdentifier
        guard let client = routes[id]?.client, let http = response as? HTTPURLResponse,
              client.fetch(id, didReceive: http) else {
            routes[id] = nil
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        #if DEBUG
        if throttling {
            let id = dataTask.taskIdentifier
            let idle = slow[id] == nil
            slow[id, default: Slow()].pending.append(data)
            if idle { pump(id) }
            return
        }
        #endif
        routes[dataTask.taskIdentifier]?.client?.fetch(dataTask.taskIdentifier, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        #if DEBUG
        // Bytes still held back by the throttle must reach the client before its completion.
        if slow[task.taskIdentifier] != nil {
            slow[task.taskIdentifier]?.finished = .some(error)
            return
        }
        #endif
        finish(task.taskIdentifier, error: error)
    }

    private func finish(_ id: Int, error: (any Error)?) {
        guard let route = routes.removeValue(forKey: id) else { return }
        route.client?.fetch(id, didCompleteWith: error)
    }

    #if DEBUG
    // Weak-link simulator (`-ymThrottleKbps`, see AppModel). URLSession still downloads at full
    // speed; what arrives is released to the transfers in small slices at the requested rate,
    // shared between the active fetches like a real link's bandwidth. Nothing blocks `queue`.

    /// `until` is in `FetchEngine.now` time; 0 = no end.
    nonisolated(unsafe) static var debugThrottle: (bytesPerSecond: Double, until: TimeInterval)?

    private struct Slow {
        var pending = Data()
        var finished: (any Error)??
    }

    private var slow: [Int: Slow] = [:]

    private var throttling: Bool {
        guard let t = Self.debugThrottle else { return false }
        return t.until == 0 || Self.now < t.until
    }

    private func pump(_ id: Int) {
        guard var entry = slow[id] else { return }
        // Fetch dropped meanwhile: forget what it still had queued.
        guard routes[id] != nil else { slow[id] = nil; return }
        let rate = throttling ? Self.debugThrottle.map { $0.bytesPerSecond / Double(max(slow.count, 1)) } : nil
        let slice = rate == nil ? entry.pending : entry.pending.prefix(2048)
        entry.pending = Data(entry.pending.dropFirst(slice.count))
        slow[id] = entry
        if !slice.isEmpty { routes[id]?.client?.fetch(id, didReceive: Data(slice)) }
        guard routes[id] != nil else { slow[id] = nil; return }
        if entry.pending.isEmpty, let done = entry.finished {
            slow[id] = nil
            finish(id, error: done)
        } else if let rate {
            // Keep ticking while idle too, so bytes arriving later are paced as well.
            let wait = slice.isEmpty ? 0.1 : Double(slice.count) / rate
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.pump(id) }
        } else if entry.pending.isEmpty {
            // Throttle expired and nothing is held back: hand the fetch back to the fast path.
            slow[id] = nil
        } else {
            queue.async { [weak self] in self?.pump(id) }
        }
    }
    #endif

    // MARK: Throughput (call on `queue`)

    // Only time spent actually receiving is measured: the window opens when the first
    // response body starts and is thrown away when the last one ends, so an idle engine
    // (nothing left to fetch) never reports a misleadingly low speed.
    private var receiving = 0
    private var windowStart: TimeInterval = 0
    private var windowBytes = 0
    private var ticker: DispatchSourceTimer?
    private var lastRate: (bytesPerSecond: Double, at: TimeInterval)?

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Link speed measured within the last few seconds, if any.
    var recentRate: Double? {
        guard let r = lastRate, Self.now - r.at < 5 else { return nil }
        return r.bytesPerSecond
    }

    func receivingBegan() {
        receiving += 1
        guard receiving == 1 else { return }
        windowStart = Self.now
        windowBytes = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t
    }

    func receivingEnded() {
        receiving -= 1
        guard receiving <= 0 else { return }
        receiving = 0
        ticker?.cancel()
        ticker = nil
        // On a fast link a whole track arrives in under a second and the ticker never fires,
        // so the quality controller would never learn the link is good again (and never climb
        // back from a downgrade). Report the closing window when it is big enough to mean
        // something: with >= 256 KB a sub-second window can't read as a slow link.
        let elapsed = Self.now - windowStart
        if windowBytes >= 256 * 1024, elapsed >= 0.05 {
            let rate = Double(windowBytes) / elapsed
            lastRate = (rate, Self.now)
            onThroughput?(rate)
        }
        windowBytes = 0
    }

    func received(_ bytes: Int) {
        windowBytes += bytes
    }

    /// Measurements from the old network path say nothing about the new one.
    func linkChanged() {
        lastRate = nil
        windowStart = Self.now
        windowBytes = 0
    }

    private func tick() {
        let now = Self.now
        let elapsed = now - windowStart
        guard elapsed >= 0.5 else { return }
        let rate = Double(windowBytes) / elapsed
        windowStart = now
        windowBytes = 0
        // A silent second is a stall, which the idle timeout and the player report;
        // there is no speed to speak of.
        guard rate > 0 else { return }
        lastRate = (rate, now)
        onThroughput?(rate)
    }
}
