import AVFoundation
import Foundation

/// Feeds an `AVURLAsset` from a `Transfer`: the player reads the cache file while it is
/// still being downloaded.
///
/// The asset gets a URL with a scheme AVFoundation can't load itself, which makes it ask
/// this delegate for everything. `AVAssetResourceLoader` holds its delegate weakly, so
/// whoever owns the asset must keep the loader alive (`PlayableAsset.retainer`).
nonisolated final class StreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "ymstream"

    private let transfer: Transfer
    // Loading requests in flight (touched on the transfer's queue only).
    private var open: Set<ObjectIdentifier> = []
    private var readers: [ObjectIdentifier: Transfer.Reader] = [:]

    init(transfer: Transfer) {
        self.transfer = transfer
    }

    deinit {
        let transfer = self.transfer
        let left = Array(readers.values)
        guard !left.isEmpty else { return }
        transfer.engine.queue.async { left.forEach(transfer.removeReader) }
    }

    /// An asset that loads through `transfer`. `name` only has to make the URL unique-ish
    /// and carry a sensible extension; the real type comes with the content information.
    func makeAsset(name: String) -> AVURLAsset {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "audio"
        parts.path = "/" + name
        let asset = AVURLAsset(url: parts.url ?? URL(string: Self.scheme + "://audio/track")!)
        asset.resourceLoader.setDelegate(self, queue: transfer.engine.queue)
        return asset
    }

    // MARK: AVAssetResourceLoaderDelegate (on the transfer's queue)

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url?.scheme == Self.scheme else { return false }
        let id = ObjectIdentifier(request)
        open.insert(id)
        guard let info = request.contentInformationRequest else {
            serve(request)
            return true
        }
        transfer.requestInfo { [weak self] result in
            guard let self, self.open.contains(id) else { return }
            switch result {
            case .failure(let error):
                self.finish(request, error)
            case .success(let known):
                info.contentType = known.type
                info.contentLength = known.total
                info.isByteRangeAccessSupported = true
                self.serve(request)
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        let id = ObjectIdentifier(request)
        open.remove(id)
        if let reader = readers.removeValue(forKey: id) { transfer.removeReader(reader) }
    }

    private func serve(_ request: AVAssetResourceLoadingRequest) {
        guard let data = request.dataRequest else {
            finish(request, nil)
            return
        }
        // `currentOffset` is where the next byte goes; it starts at `requestedOffset`.
        let start = max(data.currentOffset, data.requestedOffset)
        let end = data.requestsAllDataToEndOfResource ? nil : data.requestedOffset + Int64(data.requestedLength)
        let id = ObjectIdentifier(request)
        readers[id] = transfer.addReader(
            from: start, to: end,
            onData: { data.respond(with: $0) },
            onFinish: { [weak self] error in self?.finish(request, error) })
    }

    private func finish(_ request: AVAssetResourceLoadingRequest, _ error: (any Error)?) {
        let id = ObjectIdentifier(request)
        guard open.remove(id) != nil else { return }
        readers[id] = nil
        if let error {
            // Only for transfers that died for good. Note that AVPlayer does not turn this
            // into a failed item mid-playback: it asks again a few times, then plays out
            // its buffer and stalls. `TrackStore.onStreamFailure` is how the player learns.
            request.finishLoading(with: error)
        } else {
            request.finishLoading()
        }
    }
}
