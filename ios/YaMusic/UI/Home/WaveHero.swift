import SwiftUI

// MARK: - Hero

/// "▶ Моя волна" in big heavy type over the blob (tap = play / pause), then, while this wave
/// plays, the current track with a compact glass "next" control, and the seed chips.
///
/// Text sits straight on the blob like the reference; glass is limited to the small controls.
struct WaveHero: View {
    let wave: WaveSeed
    let seeds: [WaveSeed]
    let scene: HomeScene

    @Environment(Player.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var removed: Set<String> = []
    @State private var showTuning = false

    /// My Wave carries its tuning in the station id ("user:onyourwave,settingMoodEnergy:calm").
    private var isMyWave: Bool { wave.id == WaveTuning.base }
    private var stationId: String { isMyWave ? settings.waveTuning.stationId : wave.id }
    private var isCurrentWave: Bool {
        isMyWave ? WaveTuning.isMyWave(player.waveStationId) : player.waveStationId == wave.id
    }
    private var isPlaying: Bool { isCurrentWave && player.isPlaying }
    private var isBuffering: Bool { isCurrentWave && player.buffering }

    var body: some View {
        let reduce = reduceMotion
        let visibleSeeds = seeds.filter { !removed.contains($0.id) }
        VStack(spacing: 14) {
            title
                .frame(height: 64)
                .padding(.top, HomeLayout.titleCenter - 32)
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 14) {
                    if isCurrentWave {
                        nowPlaying.transition(.opacity)
                    }
                    if isMyWave { tuningChip }
                    if !visibleSeeds.isEmpty {
                        SeedChips(seeds: visibleSeeds, tint: scene.palette.dropFirst(2).first ?? Theme.accent) { seed in
                            withAnimation(.smooth) { _ = removed.insert(seed.id) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.35), value: isCurrentWave)
        .animation(.smooth(duration: 0.35), value: player.current?.id)
        .sheet(isPresented: $showTuning) { WaveTuningSheet() }
        // Drift down and fade while scrolling off the top. Applied at render time:
        // no state, no body re-evaluation per scroll frame.
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            let leaving = min(phase.value, 0)          // -1...0 while leaving at the top
            return content
                .opacity(max(0, 1 + leaving * 1.3))
                .offset(y: reduce ? 0 : -leaving * 90)
        }
    }

    private var title: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                ZStack {
                    if isBuffering {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .black))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 40, height: 48)
                Text(wave.title)
                    .font(.system(size: 46, weight: .heavy))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.gutter)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Пауза, «\(wave.title)»" : "Слушать «\(wave.title)»")
        .accessibilityAddTraits(.isHeader)
    }

    /// "Title — Artist" and a small glass skip button.
    private var nowPlaying: some View {
        HStack(spacing: 12) {
            Group {
                if let t = player.current {
                    Text("\(Text(t.fullTitle).fontWeight(.semibold)) — \(Text(t.artistLine).foregroundStyle(.white.opacity(0.7)))")
                        .id(t.id)
                        .transition(.opacity)
                } else {
                    Text("Подбираем музыку…").foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.subheadline)
            .lineLimit(1)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Следующий трек")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
    }

    /// Opens "Настроить Мою волну"; shows the chosen filters when there are any.
    private var tuningChip: some View {
        let summary = settings.waveTuning.summary
        return Button { showTuning = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "slider.horizontal.3")
                Text(summary ?? "Настроить")
                    .lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(summary == nil ? .white : Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 32)
        .accessibilityLabel("Настроить Мою волну")
        .accessibilityValue(summary ?? "Без фильтров")
    }

    private func toggle() {
        if isCurrentWave { player.togglePlay() } else { player.playWave(stationId) }
    }
}

/// Removable seed pills ("pyro - slowed ×") as interactive tinted Liquid Glass.
/// Expects to sit inside a `GlassEffectContainer`.
struct SeedChips: View {
    let seeds: [WaveSeed]
    let tint: Color
    let onRemove: (WaveSeed) -> Void

    @Environment(Player.self) private var player
    @Namespace private var glass

    var body: some View {
        HStack(spacing: 8) {
            ForEach(seeds.prefix(3)) { seed in
                HStack(spacing: 8) {
                    Button { player.playWave(seed.id) } label: {
                        Text(seed.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    .accessibilityLabel("Волна по «\(seed.title)»")
                    Button { onRemove(seed) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .accessibilityLabel("Убрать «\(seed.title)»")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(tint.opacity(0.45)).interactive(), in: .capsule)
                .glassEffectID(seed.id, in: glass)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Backdrop

/// The live blob behind the hero. It is laid out in the scroll content as the hero's
/// background (so it is exactly aligned with it on every device), extends up under the top
/// bar and is clipped at the hero's bottom with a black fade, so at rest the mix capsules
/// below are not glass over the animated layer.
///
/// This is the only view observing the scroll offset and the drag position: a scroll frame
/// re-evaluates this tiny body (plus a no-op equality check of the blob), nothing else.
struct HomeBackdrop: View {
    let scene: HomeScene

    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down = max(scene.offset, 0), over = max(-scene.offset, 0)
        let progress = min(down / (HomeLayout.heroHeight * 0.85), 1)
        // Fade through the shader's own `dim` (quantized) rather than view opacity: group
        // opacity over a live Metal layer would cost an offscreen pass every frame.
        let dim = ((1 - progress) * 40).rounded() / 40
        BlobLayer(isPlaying: player.isPlaying,
                  palette: scene.palette,
                  active: dim > 0,
                  touch: scene.touch,
                  dim: dim)
            .equatable()
            .frame(height: HomeLayout.blobHeight)
            .frame(height: HomeLayout.blobLift + HomeLayout.heroHeight, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            // Stretch on overscroll; parallax (slower than content) while scrolling down.
            .scaleEffect(1 + over / 900 + (reduceMotion ? 0 : progress * 0.06))
            .offset(y: down * 0.55 - over * 0.6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: player.current?.coverURL(200)) { await updatePalette() }
    }

    private func updatePalette() async {
        guard let url = player.current?.coverURL(200) else {
            if !scene.palette.isEmpty { scene.palette = [] }
            return
        }
        let colors = await CoverPalette.colors(for: url)
        guard !Task.isCancelled else { return }
        scene.palette = colors ?? []                 // WaveBackground cross-fades itself
    }
}

/// `WaveBackground` behind an equality check, so a backdrop re-evaluation whose blob inputs
/// did not change (most scroll frames) doesn't touch the Metal view at all.
private struct BlobLayer: View, Equatable {
    let isPlaying: Bool
    let palette: [Color]
    let active: Bool
    let touch: CGPoint?
    let dim: Double

    var body: some View {
        WaveBackground(isPlaying: isPlaying, palette: palette, active: active,
                       externalTouch: touch, dim: dim)
    }
}
