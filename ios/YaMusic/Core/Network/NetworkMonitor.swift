import Foundation
import Network
import Observation

/// Live reachability. Views and the player read it; nothing here ever blocks.
@Observable
final class NetworkMonitor {
    enum Link: String, Sendable { case none, wifi, cellular, wired, other }

    /// A usable route exists (says nothing about its speed).
    private(set) var isOnline = true
    private(set) var link: Link = .other
    /// Cellular or personal hotspot.
    private(set) var isExpensive = false
    /// Low Data Mode.
    private(set) var isConstrained = false
    /// Bumped on every path change, so observers can restart stalled work.
    private(set) var generation = 0

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let link: Link =
                !online ? .none
                : path.usesInterfaceType(.wifi) ? .wifi
                : path.usesInterfaceType(.cellular) ? .cellular
                : path.usesInterfaceType(.wiredEthernet) ? .wired
                : .other
            let expensive = path.isExpensive, constrained = path.isConstrained
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
                if self.link != link { self.link = link }
                if self.isExpensive != expensive { self.isExpensive = expensive }
                if self.isConstrained != constrained { self.isConstrained = constrained }
                self.generation += 1
            }
        }
        monitor.start(queue: DispatchQueue(label: "ym.network-monitor", qos: .utility))
    }

    deinit { monitor.cancel() }
}
