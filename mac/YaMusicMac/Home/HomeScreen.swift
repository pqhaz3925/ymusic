import SwiftUI

/// «Главная»: the wave hero, mix capsules, then the feed's shelves.
/// Cached feed first, refreshed in the background.
struct HomeScreen: View {
    static let myWave = WaveSeed(id: "user:onyourwave", title: "Моя волна")
    static let heroHeight: CGFloat = 340

    @Environment(AppModel.self) private var app

    @State private var feed: HomeFeed?
    @State private var failure: String?
    @State private var heroVisible = true
    /// Toolbar height: the backdrop reaches up under it.
    @State private var topInset: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HomeHero(wave: feed?.wave ?? Self.myWave, heroVisible: heroVisible, topInset: topInset)
                    .frame(height: Self.heroHeight)
                if let feed {
                    if !feed.mixes.isEmpty { MixRow(mixes: feed.mixes) }
                    ForEach(feed.shelves) { ShelfRow(shelf: $0) }
                } else if let failure {
                    ContentUnavailableView {
                        Label("Не удалось загрузить главную", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Повторить") { Task { await refresh() } }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.bottom, 24)
        }
        // The wave fades into pure black, so the page behind it must be black too
        // (the default window background would show the hero as a darker rectangle).
        .background(Theme.background)
        // The hero runs under the toolbar; no blur pass over a live Metal layer while it's there.
        .scrollEdgeEffectHidden(heroVisible, for: .top)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top < Self.heroHeight - 40
        } action: { _, visible in
            heroVisible = visible
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, top in
            topInset = top
        }
        .toolbarBackgroundVisibility(heroVisible ? .hidden : .automatic, for: .windowToolbar)
        .navigationTitle("Главная")
        .task { await appeared() }
    }

    private func appeared() async {
        if feed == nil, let cached = app.library.cached(.home) { feed = cached }
        await refresh()
    }

    private func refresh() async {
        do {
            feed = try await app.library.load(.home)
            failure = nil
        } catch {
            guard !(error is CancellationError) else { return }
            if feed == nil { failure = error.localizedDescription }
        }
    }
}

// MARK: - Hero

/// "▶ Моя волна" over the live backdrop; while the wave plays, the current track and «дальше».
struct HomeHero: View {
    let wave: WaveSeed
    let heroVisible: Bool
    let topInset: CGFloat
    /// Vertical centre of the title inside the hero.
    static let titleCenter: CGFloat = 140

    @Environment(Player.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(WindowState.self) private var window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wave colours taken from the current cover (the renderer cross-fades between palettes).
    @State private var palette: [Color] = []

    private var isCurrentWave: Bool { player.waveStationId == wave.id }
    private var isPlaying: Bool { isCurrentWave && player.isPlaying }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: toggle) {
                HStack(spacing: 16) {
                    ZStack {
                        if isCurrentWave && player.buffering {
                            ProgressView().controlSize(.regular).tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .black))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 40, height: 48)
                    Text(wave.title)
                        .font(.system(size: 50, weight: .heavy))
                        .tracking(-1)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel(isPlaying ? "Пауза, «\(wave.title)»" : "Слушать «\(wave.title)»")

            nowPlaying
                .frame(height: 30)
                .opacity(isCurrentWave ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.top, Self.titleCenter - 32)
        .frame(maxWidth: .infinity)
        .task(id: player.current?.coverURL(200)) {
            guard let url = player.current?.coverURL(200) else { palette = []; return }
            let colors = await CoverPalette.colors(for: url)
            if !Task.isCancelled { palette = colors ?? [] }
        }
        .background(alignment: .top) {
            // The shader puts the cloud's core at 34% of the layer: size the layer so the core
            // sits behind the title, starting under the toolbar; clip at the hero's bottom.
            let blobHeight = (Self.titleCenter + topInset) / 0.34
            WaveBackdrop(isPlaying: player.isPlaying,
                         active: heroVisible && window.visible,
                         motion: settings.waveMotion,
                         reduceMotion: reduceMotion,
                         spectrum: player.spectrumSource,
                         colors: palette)
                .equatable()
                .frame(height: blobHeight)
                .frame(height: HomeScreen.heroHeight + topInset, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                }
                .padding(.top, -topInset)
        }
        .animation(.smooth(duration: 0.3), value: isCurrentWave)
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            Group {
                if let t = player.current, isCurrentWave {
                    Text("\(Text(t.fullTitle).fontWeight(.semibold)) — \(Text(t.artistLine).foregroundStyle(.white.opacity(0.75)))")
                } else {
                    Text("Подбираем музыку…").foregroundStyle(.white.opacity(0.75))
                }
            }
            .font(.title3)
            .lineLimit(1)
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.18), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Следующий трек")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 40)
    }

    private func toggle() {
        if isCurrentWave { player.togglePlay() } else { player.playWave(wave.id) }
    }
}

// MARK: - Mixes

/// Wave modes ("Для вас", "Тренды"…) as glass capsules.
struct MixRow: View {
    let mixes: [MixCard]
    @Environment(Player.self) private var player

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(mixes) { mix in
                        let active = player.waveStationId == mix.stationId
                        Button { player.playWave(mix.stationId) } label: {
                            HStack(spacing: 10) {
                                avatars(mix)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mix.title).font(.headline)
                                    Text(mix.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: 200, alignment: .leading)
                                if active {
                                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 8)
                            .padding(.trailing, 16)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(active ? .regular.tint(Theme.accent.opacity(0.25)).interactive() : .regular.interactive(),
                                     in: .capsule)
                        .help("Волна «\(mix.title)»")
                    }
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.never)
    }

    private func avatars(_ mix: MixCard) -> some View {
        HStack(spacing: -12) {
            ForEach(Array(mix.coverURIs.prefix(2).enumerated()), id: \.offset) { _, uri in
                CoverImage(url: CoverURL.make(uri, size: 100), cornerRadius: 20)
                    .frame(width: 36, height: 36)
                    .clipShape(.circle)
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

enum Layout {
    static let gutter: CGFloat = 28
    static let card: CGFloat = 168
}
