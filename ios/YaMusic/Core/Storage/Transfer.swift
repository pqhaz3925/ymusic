import Foundation

/// Where the bytes of a stream currently are.
nonisolated struct RemoteStream: Sendable {
    /// Signed and short-lived.
    var url: URL
    /// AES-128 key of an `encraw` stream; nil = not encrypted.
    var key: Data? = nil
}

nonisolated enum ResolveOutcome: Sendable {
    case resolved(RemoteStream)
    /// Connectivity problem: worth asking again.
    case unreachable
    /// The service now answers with a different file (other quality or codec).
    case changed
    /// The service said no; asking again won't help.
    case refused(any Error)
}

/// The ways a transfer ends for good. Network trouble is not among them: that is retried.
nonisolated enum TransferError: LocalizedError {
    /// The remote file is no longer the one the bytes on disk came from.
    case remoteChanged
    /// The transfer was shut down while requests were still waiting on it.
    case closed
    case disk(Int32)
    case badKey
    case refused(any Error)

    var errorDescription: String? {
        switch self {
        case .remoteChanged: "Файл на сервере изменился"
        case .closed: "Загрузка остановлена"
        case .disk(ENOSPC): "Недостаточно места на устройстве"
        case .disk: "Не удалось записать файл"
        case .badKey: "Не удалось расшифровать поток"
        case .refused(let error): error.localizedDescription
        }
    }
}

/// One audio file on its way from the network to the disk, readable while it arrives.
///
/// The partial file `<name>.part` is written sparsely: a sequential fill plus, after a seek
/// ahead, a second run further in. `<name>.map` remembers which bytes are valid so the next
/// launch continues instead of starting over. When every byte is there the file is renamed
/// to `<destination>/<name>.<ext>`.
///
/// At most two HTTP range requests run at a time, placed where they are needed most:
/// first wherever a reader (a player's loading request) is waiting, otherwise at the first
/// hole (background fill). A seek far ahead therefore moves the download to the new
/// position, and the skipped part is filled once the player has what it needs.
///
/// Network failures never end a transfer: it retries with backoff for as long as it is kept
/// open, re-resolving the signed URL when that looks like the problem.
///
/// Everything runs on `engine.queue`. The thread-safe entry points say so; the rest
/// (readers, info) is for callers already on that queue, i.e. `StreamLoader`.
nonisolated final class Transfer: FetchClient, @unchecked Sendable {
    nonisolated enum Event: Sendable {
        /// At most ~4 a second.
        case progress(have: Int64, total: Int64)
        /// The finished file, and the directory it was asked to go to.
        case completed(file: URL, directory: URL, total: Int64)
        /// Final. For `.remoteChanged` the partial file is already deleted.
        case failed(TransferError)
    }

    /// How much to fetch when no reader is asking.
    nonisolated enum Fill: Sendable, Equatable {
        case onDemand
        /// The first bytes only (prefetch on a metered link).
        case head(Int64)
        case everything
    }

    nonisolated struct Info {
        let total: Int64
        /// UTI.
        let type: String
    }

    /// A consumer of a byte range, fed in order as bytes become available.
    /// Confined to the engine's queue like the transfer itself.
    nonisolated final class Reader: @unchecked Sendable {
        fileprivate(set) var offset: Int64
        /// Exclusive; nil = up to the end of the file.
        fileprivate let end: Int64?
        fileprivate let onData: (Data) -> Void
        fileprivate let onFinish: ((any Error)?) -> Void
        fileprivate var done = false

        fileprivate init(offset: Int64, end: Int64?, onData: @escaping (Data) -> Void,
                         onFinish: @escaping ((any Error)?) -> Void) {
            self.offset = offset
            self.end = end
            self.onData = onData
            self.onFinish = onFinish
        }
    }

    private nonisolated final class Worker {
        let id: Int
        let start: Int64
        /// Exclusive end of the requested range; nil = open-ended.
        let stop: Int64?
        var position: Int64
        var cipher: StreamCipher?
        /// Bytes to throw away first (the server ignored `Range` and sent the whole file).
        var skip: Int64 = 0
        var receiving = false
        /// The server honoured `Range` (206), so the body ends where the request said.
        var ranged = false
        var received: Int64 = 0
        let started = FetchEngine.now
        var lastActivity = FetchEngine.now

        init(id: Int, start: Int64, stop: Int64?, cipher: StreamCipher?) {
            self.id = id
            self.start = start
            self.stop = stop
            self.position = start
            self.cipher = cipher
        }
    }

    private nonisolated struct Map: Codable {
        var total: Int64
        var runs: [[Int64]]
    }

    private enum Phase {
        case idle, running, complete, failed(TransferError), closed
    }

    private static let maxWorkers = 2
    private static let chunk: Int64 = 256 << 10

    let engine: FetchEngine
    private var queue: DispatchQueue { engine.queue }
    private let name: String
    private let partURL: URL
    private let mapURL: URL
    private var destination: URL
    private let codec: String
    private let resolver: @Sendable () async -> ResolveOutcome
    private let onEvent: @Sendable (Transfer, Event) -> Void

    private var phase = Phase.idle
    private var fd: Int32 = -1
    private var total: Int64?
    private var have = ByteRanges()
    private var type: String?
    private var headChecked = false
    private var remote: RemoteStream?
    /// The location given up on after repeated failures; used again if no new one can be had.
    private var previous: RemoteStream?
    private var resolving = false
    private var fill = Fill.onDemand
    private var workers: [Worker] = []
    private var readers: [Reader] = []
    private var infoWaiters: [(Result<Info, any Error>) -> Void] = []
    /// Something of this file reached a consumer, so it can't be silently swapped for another.
    private var delivered = false
    /// Failed attempts since bytes last arrived.
    private var failures = 0
    private var retryPending = false
    private var retryToken = 0
    private var pumpQueued = false
    private var lastProgress: TimeInterval = 0
    private var reportQueued = false
    private var lastSaved: TimeInterval = 0

    /// - Parameters:
    ///   - name: file name without extension, unique per track and quality.
    ///   - workDirectory: where the partial file lives.
    ///   - destination: where the finished file goes (see `setDestination`).
    ///   - codec: the API's codec name, a fallback when the bytes can't be identified.
    ///   - remote: a freshly resolved location, if the caller has one; else `resolver` is asked.
    ///   - onEvent: called on `engine.queue`.
    init(engine: FetchEngine, name: String, workDirectory: URL, destination: URL, codec: String,
         remote: RemoteStream?, resolver: @escaping @Sendable () async -> ResolveOutcome,
         onEvent: @escaping @Sendable (Transfer, Event) -> Void) {
        self.engine = engine
        self.name = name
        self.partURL = workDirectory.appendingPathComponent(name + ".part")
        self.mapURL = workDirectory.appendingPathComponent(name + ".map")
        self.destination = destination
        self.codec = codec
        self.remote = remote
        self.resolver = resolver
        self.onEvent = onEvent
    }

    deinit {
        // Normally `stop()` came first and there is nothing left; this is the safety net.
        if fd >= 0 { Darwin.close(fd) }
        guard !workers.isEmpty else { return }
        let engine = self.engine
        let left = workers.map { ($0.id, $0.receiving) }
        engine.queue.async {
            for (id, receiving) in left {
                engine.drop(id)
                if receiving { engine.receivingEnded() }
            }
        }
    }

    /// The files a transfer named `name` may have left in `directory`.
    static func leftovers(name: String, in directory: URL) -> [URL] {
        [directory.appendingPathComponent(name + ".part"), directory.appendingPathComponent(name + ".map")]
    }

    /// Bytes of `name` already in `directory`, per its map (0 when there is nothing usable).
    static func bytesOnDisk(name: String, in directory: URL) -> Int64 {
        let urls = leftovers(name: name, in: directory)
        guard FileManager.default.fileExists(atPath: urls[0].path),
              let data = try? Data(contentsOf: urls[1]),
              let map = try? JSONDecoder().decode(Map.self, from: data) else { return 0 }
        return ByteRanges(map.runs.compactMap { $0.count == 2 && $0[0] < $0[1] ? $0[0]..<$0[1] : nil }).count
    }

    // MARK: Control (thread-safe)

    func start() {
        queue.async { self.begin() }
    }

    func setFill(_ fill: Fill) {
        queue.async {
            guard self.fill != fill else { return }
            self.fill = fill
            self.reschedule()
        }
    }

    /// Directory the finished file is moved to. Takes effect if the file isn't finished yet.
    func setDestination(_ directory: URL) {
        queue.async { self.destination = directory }
    }

    /// The network path changed: retry now instead of waiting out the backoff, and restart
    /// requests that went quiet (their connection likely belonged to the old path).
    func networkChanged() {
        queue.async {
            guard case .running = self.phase else { return }
            self.retryPending = false
            self.retryToken += 1
            // Don't wait for a resolve that may be hanging on the old path.
            if self.remote == nil { self.remote = self.previous }
            let changed = FetchEngine.now
            self.restartQuietWorkers(olderThan: changed)
            // A request that got its last bytes just before the switch only shows as
            // quiet a moment later; without this it would sit out the full idle timeout.
            self.queue.asyncAfter(deadline: .now() + 1.5) {
                self.restartQuietWorkers(olderThan: changed)
            }
        }
    }

    /// Restart requests begun before `time` (on the old path) that have gone silent.
    private func restartQuietWorkers(olderThan time: TimeInterval) {
        guard case .running = phase else { return }
        let now = FetchEngine.now
        for w in workers where w.started <= time && now - w.lastActivity > 1 { retire(w) }
        reschedule()
    }

    /// Stop fetching and release the file, remembering what was fetched.
    func stop() {
        queue.async { self.shutdown() }
    }

    // MARK: Consumers (on `engine.queue`)

    /// Size and type of the file, as soon as they are known.
    func requestInfo(_ handler: @escaping (Result<Info, any Error>) -> Void) {
        switch phase {
        case .failed(let error): handler(.failure(error))
        case .closed: handler(.failure(TransferError.closed))
        case .idle, .running, .complete:
            infoWaiters.append(handler)
            answerInfo()
            reschedule()
        }
    }

    /// Deliver `[offset, end)` (`end` nil = to the end of the file) to `onData` in order,
    /// then call `onFinish(nil)`; or `onFinish(error)` if the transfer dies first.
    func addReader(from offset: Int64, to end: Int64?, onData: @escaping (Data) -> Void,
                   onFinish: @escaping ((any Error)?) -> Void) -> Reader {
        let reader = Reader(offset: max(0, offset), end: end, onData: onData, onFinish: onFinish)
        // Nothing is delivered from inside this call: the caller hasn't stored the reader yet.
        switch phase {
        case .failed(let error): queue.async { self.finish(reader, error) }
        case .closed: queue.async { self.finish(reader, TransferError.closed) }
        case .idle, .running, .complete:
            readers.append(reader)
            schedulePump()
            reschedule()
        }
        return reader
    }

    func removeReader(_ reader: Reader) {
        guard !reader.done else { return }
        reader.done = true
        readers.removeAll { $0 === reader }
        // A player usually cancels a request only to issue the next one. Give that a moment
        // to arrive before deciding the fetch that fed this reader is in the wrong place.
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reschedule() }
    }

    // MARK: Lifecycle

    private func begin() {
        guard case .idle = phase else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Continue a previous run only as far as both the map and the file agree.
        if let data = try? Data(contentsOf: mapURL), let map = try? JSONDecoder().decode(Map.self, from: data),
           map.total > 0, let size = (try? fm.attributesOfItem(atPath: partURL.path))?[.size] as? NSNumber {
            var runs = ByteRanges(map.runs.compactMap { $0.count == 2 && $0[0] < $0[1] ? $0[0]..<$0[1] : nil })
            runs.clip(to: min(size.int64Value, map.total))
            if runs.count > 0 {
                have = runs
                total = map.total
            }
        }
        if have.count == 0 {
            try? fm.removeItem(at: partURL)
            try? fm.removeItem(at: mapURL)
        }
        fd = Darwin.open(partURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            die(.disk(errno))
            return
        }
        phase = .running
        identify()
        if let total {
            report(total, force: true)
            if have.covers(0..<total) {
                finalize()
                return
            }
        }
        answerInfo()
        schedulePump()
        reschedule()
    }

    private func shutdown() {
        switch phase {
        case .closed, .failed: return
        case .idle, .running, .complete: break
        }
        if case .running = phase { saveMap() }
        phase = .closed
        teardown(TransferError.closed)
    }

    /// End for good and tell everyone.
    private func die(_ error: TransferError) {
        switch phase {
        case .closed, .failed: return
        case .idle, .running, .complete: break
        }
        if case .remoteChanged = error {
            try? FileManager.default.removeItem(at: partURL)
            try? FileManager.default.removeItem(at: mapURL)
        } else if case .running = phase {
            saveMap()
        }
        phase = .failed(error)
        teardown(error)
        onEvent(self, .failed(error))
    }

    private func teardown(_ error: any Error) {
        retryToken += 1
        for w in workers { retire(w) }
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        let waiting = readers
        readers = []
        for r in waiting { finish(r, error) }
        let asked = infoWaiters
        infoWaiters = []
        for handler in asked { handler(.failure(error)) }
    }

    private func finalize() {
        guard case .running = phase, let total else { return }
        for w in workers { retire(w, natural: w.position >= (w.stop ?? total)) }
        identify()
        let type = self.type ?? fallbackType
        let directory = destination
        let file = directory.appendingPathComponent(name + "." + AudioContainer.fileExtension(for: type))
        let fm = FileManager.default
        fsync(fd)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fm.removeItem(at: file)
            // A rename within the volume is atomic; the open descriptor keeps serving readers.
            try fm.moveItem(at: partURL, to: file)
        } catch {
            die(.disk((error as NSError).domain == NSPOSIXErrorDomain ? Int32((error as NSError).code) : EIO))
            return
        }
        try? fm.removeItem(at: mapURL)
        phase = .complete
        onEvent(self, .completed(file: file, directory: directory, total: total))
        answerInfo()
        pump()
    }

    // MARK: Scheduling

    /// How far ahead of a request's position a running fetch may be and still count as
    /// "about to get there" (about 1.5 s of download) rather than needing a fetch of its own.
    private var reach: Int64 {
        max(96 << 10, Int64((engine.recentRate ?? 0) * 1.5))
    }

    /// `lo` is missing; true when nothing between `lo` and `hi` is on disk either.
    private func sameHole(_ lo: Int64, _ hi: Int64) -> Bool {
        (have.nextRunStart(after: lo) ?? .max) > hi
    }

    /// Bring the running fetches in line with what is wanted right now. Idempotent; called
    /// after every change (readers, bytes, failures, settings).
    private func reschedule() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard case .running = phase else { return }
        let end = total ?? .max
        let reach = self.reach

        // Where bytes are wanted, most urgent first.
        var targets: [Int64] = []
        func want(_ t: Int64) {
            for i in targets.indices {
                let lo = min(targets[i], t), hi = max(targets[i], t)
                if hi - lo <= reach, sameHole(lo, hi) {
                    targets[i] = lo
                    return
                }
            }
            targets.append(t)
        }
        if !infoWaiters.isEmpty,
           let t = have.firstMissing(in: 0..<min(Int64(AudioContainer.headLength), end)) { want(t) }
        // The newest request is the one the player is actually waiting on.
        for r in readers.reversed() {
            let from = min(r.offset, end)
            if let t = have.firstMissing(in: from..<max(from, min(r.end ?? end, end))) { want(t) }
        }
        var bound: Int64?
        if targets.isEmpty {
            // Nobody is waiting: fill holes from the start, as far as allowed.
            let fillEnd: Int64
            switch fill {
            case .onDemand: fillEnd = 0
            case .head(let n):
                fillEnd = min(n, end)
                bound = n
            case .everything: fillEnd = end
            }
            if fill == .everything, let w = workers.first {
                // Any hole has to be filled eventually; a fetch that is already inside one
                // (left there by a seek) is better kept than moved back to the first.
                targets = [w.position]
            } else if let t = have.firstMissing(in: 0..<fillEnd) {
                targets = [t]
            }
        }

        // Keep fetches that are at (or just before) a target; the rest are in the wrong place.
        var kept: [Worker] = []
        var starts: [Int64] = []
        for t in targets.prefix(Self.maxWorkers) {
            let match = workers.first { w in
                !kept.contains { $0 === w } && w.position <= t && t - w.position <= reach
                    && t < (w.stop ?? .max) && sameHole(w.position, t)
            }
            if let match { kept.append(match) } else { starts.append(t) }
        }
        for w in workers where !kept.contains(where: { $0 === w }) { retire(w) }

        guard !starts.isEmpty, !retryPending else { return }
        guard remote != nil else {
            resolve()
            return
        }
        for t in starts {
            guard case .running = phase else { return }
            startWorker(at: t, bound: bound)
        }
    }

    private func startWorker(at offset: Int64, bound: Int64?) {
        guard let remote else { return }
        // Ask for exactly the hole: up to the next bytes already on disk.
        var stop = have.nextRunStart(after: offset) ?? total
        if let bound, bound > offset { stop = min(stop ?? bound, bound) }
        var cipher: StreamCipher?
        if let key = remote.key {
            guard let c = StreamCipher(key: key, offset: offset) else {
                die(.badKey)
                return
            }
            cipher = c
        }
        var request = URLRequest(url: remote.url)
        request.setValue(stop.map { "bytes=\(offset)-\($0 - 1)" } ?? "bytes=\(offset)-", forHTTPHeaderField: "Range")
        // Offsets must be offsets into the file itself, not into a compressed encoding of it.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let id = engine.start(request, urgent: !readers.isEmpty || !infoWaiters.isEmpty, for: self)
        workers.append(Worker(id: id, start: offset, stop: stop, cipher: cipher))
    }

    /// Stop a fetch and forget it. `natural`: it has received everything it asked for.
    private func retire(_ worker: Worker, natural: Bool = false) {
        guard let i = workers.firstIndex(where: { $0 === worker }) else { return }
        workers.remove(at: i)
        engine.drop(worker.id, abort: !natural)
        if worker.receiving { engine.receivingEnded() }
    }

    // MARK: Failures

    private func resolve() {
        guard !resolving else { return }
        resolving = true
        let resolver = self.resolver
        Task { [weak self] in
            let outcome = await resolver()
            guard let self else { return }
            self.queue.async { self.resolved(outcome) }
        }
    }

    private func resolved(_ outcome: ResolveOutcome) {
        resolving = false
        guard case .running = phase else { return }
        switch outcome {
        case .resolved(let stream):
            remote = stream
            previous = nil
            reschedule()
        case .unreachable:
            if let previous {
                // The API can't be reached either, which says the link is down, not that
                // the URL is bad: keep trying the old one (it already waited its backoff).
                remote = previous
                reschedule()
            } else {
                failures += 1
                backOff()
            }
        case .changed:
            die(.remoteChanged)
        case .refused(let error):
            die(.refused(error))
        }
    }

    /// A request failed in a way that may pass (transport error, 5xx, short body).
    private func transientFailure() {
        failures += 1
        // Twice in a row with nothing received: the signed URL itself may be the problem.
        if failures % 2 == 0, remote != nil {
            previous = remote
            remote = nil
        }
        backOff()
    }

    /// The server rejected the URL (expired signature, moved file): sign a new one.
    private func urlRejected() {
        remote = nil
        previous = nil
        failures += 1
        // Straight away the first time; if fresh URLs keep being rejected, slow down.
        if failures > 1 { backOff() }
    }

    /// 0.5 s, 1, 2, 4, then every 8 s for as long as someone holds the transfer open.
    private func backOff() {
        let delay = min(8, 0.5 * pow(2, Double(min(failures, 6) - 1)))
        retryPending = true
        retryToken += 1
        let token = retryToken
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.retryToken == token else { return }
            self.retryPending = false
            self.reschedule()
        }
    }

    /// The server's idea of the file length. False when that ended this response.
    private func adopt(total new: Int64) -> Bool {
        guard let known = total else {
            total = new
            report(new, force: true)
            return true
        }
        guard known != new else { return true }
        // A different file than the bytes on disk came from. If a player already has some
        // of the old one, the two can't be mixed: fail and let it start over. Otherwise
        // (a stale partial from an earlier launch) just begin again quietly.
        guard !delivered else {
            die(.remoteChanged)
            return false
        }
        for w in workers { retire(w) }
        have = ByteRanges()
        type = nil
        headChecked = false
        total = new
        ftruncate(fd, 0)
        try? FileManager.default.removeItem(at: mapURL)
        report(new, force: true)
        reschedule()
        return false
    }

    // MARK: FetchClient

    func fetch(_ id: Int, didReceive response: HTTPURLResponse) -> Bool {
        guard let w = workers.first(where: { $0.id == id }) else { return false }
        w.lastActivity = FetchEngine.now
        switch response.statusCode {
        case 206:
            guard let range = Self.contentRange(response), range.start == w.start else {
                retire(w)
                transientFailure()
                reschedule()
                return false
            }
            guard adopt(total: range.total) else { return false }
            w.ranged = true
        case 200:
            // `Range` was ignored: this is the whole file from byte zero.
            let length = response.expectedContentLength
            guard length > 0 else {
                retire(w)
                transientFailure()
                reschedule()
                return false
            }
            guard adopt(total: length) else { return false }
            if w.start > 0 {
                w.skip = w.start
                if let key = remote?.key { w.cipher = StreamCipher(key: key) }
            }
        case 401, 403, 404, 410:
            retire(w)
            urlRejected()
            reschedule()
            return false
        case 416:
            // The file is shorter than the bytes we were promised.
            retire(w)
            die(.remoteChanged)
            return false
        default:
            retire(w)
            transientFailure()
            reschedule()
            return false
        }
        w.receiving = true
        engine.receivingBegan()
        return true
    }

    func fetch(_ id: Int, didReceive data: Data) {
        guard case .running = phase, let w = workers.first(where: { $0.id == id }), let total else { return }
        let now = FetchEngine.now
        w.lastActivity = now
        engine.received(data.count)
        var bytes = w.cipher?.process(data) ?? data
        if w.skip > 0 {
            let dropped = min(w.skip, Int64(bytes.count))
            w.skip -= dropped
            bytes = bytes.dropFirst(Int(dropped))
        }
        // Never trust the server past the end of the file.
        if w.position + Int64(bytes.count) > total { bytes = bytes.prefix(Int(max(0, total - w.position))) }
        guard !bytes.isEmpty else { return }
        guard write(bytes, at: w.position) else {
            die(.disk(errno))
            return
        }
        let end = w.position + Int64(bytes.count)
        have.insert(w.position..<end)
        w.position = end
        w.received += Int64(bytes.count)
        // Bytes are flowing: whatever failed before is over.
        failures = 0
        if retryPending {
            retryPending = false
            retryToken += 1
        }
        identify()
        report(total)
        if have.covers(0..<total) {
            finalize()
            return
        }
        if now - lastSaved > 3 { saveMap() }
        if w.position >= (w.stop ?? total) {
            // Got what it was started for. If the server ignored the range, more is still
            // coming that nobody asked for: cut that off.
            retire(w, natural: w.skip == 0 && (w.ranged || w.position >= total))
        } else if have.runEnd(at: w.position) != nil {
            // Ran into bytes another fetch already brought.
            retire(w)
        }
        answerInfo()
        pump()
        reschedule()
    }

    func fetch(_ id: Int, didCompleteWith error: (any Error)?) {
        guard let w = workers.first(where: { $0.id == id }) else { return }
        retire(w, natural: true)
        guard case .running = phase else { return }
        // An early clean close after some bytes is just a reason to ask for the rest;
        // anything else counts as a failure and waits a little.
        if error != nil || w.received == 0 { transientFailure() }
        reschedule()
    }

    private static func contentRange(_ response: HTTPURLResponse) -> (start: Int64, total: Int64)? {
        // "bytes 100-199/5000"
        guard let value = response.value(forHTTPHeaderField: "Content-Range") else { return nil }
        let parts = value.split(whereSeparator: { " -/".contains($0) })
        guard parts.count == 4, parts[0].lowercased() == "bytes",
              let start = Int64(parts[1]), let total = Int64(parts[3]), total > 0 else { return nil }
        return (start, total)
    }

    // MARK: Delivery

    private func schedulePump() {
        guard !pumpQueued else { return }
        pumpQueued = true
        queue.async {
            self.pumpQueued = false
            self.pump()
        }
    }

    /// Hand every reader the bytes that are on disk at its position.
    private func pump() {
        guard fd >= 0, let total else { return }
        // A bounded amount per turn, so one reader of a big finished file can't hold up
        // the queue (incoming data, cancellations) while megabytes are copied.
        var budget: Int64 = 2 << 20
        var more = false
        for r in readers where !r.done {
            let end = min(r.end ?? total, total)
            while budget > 0, r.offset < end, let runEnd = have.runEnd(at: r.offset) {
                let n = min(min(runEnd, end) - r.offset, Self.chunk, budget)
                guard let data = read(r.offset..<r.offset + n) else {
                    finish(r, TransferError.disk(errno))
                    break
                }
                r.offset += n
                budget -= n
                delivered = true
                r.onData(data)
                if r.done { break }
            }
            guard !r.done else { continue }
            if r.offset >= end {
                finish(r, nil)
            } else if budget <= 0 {
                more = true
            }
        }
        readers.removeAll { $0.done }
        if more { schedulePump() }
    }

    private func finish(_ reader: Reader, _ error: (any Error)?) {
        guard !reader.done else { return }
        reader.done = true
        reader.onFinish(error)
    }

    private func answerInfo() {
        guard !infoWaiters.isEmpty, let total else { return }
        identify()
        // Without the first bytes the type is a guess; wait for them (they are being fetched).
        guard headChecked else { return }
        let type = self.type ?? fallbackType
        let asked = infoWaiters
        infoWaiters = []
        delivered = true
        for handler in asked { handler(.success(Info(total: total, type: type))) }
    }

    private var fallbackType: String { AudioContainer.type(forCodec: codec) ?? AudioContainer.m4a }

    /// Look at the first bytes, once they are there, to learn what kind of file this is.
    private func identify() {
        guard !headChecked, fd >= 0, let total else { return }
        let n = min(Int64(AudioContainer.headLength), total)
        guard have.covers(0..<n), let head = read(0..<n) else { return }
        headChecked = true
        type = AudioContainer.type(ofHead: head)
    }

    /// Progress for the owner, at most every 250 ms. A report that comes too soon is sent
    /// when its turn comes, so the last value always gets out (a short fetch may be over
    /// within one interval).
    private func report(_ total: Int64, force: Bool = false) {
        let now = FetchEngine.now
        let wait = 0.25 - (now - lastProgress)
        guard force || wait <= 0 else {
            guard !reportQueued else { return }
            reportQueued = true
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, self.reportQueued else { return }
                if case .running = self.phase, let total = self.total { self.report(total, force: true) }
                self.reportQueued = false
            }
            return
        }
        reportQueued = false
        lastProgress = now
        onEvent(self, .progress(have: have.count, total: total))
    }

    // MARK: File

    private func write(_ data: Data, at offset: Int64) -> Bool {
        data.withUnsafeBytes { buffer in
            var done = 0
            while done < buffer.count {
                let n = pwrite(fd, buffer.baseAddress! + done, buffer.count - done, off_t(offset) + off_t(done))
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                done += n
            }
            return true
        }
    }

    private func read(_ range: Range<Int64>) -> Data? {
        var data = Data(count: Int(range.upperBound - range.lowerBound))
        let ok = data.withUnsafeMutableBytes { buffer in
            var done = 0
            while done < buffer.count {
                let n = pread(fd, buffer.baseAddress! + done, buffer.count - done, off_t(range.lowerBound) + off_t(done))
                if n < 0, errno == EINTR { continue }
                if n <= 0 { return false }
                done += n
            }
            return true
        }
        return ok ? data : nil
    }

    /// Record which bytes are valid. Data first, then the claim about it, so a crash in
    /// between leaves a map that says less than the file holds, never more.
    private func saveMap() {
        guard fd >= 0, let total, have.count > 0 else { return }
        lastSaved = FetchEngine.now
        fsync(fd)
        let map = Map(total: total, runs: have.runs.map { [$0.lowerBound, $0.upperBound] })
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: mapURL, options: .atomic) }
    }
}
