# ymusic

Personal Yandex Music client: a Rust core (port of MarshalX/yandex-music-api, exposed through
UniFFI) with a SwiftUI iPhone app (iOS 26, Liquid Glass) and a minimal Mac app on the same core.
UI language is Russian; code comments are English.

## Layout

- `core/` — Rust. `src/ffi.rs` is the facade the apps call (`YmClient`); `src/client/*`, `src/models/*`
  mirror the Python library. `examples/` are dev tools that hit the real API (need `YM_TOKEN`):
  `devauth` (device-flow login → token file), `ffi_smoke` (every FFI call the apps use),
  `probe` (what streams the API hands out), `dbg_*`.
- `ios/` — XcodeGen project (`project.yml`). `YaMusic/Core` is shared with the Mac app and must
  stay cross-platform (`#if os(iOS)` / `canImport(UIKit)`); `YaMusic/UI` is iPhone-only except
  `UI/Components/{WaveBackground,WaveRenderer,CoverImage,Theme}.swift` and `Resources/Shaders`.
- `mac/` — XcodeGen project for the Mac app (`YaMusicMac/` = Mac-only UI; sources of `ios/YaMusic/Core` by path).
- `scripts/` — build / deploy / measure helpers.

## Build and run

- Core → XCFramework (iOS device, iOS sim, macOS arm64) + regenerated Swift bindings:
  `core/build-xcframework.sh`. Run it after any change to `ffi.rs`.
- Signing team is not in the repo: put `YM_TEAM_ID=<Apple team id>` into `local.env` at the root
  (git-ignored); the scripts pass it to xcodebuild. It must match the app already on the phone.
- iPhone: `scripts/deploy-ios.sh [--launch] [-- <launch args>]` (signed Debug build → connected iPhone).
- Compile check without a device:
  `xcodebuild -project ios/YaMusic.xcodeproj -scheme YaMusic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Mac: `scripts/build-mac.sh [--run] [-- <launch args>]`.
- Icons: `swift scripts/make-icon.swift` regenerates both asset catalogs.
- Never boot the iOS Simulator (owner's rule): verify on the device or by compiling.

## Architecture (the parts that are easy to get wrong)

- **Actor isolation.** App targets default to `MainActor`. The UniFFI output lives in its own
  `YmBindings` module (nonisolated) so FFI calls stay off the main thread. Models are `nonisolated`.
- **Audio** (`Core/Player.swift`, `Core/Storage/*`). One `AVPlayer`. Every byte comes from
  `TrackStore`: a cache-through loader (`AVAssetResourceLoaderDelegate`, scheme `ymstream`) that
  streams into a sparse file, resumes with `Range`, re-resolves expired signed URLs and retries
  forever on network errors; finished files replay with no network; explicit downloads are the same
  files pinned in Application Support. Failing a loader request does not fail the `AVPlayerItem`,
  hence `TrackStore.onStreamFailure` and the player's stall watchdog.
- **Quality** (`Core/Network/QualityController.swift`). `lq` 64 kbit/s HE-AAC, `nq` 192, `hq` 256 AAC,
  `lossless` FLAC ~940 — all fast-start MP4 (measured). The controller lowers the *requested*
  quality on stalls / low measured throughput and raises it again when the link measures healthy
  twice; each new track simply asks for `quality.effective`.
- **Nothing may run per frame in SwiftUI.** The wave backdrop is a tiny (~0.3 px/pt) `CAMetalLayer`
  drawable on its own display link (`WaveRenderer.swift`), paused when hidden / backgrounded / hot;
  band energies go through `SpectrumSource` (a lock, not observation) and the FFT runs only while a
  visualiser is on screen. No `TimelineView`, timers or repeat-forever animations in views; the
  player publishes `elapsed` twice a second and only while the app is in the foreground.
- **My Wave tuning** (`WaveTuning` in `Core/Models.swift`): activity / character / mood / language
  travel inside the station id as extra seeds (`user:onyourwave,settingMoodEnergy:calm`); the core
  splits on commas when it opens the rotor session.
- **Offline data** (`Core/Library.swift`): library responses are cached on disk; views show
  `cached(key)` first and then `load(key)`.

## Measuring (DEBUG builds)

Launch arguments (see `AppModel.init`): `-perfProbe YES` prints `PERF cpu=…% thermal=… playing=… q=… want=…`
every 2 s; `-ymPlay wave|liked|downloads`, `-ymOffline YES|NO`, `-ymQuality lq|nq|hq|lossless`,
`-ymThrottleKbps N [-ymThrottleSeconds S]` (weak-link simulator for audio fetches), `-ymSkipEvery S`,
`-ymToken <token>` (sign in without the OAuth sheet). `-ymOffline` / `-ymQuality` persist: reset them.

- `scripts/perf-ios.sh <seconds> [args]` — run on the phone with the probe and print its lines.
- `scripts/sys-trace-ios.sh <name> <seconds>` — system-wide trace (watch `backboardd`); xctrace
  intermittently says "Waiting for device to boot", just rerun.

Reference numbers (iPhone 16 Pro, lossless stream): home idle ≈ 2 % of one core, My Wave playing on
screen ≈ 5.5 %, playing in the background ≈ 0.1–0.2 %.
