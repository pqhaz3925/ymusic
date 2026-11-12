import SwiftUI

/// Grid screens reachable from the collection root.
enum CollectionRoute: Hashable {
    case playlists, albums, artists

    var title: String {
        switch self {
        case .playlists: "Плейлисты"
        case .albums: "Альбомы"
        case .artists: "Исполнители"
        }
    }
}

/// "Коллекция" tab: wave banner, a paged preview of liked tracks and tiles for
/// playlists, albums, artists and downloads. Cached data first, refreshed after.
struct CollectionView: View {
    @Environment(AppModel.self) private var app

    @State private var liked: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var loading = true
    @State private var lastRefresh: Date?

    /// Re-appearing (back from a pushed screen) re-reads the cache but refetches at most this often.
    private let refreshInterval: TimeInterval = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(spacing: 10) {
                    CollectionWaveBanner()
                    if app.isOffline { offlineNote }
                }
                .padding(.horizontal, Theme.gutter)

                likedSection
                moreSection
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Коллекция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        .navigationDestination(for: CollectionRoute.self) { CollectionGridView(route: $0) }
        .refreshable { await load(force: true) }
        .task { await load() }
        .onChange(of: app.likedIds.count) {
            // AppModel keeps the cached liked list in step with likes made anywhere.
            if let cached = app.library.cached(.liked) { liked = cached }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Профиль и настройки")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                app.tab = .search
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Поиск")
        }
    }

    // MARK: Sections

    private var offlineNote: some View {
        Label("Нет сети — доступно только скачанное", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
    }

    private var likedCount: Int { app.likedIds.isEmpty ? liked.count : app.likedIds.count }

    private var likedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Destination.liked) {
                HStack(spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(LinearGradient(colors: CollectionSymbolTile.liked,
                                                        startPoint: .top, endPoint: .bottom))
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Мне нравится")
                                .font(.title2.weight(.bold))
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if likedCount > 0 {
                            Text(CollectionText.tracks(likedCount))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Мне нравится, \(CollectionText.tracks(likedCount))")
            .padding(.horizontal, Theme.gutter)

            if !liked.isEmpty {
                LikedPreview(tracks: liked)
            } else if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                EmptyStateView(icon: "heart", title: "Здесь пока пусто",
                               subtitle: "Ставьте лайки трекам, и они появятся здесь.")
                    .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ещё у вас в Коллекции")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            GlassEffectContainer(spacing: 12) {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        NavigationLink(value: CollectionRoute.playlists) {
                            CollectionTile(title: "Плейлисты",
                                           subtitle: countLine(playlists.count, "плейлист", "плейлиста", "плейлистов")) {
                                TileArt(url: playlists.first?.coverURL(200), symbol: "music.note.list")
                            }
                        }
                        NavigationLink(value: CollectionRoute.albums) {
                            CollectionTile(title: "Альбомы",
                                           subtitle: countLine(albums.count, "альбом", "альбома", "альбомов")) {
                                TileArt(url: albums.first?.coverURL(200), symbol: "square.stack")
                            }
                        }
                    }
                    GridRow {
                        NavigationLink(value: CollectionRoute.artists) {
                            CollectionTile(title: "Исполнители",
                                           subtitle: countLine(artists.count, "исполнитель", "исполнителя", "исполнителей")) {
                                TileArt(url: artists.first?.coverURL(200), symbol: "music.mic", round: true)
                            }
                        }
                        NavigationLink(value: Destination.downloads) {
                            DownloadsTile()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func countLine(_ n: Int, _ one: String, _ few: String, _ many: String) -> String? {
        if n > 0 { return CollectionText.count(n, one, few, many) }
        return loading ? nil : "Пока пусто"
    }

    // MARK: Data

    private func load(force: Bool = false) async {
        let lib = app.library
        if let v = lib.cached(.liked) { liked = v }
        if let v = lib.cached(.playlists) { playlists = v }
        if let v = lib.cached(.likedAlbums) { albums = v }
        if let v = lib.cached(.likedArtists) { artists = v }

        if !force, let last = lastRefresh, Date.now.timeIntervalSince(last) < refreshInterval {
            loading = false
            return
        }
        guard app.network.isOnline else { loading = false; return }
        lastRefresh = .now

        // Unstructured tasks inherit the main actor; the four fetches run concurrently.
        let tl = Task { try? await lib.load(.liked) }
        let tp = Task { try? await lib.load(.playlists) }
        let ta = Task { try? await lib.load(.likedAlbums) }
        let tr = Task { try? await lib.load(.likedArtists) }

        if let fresh = await tl.value {
            liked = fresh
            // The store skips what it already has or has queued.
            if app.settings.autoDownloadLiked { app.store.download(fresh) }
        }
        if let fresh = await tp.value { playlists = fresh }
        if let fresh = await ta.value { albums = fresh }
        if let fresh = await tr.value { artists = fresh }
        loading = false
    }
}

// MARK: - Wave banner

/// Wide pink Liquid Glass banner that starts "My Wave" seeded by the collection.
private struct CollectionWaveBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player

    private static let pink = Color(red: 0.93, green: 0.12, blue: 0.38)
    private static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        let offline = app.isOffline
        Button {
            player.playWave("personal:collection")
        } label: {
            VStack(spacing: 2) {
                Text("Моя волна по коллекции")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Коллекция")
                        .font(.title2.weight(.heavy))
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .background {
                // Static sheen over the tinted glass; no animation.
                LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0.55).opacity(0.55),
                                        Self.pink.opacity(0.25),
                                        Color(red: 0.75, green: 0.0, blue: 0.2).opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(Self.shape)
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Self.pink.opacity(0.8)).interactive(), in: Self.shape)
        .disabled(offline)
        .opacity(offline ? 0.45 : 1)
        .accessibilityLabel("Моя волна по коллекции")
        .accessibilityHint(offline ? "Недоступно без сети" : "Запускает волну")
    }
}

// MARK: - Liked preview

/// First liked tracks as horizontally paged columns of three rows.
private struct LikedPreview: View {
    let tracks: [Track]

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store

    private let perColumn = 3
    private let limit = 12

    var body: some View {
        let count = min(tracks.count, limit)
        let starts = Array(stride(from: 0, to: count, by: perColumn))
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(starts, id: \.self) { start in
                    VStack(spacing: 2) {
                        ForEach(start..<min(start + perColumn, count), id: \.self) { i in
                            TrackRow(track: tracks[i]) { play(from: i) }
                        }
                    }
                    .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 12)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
    }

    private func play(from i: Int) {
        CollectionPlayback.play(tracks, startAt: i, player: player, store: store, offline: app.isOffline)
    }
}

// MARK: - Tiles

/// Glass tile acting as a button: art, title, secondary line.
private struct CollectionTile<Art: View>: View {
    let title: String
    let subtitle: String?
    let art: Art

    init(title: String, subtitle: String?, @ViewBuilder art: () -> Art) {
        self.title = title
        self.subtitle = subtitle
        self.art = art()
    }

    var body: some View {
        HStack(spacing: 10) {
            art.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .contentShape(.rect(cornerRadius: 20))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// Cover of the first item, or a symbol when there is none.
private struct TileArt: View {
    let url: URL?
    let symbol: String
    var round = false

    var body: some View {
        if let url {
            CoverImage(url: url, cornerRadius: round ? 22 : 8)
        } else {
            RoundedRectangle(cornerRadius: round ? 22 : 8)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityHidden(true)
        }
    }
}

/// Downloads tile; observes the store itself so the root never re-renders on download progress.
private struct DownloadsTile: View {
    @Environment(TrackStore.self) private var store

    var body: some View {
        let n = store.downloaded.count
        CollectionTile(title: "Скачанное",
                       subtitle: n == 0 ? "Нет загрузок"
                                        : "\(CollectionText.tracks(n)) · \(CollectionText.bytes(store.downloadsBytes))") {
            CollectionSymbolTile(symbol: "arrow.down", colors: CollectionSymbolTile.downloads,
                                 cornerRadius: 8, symbolSize: 18)
        }
    }
}

// MARK: - Grid screen

/// Playlists / liked albums / liked artists as an adaptive cover grid.
struct CollectionGridView: View {
    let route: CollectionRoute

    @Environment(AppModel.self) private var app
    @State private var cards: [Card] = []
    @State private var phase: ListLoadPhase = .loading

    struct Card: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let cover: URL?
        let round: Bool
        let destination: Destination
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    var body: some View {
        ScrollView {
            Group {
                if cards.isEmpty {
                    switch phase {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    case .failed(let message):
                        CollectionErrorView(message: message) { Task { await load() } }
                    case .loaded:
                        emptyState
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(cards) { card in
                            NavigationLink(value: card.destination) {
                                CoverCard(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { if phase != .loaded { await load() } }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch route {
        case .playlists:
            EmptyStateView(icon: "music.note.list", title: "Плейлистов пока нет",
                           subtitle: "Созданные вами плейлисты появятся здесь.")
        case .albums:
            EmptyStateView(icon: "square.stack", title: "Альбомов пока нет",
                           subtitle: "Альбомы, которые вам понравились, появятся здесь.")
        case .artists:
            EmptyStateView(icon: "music.mic", title: "Исполнителей пока нет",
                           subtitle: "Исполнители, которые вам понравились, появятся здесь.")
        }
    }

    private func load() async {
        switch route {
        case .playlists:
            await fetch(.playlists) {
                Card(id: $0.id, title: $0.title,
                     subtitle: $0.trackCount.map(CollectionText.tracks) ?? $0.ownerName,
                     cover: $0.coverURL(400), round: false, destination: .playlist($0))
            }
        case .albums:
            await fetch(.likedAlbums) {
                Card(id: $0.id, title: $0.title,
                     subtitle: $0.artists.map(\.name).joined(separator: ", "),
                     cover: $0.coverURL(400), round: false, destination: .album($0))
            }
        case .artists:
            await fetch(.likedArtists) {
                Card(id: $0.id, title: $0.name, subtitle: nil,
                     cover: $0.coverURL(400), round: true, destination: .artist($0))
            }
        }
    }

    /// Cached copy instantly, then a fresh one; an error shows only when nothing is cached.
    private func fetch<T: Codable & Sendable>(_ key: LibraryKey<[T]>, _ map: (T) -> Card) async {
        if cards.isEmpty, let cached = app.library.cached(key) {
            cards = cached.map(map)
            phase = .loaded
        }
        guard app.network.isOnline else {
            if cards.isEmpty {
                phase = .failed(CollectionText.loadError(URLError(.notConnectedToInternet), offline: true))
            }
            return
        }
        if case .failed = phase { phase = .loading }
        do {
            let fresh = try await app.library.load(key)
            cards = fresh.map(map)
            phase = .loaded
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if cards.isEmpty { phase = .failed(CollectionText.loadError(error, offline: app.isOffline)) }
        }
    }
}

private struct CoverCard: View {
    let card: CollectionGridView.Card

    var body: some View {
        VStack(alignment: card.round ? .center : .leading, spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CoverImage(url: card.cover, cornerRadius: card.round ? 999 : Theme.cornerRadius)
                }
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let sub = card.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: card.round ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}
