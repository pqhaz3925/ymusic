import Foundation

/// Which bytes of a file are on disk: sorted, non-overlapping, non-adjacent half-open runs.
///
/// A cache file is usually one run growing from zero; a seek ahead adds a second one.
nonisolated struct ByteRanges: Sendable, Equatable {
    private(set) var runs: [Range<Int64>] = []

    init() {}

    init(_ runs: [Range<Int64>]) {
        for r in runs { insert(r) }
    }

    /// Total bytes held.
    var count: Int64 { runs.reduce(0) { $0 + $1.upperBound - $1.lowerBound } }

    mutating func insert(_ r: Range<Int64>) {
        guard !r.isEmpty else { return }
        var lo = r.lowerBound, hi = r.upperBound
        // Everything touching [lo, hi] (adjacent counts) collapses into one run.
        let first = runs.firstIndex { $0.upperBound >= lo } ?? runs.count
        var last = first
        while last < runs.count, runs[last].lowerBound <= hi {
            lo = min(lo, runs[last].lowerBound)
            hi = max(hi, runs[last].upperBound)
            last += 1
        }
        runs.replaceSubrange(first..<last, with: [lo..<hi])
    }

    /// End of the run holding `offset`, or nil when that byte is missing.
    func runEnd(at offset: Int64) -> Int64? {
        runs.first { $0.contains(offset) }?.upperBound
    }

    /// First byte of `r` that is not held, or nil when all of it is.
    func firstMissing(in r: Range<Int64>) -> Int64? {
        guard !r.isEmpty else { return nil }
        let p = runEnd(at: r.lowerBound) ?? r.lowerBound
        return p < r.upperBound ? p : nil
    }

    /// Where the next run begins after the (missing) byte `offset`.
    func nextRunStart(after offset: Int64) -> Int64? {
        runs.first { $0.lowerBound > offset }?.lowerBound
    }

    func covers(_ r: Range<Int64>) -> Bool { firstMissing(in: r) == nil }

    /// Forget everything at or beyond `length` (the file turned out shorter than the map says).
    mutating func clip(to length: Int64) {
        runs = runs.compactMap { r in
            let hi = min(r.upperBound, length)
            return r.lowerBound < hi ? r.lowerBound..<hi : nil
        }
    }
}
