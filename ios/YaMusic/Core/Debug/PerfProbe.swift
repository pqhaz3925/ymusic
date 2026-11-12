#if DEBUG
import Foundation

/// Dev-only CPU meter. Launch with `-perfProbe YES` and read the console:
/// `PERF cpu=3.1% thermal=nominal` every 2 s (process CPU across all threads, 100% = one core).
nonisolated enum PerfProbe {
    /// Extra text for each line (player state), evaluated on the main actor.
    nonisolated(unsafe) static var status: (@MainActor () -> String)?

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "perfProbe") else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ym.perf", qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        var last = cpuSeconds(), lastWall = DispatchTime.now().uptimeNanoseconds
        timer.setEventHandler {
            let now = cpuSeconds(), wall = DispatchTime.now().uptimeNanoseconds
            let pct = (now - last) / (Double(wall - lastWall) / 1e9) * 100
            last = now; lastWall = wall
            let thermal = ["nominal", "fair", "serious", "critical"][min(ProcessInfo.processInfo.thermalState.rawValue, 3)]
            let line = String(format: "PERF cpu=%.1f%% thermal=%@", pct, thermal)
            let status = Self.status
            DispatchQueue.main.async {
                print(line + (status.map { " " + $0() } ?? ""))
                fflush(stdout)
            }
        }
        timer.resume()
        keep = timer
    }

    nonisolated(unsafe) private static var keep: (any DispatchSourceTimer)?

    /// Total user+system CPU time consumed by the process so far.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
             + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }
}
#endif
