import SwiftUI

/// Geometry shared by the hero, its backdrop and the scroll observers.
nonisolated enum HomeLayout {
    /// Height of the hero in the scroll content (it starts right under the top bar).
    static let heroHeight: CGFloat = 360
    /// Vertical centre of the "▶ Моя волна" title inside the hero.
    static let titleCenter: CGFloat = 150
    /// The Metal layer's own height. The shader puts the cloud's core at 34% of it.
    static let blobHeight: CGFloat = 780
    /// How far the blob reaches above the hero's top (under the top bar and status bar),
    /// chosen so the cloud's core sits behind the title.
    static var blobLift: CGFloat { blobHeight * 0.34 - titleCenter }
}

/// Scroll / touch / palette state of the hero.
///
/// `HomeView` only holds the reference and never reads these in its body, so scrolling
/// re-evaluates just the small leaves that observe them (`HomeBackdrop`, the top edge gate),
/// never the grid or the shelves.
@Observable
final class HomeScene {
    /// Scroll distance from the top, clamped to the hero range (negative = overscroll).
    var offset: CGFloat = 0
    /// The hero (and so the blob) is still on screen.
    var heroVisible = true
    /// Top content inset (status bar + top bar), for hit-testing blob touches.
    var insetTop: CGFloat = 100
    /// Global finger position while dragging on the hero; `nil` = lifted.
    var touch: CGPoint?
    /// Palette from the current cover; empty = default magenta/violet/yellow.
    var palette: [Color] = []
}

/// "Главная": "▶ Моя волна" over the live blob, then mix capsules, quick access and shelves.
/// Shows the cached feed instantly and refreshes it in the background.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var feed: HomeFeed?
    /// Set only when there is nothing (not even a cache) to show.
    @State private var failure: String?
    @State private var lastRefresh: Date?
    /// The last refresh could only return the cache; refresh again once back online.
    @State private var refreshedOffline = false
    @State private var scene = HomeScene()

    private static let myWave = WaveSeed(id: "user:onyourwave", title: "Моя волна")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WaveHero(wave: feed?.wave ?? Self.myWave, seeds: feed?.waveSeeds ?? [], scene: scene)
                    .frame(height: HomeLayout.heroHeight)
                    .background(alignment: .bottom) { HomeBackdrop(scene: scene) }
                    .overlay(alignment: .top) { OfflineBanner() }
                sections
            }
            .padding(.bottom, 140)   // clear mini-player + tab bar
        }
        .scrollIndicators(.hidden)
        // Clamped + rounded: once past the hero the value stops changing and no update fires.
        .onScrollGeometryChange(for: CGFloat.self) { g in
            let y = g.contentOffset.y + g.contentInsets.top
            return min(max(y, -400), HomeLayout.heroHeight).rounded()
        } action: { _, y in
            scene.offset = y
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top < HomeLayout.heroHeight * 0.9
        } action: { _, visible in
            scene.heroVisible = visible
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, top in
            scene.insetTop = top
        }
        .simultaneousGesture(blobTouch)
        .background(Theme.background)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .modifier(TopEdgeGate(scene: scene))
        .toolbar { toolbar }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        .refreshable { await refresh() }
        .task(id: app.isOffline) { await appeared() }
    }

    // MARK: - Content

    @ViewBuilder
    private var sections: some View {
        if let feed {
            HomeFeedSections(feed: feed)
        } else if let failure {
            errorView(failure)
        } else {
            HomeSkeleton()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: app.isOffline ? "wifi.slash" : "exclamationmark.icloud")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(app.isOffline ? "Нет подключения" : "Не удалось загрузить главную")
                .font(.headline)
            Text(app.isOffline ? "Главная появится, когда вернётся сеть. Скачанное можно слушать уже сейчас." : message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Повторить") {
                        Task { failure = nil; await refresh() }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(.black)
                    NavigationLink("Открыть скачанное", value: Destination.downloads)
                        .buttonStyle(.glass)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: - Blob touch

    /// Feeds the finger position to the shader when the drag starts inside the hero.
    /// Writes only `scene.touch`, which just the backdrop observes.
    private var blobTouch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard !reduceMotion, scene.heroVisible,
                      v.startLocation.y < scene.insetTop + HomeLayout.heroHeight - scene.offset else { return }
                scene.touch = v.location
            }
            .onEnded { _ in
                if scene.touch != nil { scene.touch = nil }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { app.showSettings = true } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Настройки")
        }
        ToolbarItem(placement: .principal) {
            Text("Музыка")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { app.tab = .search } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Поиск")
        }
    }

    // MARK: - Data

    /// On appear and whenever connectivity flips: cache first, then refresh if stale.
    private func appeared() async {
        if feed == nil, let cached = app.library.cached(.home) { feed = cached }
        let stale = lastRefresh.map { Date.now.timeIntervalSince($0) > 600 } ?? true
        if stale || (refreshedOffline && !app.isOffline) { await refresh() }
    }

    private func refresh() async {
        do {
            let fresh = try await app.library.load(.home)   // falls back to the cache offline
            if feed == nil {
                withAnimation(.smooth) { feed = fresh }
            } else {
                feed = fresh
            }
            failure = nil
            lastRefresh = .now
            refreshedOffline = app.isOffline
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if feed == nil { failure = error.localizedDescription }   // keep stale content otherwise
        }
    }
}

/// Hides the top scroll-edge effect while the hero is on screen, so the blob runs under the
/// top bar untouched (no blur pass over a live layer). As a modifier, only this body
/// re-evaluates when `heroVisible` flips; the wrapped content is passed through as is.
private struct TopEdgeGate: ViewModifier {
    let scene: HomeScene

    func body(content: Content) -> some View {
        content.scrollEdgeEffectHidden(scene.heroVisible, for: .top)
    }
}

#Preview {
    let app = AppModel()
    NavigationStack { HomeView() }
        .environment(app)
        .environment(app.player)
        .environment(app.settings)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
}
