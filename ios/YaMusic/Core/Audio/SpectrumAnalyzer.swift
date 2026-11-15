import Accelerate
import CoreAudio
import Foundation
import Synchronization

/// FFT analyser behind the wave backdrop. One instance per audio tap.
///
/// Every quarter window (~11 ms) of audio: Hann window -> real FFT -> 4 log-spaced bands against
/// their running peaks, loudness against the track's recent ceiling, and two onset detectors
/// (low end = kick, high end = snare / hat). Each result goes into the `SpectrumSource`
/// timeline stamped with its media time; the renderer picks it up when the playhead gets there
/// (the tap runs ahead of what is heard).
///
/// `process` runs on the tap's real-time thread: no allocation, no locks of its own (the only
/// lock taken is the timeline's), and nothing at all unless a visualiser is watching.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    /// Largest window (sample rates above 100 kHz); 2048 at 44.1 / 48 kHz. That is ~45 ms:
    /// anything shorter doesn't hold a whole period of a sub-bass note, and its energy then
    /// wobbles from one analysis to the next as if it were a drum roll.
    private static let maxLog2n = 13
    private static let maxN = 1 << maxLog2n
    /// Band edges in Hz: bass, low-mid, high-mid, treble.
    private static let bandLow = SIMD4<Float>(30, 200, 800, 3000)
    private static let bandHigh = SIMD4<Float>(200, 800, 3000, 12000)
    /// Where a kick and a snare / hat show up.
    private static let kickRange: (Float, Float) = (35, 160)
    private static let snapRange: (Float, Float) = (2500, 10000)
    private static let loudRange: (Float, Float) = (30, 10000)
    /// Loudness below this (full scale = 1 here would be ~0.5) is "quiet" whatever the track did so far.
    private static let loudFloor: Float = 0.02
    /// A hit registers once it is a good way into the window, so a result is this late
    /// against the audio it reports. Subtracted from the stamp.
    private static let latency = 0.018

    private static let layoutFloat32: UInt64 = 1
    private static let layoutInt16: UInt64 = 2

    private let source: SpectrumSource
    private let setup: FFTSetup
    /// Hann windows for 2048, 4096 and 8192 samples, one after another.
    private let windows = UnsafeMutablePointer<Float>.allocate(capacity: 2048 + 4096 + 8192)
    /// The newest `n` mono samples, oldest first.
    private let history = UnsafeMutablePointer<Float>.allocate(capacity: maxN)
    private let frame = UnsafeMutablePointer<Float>.allocate(capacity: maxN)
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: maxN)
    private let re = UnsafeMutablePointer<Float>.allocate(capacity: maxN / 2)
    private let im = UnsafeMutablePointer<Float>.allocate(capacity: maxN / 2)
    private let mags = UnsafeMutablePointer<Float>.allocate(capacity: maxN / 2)

    /// Source format, packed so the audio thread reads it without a lock:
    /// bits 0-1 layout (0 = unsupported), bit 2 interleaved, bits 8-15 channels, bits 32-63 sample rate.
    private let format = Atomic<UInt64>(0)

    // Audio-thread state.
    private var n = 0
    private var pending = 0
    /// Windows analysed since the last restart: the first ones still hold silence.
    private var warmup = 0
    private var lastEnd = -Double.infinity
    private var peak = SIMD4<Float>(repeating: 0.03)
    private var loudPeak: Float = SpectrumAnalyzer.loudFloor
    private var low = Onset(threshold: 1.2, range: 3.0)
    private var high = Onset(threshold: 1.0, range: 2.6)

    init(source: SpectrumSource) {
        self.source = source
        setup = vDSP_create_fftsetup(vDSP_Length(Self.maxLog2n), FFTRadix(kFFTRadix2))!
        var at = 0
        for size in [2048, 4096, 8192] {
            vDSP_hann_window(windows + at, vDSP_Length(size), Int32(vDSP_HANN_NORM))
            at += size
        }
        history.initialize(repeating: 0, count: Self.maxN)
        frame.initialize(repeating: 0, count: Self.maxN)
        scratch.initialize(repeating: 0, count: Self.maxN)
        re.initialize(repeating: 0, count: Self.maxN / 2)
        im.initialize(repeating: 0, count: Self.maxN / 2)
        mags.initialize(repeating: 0, count: Self.maxN / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        windows.deallocate(); history.deallocate(); frame.deallocate(); scratch.deallocate()
        re.deallocate(); im.deallocate(); mags.deallocate()
    }

    /// The tap is about to deliver audio in `asbd`. Anything but native-endian packed
    /// Float32 / Int16 PCM is left unsupported, which makes `process` a no-op.
    func configure(_ asbd: AudioStreamBasicDescription) {
        let flags = asbd.mFormatFlags
        let channels = Int(asbd.mChannelsPerFrame)
        let interleaved = flags & kAudioFormatFlagIsNonInterleaved == 0
        let samplesPerFrame = interleaved ? channels : 1
        var layout: UInt64 = 0
        if asbd.mFormatID == kAudioFormatLinearPCM, flags & kAudioFormatFlagIsBigEndian == 0,
           (1...255).contains(channels), asbd.mSampleRate >= 8000, asbd.mSampleRate <= 768_000 {
            let isFloat = flags & kAudioFormatFlagIsFloat != 0
            if isFloat, asbd.mBitsPerChannel == 32, Int(asbd.mBytesPerFrame) == 4 * samplesPerFrame {
                layout = Self.layoutFloat32
            } else if !isFloat, flags & kAudioFormatFlagIsSignedInteger != 0,
                      asbd.mBitsPerChannel == 16, Int(asbd.mBytesPerFrame) == 2 * samplesPerFrame {
                layout = Self.layoutInt16
            }
        }
        guard layout != 0 else { format.store(0, ordering: .relaxed); return }
        let packed = layout | (interleaved ? 4 : 0) | UInt64(channels) << 8
            | UInt64(asbd.mSampleRate.rounded()) << 32
        format.store(packed, ordering: .relaxed)
    }

    /// The tap stopped delivering audio.
    func reset() { format.store(0, ordering: .relaxed) }

    /// Audio thread. Looks at `frames` frames in `list`; never writes to them.
    /// `mediaStart` / `mediaDuration`: where these frames sit in the item, in seconds (NaN if unknown).
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int,
                 mediaStart: Double, mediaDuration: Double) {
        // Nobody is drawing: this is the whole cost of the tap.
        guard frames > 0, source.isWatched else { lastEnd = -.infinity; return }
        let packed = format.load(ordering: .relaxed)
        let layout = packed & 3
        guard layout != 0 else { return }
        let interleaved = packed & 4 != 0
        let channels = Int((packed >> 8) & 0xFF)
        let sampleRate = Float(packed >> 32)
        let width = layout == Self.layoutFloat32 ? 4 : 2
        let size = sampleRate <= 50_000 ? 2048 : sampleRate <= 100_000 ? 4096 : 8192

        // A jump in media time (seek, restart, first buffer) or another format: start over.
        let timed = mediaStart.isFinite && mediaDuration.isFinite
        let continuous = timed ? abs(mediaStart - lastEnd) < 0.1 : lastEnd.isNaN
        if !continuous || size != n { restart(size: size) }
        lastEnd = timed ? mediaStart + mediaDuration : .nan

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count >= 1, let first = buffers[0].mData else { return }
        let stride = interleaved ? channels : 1
        guard Int(buffers[0].mDataByteSize) >= frames * stride * width else { return }
        let left = UnsafeRawPointer(first)
        var right: UnsafeRawPointer?
        if interleaved {
            if channels >= 2 { right = left + width }
        } else if buffers.count >= 2, let second = buffers[1].mData,
                  Int(buffers[1].mDataByteSize) >= frames * width {
            right = UnsafeRawPointer(second)
        }

        // One analysis per quarter window, wherever the tap's buffer boundaries fall.
        let hop = n / 4
        let hopSeconds = Float(hop) / sampleRate
        var offset = 0
        while offset < frames {
            let piece = min(frames - offset, hop - pending)
            let at = offset * stride * width
            ingest(left + at, right.map { $0 + at }, count: piece, stride: stride, float32: layout == Self.layoutFloat32)
            offset += piece
            pending += piece
            guard pending == hop else { break }
            pending = 0
            let result = analyze(sampleRate: sampleRate, dt: hopSeconds)
            let time = timed ? mediaStart + Double(offset) / Double(sampleRate) : (source.clock.now ?? .nan)
            if time.isFinite { source.append(result, at: time - Self.latency) }
        }
    }

    private func restart(size: Int) {
        n = size
        pending = 0
        warmup = 0
        history.update(repeating: 0, count: Self.maxN)
        low.reset()
        high.reset()
        source.discard()
    }

    /// Slide the history by `count` and mix the new frames down to mono at its end.
    private func ingest(_ left: UnsafeRawPointer, _ right: UnsafeRawPointer?, count: Int, stride: Int, float32: Bool) {
        history.update(from: history + count, count: n - count)
        let dst = history + (n - count)
        let length = vDSP_Length(count)
        var gain: Float = right == nil ? 1 : 0.5
        if float32 {
            let l = left.assumingMemoryBound(to: Float.self)
            if let r = right?.assumingMemoryBound(to: Float.self) {
                vDSP_vadd(l, stride, r, stride, dst, 1, length)
                vDSP_vsmul(dst, 1, &gain, dst, 1, length)
            } else {
                vDSP_vsmul(l, stride, &gain, dst, 1, length)
            }
        } else {
            vDSP_vflt16(left.assumingMemoryBound(to: Int16.self), stride, dst, 1, length)
            if let r = right?.assumingMemoryBound(to: Int16.self) {
                vDSP_vflt16(r, stride, scratch, 1, length)
                vDSP_vadd(dst, 1, scratch, 1, dst, 1, length)
            }
            gain /= 32768
            vDSP_vsmul(dst, 1, &gain, dst, 1, length)
        }
    }

    private func analyze(sampleRate: Float, dt: Float) -> SpectrumFrame {
        let half = n / 2
        let window = windows + (n == 2048 ? 0 : n == 4096 ? 2048 : 6144)
        vDSP_vmul(history, 1, window, 1, frame, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: re, imagp: im)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, vDSP_Length(n.trailingZeroBitCount), FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, mags, 1, vDSP_Length(half))
        var scale = 1 / Float(n)
        vDSP_vsmul(mags, 1, &scale, mags, 1, vDSP_Length(half))

        let binHz = sampleRate / Float(n)
        func bins(_ lowHz: Float, _ highHz: Float) -> (Int, Int) {
            let lo = min(half - 1, max(1, Int(lowHz / binHz)))
            return (lo, min(half, max(lo + 1, Int(highHz / binHz) + 1)))
        }
        func energy(_ range: (Float, Float)) -> Float {
            let (lo, hi) = bins(range.0, range.1)
            var e: Float = 0
            vDSP_svesq(mags + lo, 1, &e, vDSP_Length(hi - lo))
            return e
        }

        var out = SpectrumFrame()
        var raw = SIMD4<Float>.zero
        for b in 0..<4 {
            let (lo, hi) = bins(Self.bandLow[b], Self.bandHigh[b])
            var m: Float = 0
            vDSP_meanv(mags + lo, 1, &m, vDSP_Length(hi - lo))
            raw[b] = m.squareRoot()
        }
        // Running peak with slow decay keeps every band using its own full range.
        // Decays are per second of audio, so they don't depend on the tap's buffer size.
        peak = pointwiseMax(peak * powf(0.84, dt), pointwiseMax(raw, SIMD4(repeating: 0.03)))
        out.bands = pointwiseMin(raw / peak, SIMD4(repeating: 1))

        // Loudness: the ceiling forgets slowly (half in ~10 s), so a breakdown reads as quiet
        // and the drop after it as loud.
        let loud = energy(Self.loudRange).squareRoot()
        loudPeak = max(loudPeak * powf(0.933, dt), max(loud, Self.loudFloor))
        out.level = min(loud / loudPeak, 1)

        warmup += 1
        let settled = warmup > 8
        out.kick = low.step(energy(Self.kickRange), dt: dt, armed: settled)
        out.snap = high.step(energy(Self.snapRange), dt: dt, armed: settled)
        return out
    }
}

/// Onset detector for one frequency range: how far the energy jumped above what was there
/// ~45 ms ago, as a short envelope (instant attack, ~90 ms release).
///
/// The reference lags four analyses behind, so a hit keeps registering while it fills the
/// window and stops once its own energy is the reference; a ringing tail never retriggers,
/// and the reference lets go quickly, so the next hit counts even right after a loud one.
/// Jumps are ratios, so the detector doesn't care how loud the track is mastered, but a hit
/// must also be noticeable against the range's recent peak (no ticks out of silence).
nonisolated struct Onset {
    /// log2 of the energy ratio where a hit starts to count, and the span up to "full strength".
    let threshold: Float
    let range: Float

    private var recent = SIMD4<Float>.zero
    private var reference: Float = 0
    private var ceiling: Float = 0
    private var envelope: Float = 0

    init(threshold: Float, range: Float) {
        self.threshold = threshold
        self.range = range
    }

    mutating func reset() {
        recent = .zero
        reference = 0
        envelope = 0
    }

    mutating func step(_ energy: Float, dt: Float, armed: Bool) -> Float {
        ceiling = max(ceiling * powf(0.84, dt), energy)
        reference = max(reference * expf(-dt / 0.045), recent.w)
        let base = max(reference, recent.z * 0.5)
        let floor = ceiling * 0.01 + 1e-12
        var strength: Float = 0
        if armed {
            let jump = log2f((energy + floor) / (base + floor))
            let loudEnough = min(max((energy / max(ceiling, 1e-12) - 0.04) / 0.26, 0), 1)
            strength = min(max((jump - threshold) / range, 0), 1) * loudEnough
        }
        recent = SIMD4(energy, recent.x, recent.y, recent.z)
        envelope = max(envelope * expf(-dt / 0.09), strength)
        return envelope
    }
}
