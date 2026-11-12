import AVFoundation
import MediaToolbox

/// Lets a `SpectrumAnalyzer` look at what an `AVPlayerItem` plays, through an
/// `MTAudioProcessingTap` on the item's audio mix. The tap is read-only: samples pass through
/// untouched. Works for file and progressive-download assets (not HLS).
nonisolated enum SpectrumTap {
    /// Audio mix carrying the tap for `track`, or `nil` when the tap can't be created —
    /// playback then simply goes on without feeding the visualiser.
    static func audioMix(for track: AVAssetTrack, publishingTo source: SpectrumSource,
                         clock: PlayheadClock) -> AVAudioMix? {
        let analyzer = SpectrumAnalyzer(source: source, clock: clock)
        // Lifetime: `init` (always called inside Create) takes one reference for the tap's
        // storage and `finalize` (always paired with it) drops it. Nothing else owns the
        // analyser, so it lives exactly as long as the tap, however fast items are replaced.
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(analyzer).toOpaque(),
            init: { _, clientInfo, storageOut in
                if let clientInfo { _ = Unmanaged<SpectrumAnalyzer>.fromOpaque(clientInfo).retain() }
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<SpectrumAnalyzer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                SpectrumTap.analyzer(of: tap).configure(format.pointee)
            },
            unprepare: { tap in
                SpectrumTap.analyzer(of: tap).reset()
            },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                // In-place pass-through: the system fills `buffers` with the source audio.
                var range = CMTimeRange.invalid
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, &range, framesOut)
                guard status == noErr else { framesOut.pointee = 0; return }
                SpectrumTap.analyzer(of: tap).process(buffers, frames: framesOut.pointee,
                                                      mediaStart: range.start.seconds,
                                                      mediaDuration: range.duration.seconds)
            })

        var tap: MTAudioProcessingTap?
        let status = withExtendedLifetime(analyzer) {
            MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                       kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        }
        guard status == noErr, let tap else { return nil }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private static func analyzer(of tap: MTAudioProcessingTap) -> SpectrumAnalyzer {
        Unmanaged<SpectrumAnalyzer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }
}
