import Accelerate
import CoreAudio
import Foundation
import Synchronization

/// FFT band analyser behind the wave backdrop. One instance per audio tap.
/// Hann window -> 1024-point real FFT -> 4 log-spaced bands -> running-peak normalization,
/// published into a `SpectrumSource` when the playhead gets to the analysed samples (the tap
/// runs ahead of what is heard).
///
/// `process` runs on the tap's real-time thread: no allocation, no locks of its own (the only
/// lock taken is the mailbox's), and nothing at all unless a visualiser is watching.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    private static let n = 1024
    private static let half = 512
    /// Frames between two FFTs at most: taps that deliver tiny buffers don't need one each.
    private static let hop = 512
    /// Band edges in Hz: bass, low-mid, high-mid, treble.
    private static let bandLow = SIMD4<Float>(30, 200, 800, 3000)
    private static let bandHigh = SIMD4<Float>(200, 800, 3000, 12000)

    private static let layoutFloat32: UInt64 = 1
    private static let layoutInt16: UInt64 = 2

    /// Results waiting for the playhead. Far more than the tap's lead needs.
    private static let capacity = 64
    /// Publish this early: the next chance only comes with the next tap buffer.
    private static let lookahead = 0.02
    /// A result further ahead of the playhead than this can't be from the current position.
    private static let maxLead = 3.0

    private let source: SpectrumSource
    private let clock: PlayheadClock
    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private let window = UnsafeMutablePointer<Float>.allocate(capacity: n)
    /// The newest `n` mono samples, oldest first.
    private let history = UnsafeMutablePointer<Float>.allocate(capacity: n)
    private let frame = UnsafeMutablePointer<Float>.allocate(capacity: n)
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: n)
    private let re = UnsafeMutablePointer<Float>.allocate(capacity: half)
    private let im = UnsafeMutablePointer<Float>.allocate(capacity: half)
    private let mags = UnsafeMutablePointer<Float>.allocate(capacity: half)
    /// Ring of results and the media time each one belongs to.
    private let queuedBands = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: capacity)
    private let queuedTimes = UnsafeMutablePointer<Double>.allocate(capacity: capacity)

    /// Source format, packed so the audio thread reads it without a lock:
    /// bits 0-1 layout (0 = unsupported), bit 2 interleaved, bits 8-15 channels, bits 32-63 sample rate.
    private let format = Atomic<UInt64>(0)

    // Audio-thread state.
    private var peak = SIMD4<Float>(repeating: 0.03)
    private var pending = 0
    private var head = 0
    private var queued = 0
    private var lastEnd = -Double.infinity

    init(source: SpectrumSource, clock: PlayheadClock) {
        self.source = source
        self.clock = clock
        setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(window, vDSP_Length(Self.n), Int32(vDSP_HANN_NORM))
        history.initialize(repeating: 0, count: Self.n)
        frame.initialize(repeating: 0, count: Self.n)
        scratch.initialize(repeating: 0, count: Self.n)
        re.initialize(repeating: 0, count: Self.half)
        im.initialize(repeating: 0, count: Self.half)
        mags.initialize(repeating: 0, count: Self.half)
        queuedBands.initialize(repeating: .zero, count: Self.capacity)
        queuedTimes.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate(); history.deallocate(); frame.deallocate(); scratch.deallocate()
        re.deallocate(); im.deallocate(); mags.deallocate()
        queuedBands.deallocate(); queuedTimes.deallocate()
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
        guard frames > 0, source.isWatched else { queued = 0; return }
        // A jump in media time (seek, restart): what is queued would never come due in order.
        if !(abs(mediaStart - lastEnd) < 0.1) { queued = 0 }
        lastEnd = mediaStart + mediaDuration
        defer { publishDue() }
        let packed = format.load(ordering: .relaxed)
        let layout = packed & 3
        guard layout != 0 else { return }
        let interleaved = packed & 4 != 0
        let channels = Int((packed >> 8) & 0xFF)
        let sampleRate = Float(packed >> 32)
        let width = layout == Self.layoutFloat32 ? 4 : 2

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count >= 1, let first = buffers[0].mData else { return }
        // Only the newest `n` frames matter.
        let n = Self.n
        let take = min(frames, n)
        let skip = frames - take
        let stride = interleaved ? channels : 1
        guard Int(buffers[0].mDataByteSize) >= frames * stride * width else { return }
        let left = UnsafeRawPointer(first) + skip * stride * width
        var right: UnsafeRawPointer?
        if interleaved {
            if channels >= 2 { right = left + width }
        } else if buffers.count >= 2, let second = buffers[1].mData,
                  Int(buffers[1].mDataByteSize) >= frames * width {
            right = UnsafeRawPointer(second) + skip * width
        }

        // Slide the history and mix the new frames down to mono at its end.
        if take < n { history.update(from: history + take, count: n - take) }
        let dst = history + (n - take)
        let count = vDSP_Length(take)
        var gain: Float = right == nil ? 1 : 0.5
        if layout == Self.layoutFloat32 {
            let l = left.assumingMemoryBound(to: Float.self)
            if let r = right?.assumingMemoryBound(to: Float.self) {
                vDSP_vadd(l, stride, r, stride, dst, 1, count)
                vDSP_vsmul(dst, 1, &gain, dst, 1, count)
            } else {
                vDSP_vsmul(l, stride, &gain, dst, 1, count)
            }
        } else {
            vDSP_vflt16(left.assumingMemoryBound(to: Int16.self), stride, dst, 1, count)
            if let r = right?.assumingMemoryBound(to: Int16.self) {
                vDSP_vflt16(r, stride, scratch, 1, count)
                vDSP_vadd(dst, 1, scratch, 1, dst, 1, count)
            }
            gain /= 32768
            vDSP_vsmul(dst, 1, &gain, dst, 1, count)
        }

        pending += frames
        guard pending >= Self.hop else { return }
        let dt = min(Float(pending) / sampleRate, 1)
        pending = 0
        let bands = analyze(sampleRate: sampleRate, dt: dt)
        // Without a media time there is nothing to wait for.
        guard lastEnd.isFinite else { source.publish(bands); return }
        if queued == Self.capacity {
            head = (head + 1) % Self.capacity
            queued -= 1
        }
        let slot = (head + queued) % Self.capacity
        queuedBands[slot] = bands
        queuedTimes[slot] = lastEnd
        queued += 1
    }

    /// Hand over the newest result the playhead has reached. While playback isn't running
    /// (pre-roll, pause, stall) results simply wait.
    private func publishDue() {
        guard queued > 0, let playhead = clock.now else { return }
        let horizon = playhead + Self.lookahead
        var due = -1
        while queued > 0 {
            let ahead = queuedTimes[head] - horizon
            if ahead <= 0 {
                due = head
            } else if ahead < Self.maxLead {
                break
            }
            head = (head + 1) % Self.capacity
            queued -= 1
        }
        if due >= 0 { source.publish(queuedBands[due]) }
    }

    private func analyze(sampleRate: Float, dt: Float) -> SIMD4<Float> {
        let n = Self.n, half = Self.half
        vDSP_vmul(history, 1, window, 1, frame, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: re, imagp: im)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, mags, 1, vDSP_Length(half))
        var scale = 1 / Float(n)
        vDSP_vsmul(mags, 1, &scale, mags, 1, vDSP_Length(half))

        let binHz = sampleRate / Float(n)
        var raw = SIMD4<Float>.zero
        for b in 0..<4 {
            let lo = min(half - 1, max(1, Int(Self.bandLow[b] / binHz)))
            let hi = min(half, max(lo + 1, Int(Self.bandHigh[b] / binHz)))
            var m: Float = 0
            vDSP_meanv(mags + lo, 1, &m, vDSP_Length(hi - lo))
            raw[b] = m.squareRoot()
        }
        // Running peak with slow decay keeps every band using its own full range.
        // The decay is per second of audio, so it doesn't depend on the tap's buffer size.
        let decay = powf(0.7, dt)
        peak = pointwiseMax(peak * decay, pointwiseMax(raw, SIMD4(repeating: 0.03)))
        return pointwiseMin(raw / peak, SIMD4(repeating: 1))
    }
}
