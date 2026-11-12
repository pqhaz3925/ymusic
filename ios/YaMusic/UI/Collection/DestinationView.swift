import SwiftUI

/// Tracks of a destination (liked, history, downloads, playlist, album, artist): header,
/// glass actions, lazy track list. Offline, rows without a local copy are dimmed and the
/// play actions use only what is on the device.
struct DestinationView: View {
    let destination: Destination

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store

    @State private var tracks: [Track] = []
    @State private var phase: ListLoadPhase = .loading
    @State private var refreshed = false

    private var isDownloads: Bool {
        if case .downloads = destination { return true }
        return false
    }

    private var isLiked: Bool {
        if case .liked = destination { return true }
        return false
    }

    /// Downloads are live from the store (rows vanish when removed); the rest is what was loaded.
    private var list: [Track] { isDownloads ? store.downloaded : tracks }

    var body: some View {
        let list = self.list
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DestinationHeader(destination: destination,
                                  count: list.isEmpty && phase == .loading ? nil : list.count)
                DestinationActions(isDownloads: isDownloads, tracks: list)
                    .padding(.bottom, 16)
                content(list)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle(destination.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(force: true) }
        .task { await load() }
        .onChange(of: isLiked ? app.likedIds.count : 0) {
            // Likes toggled elsewhere: AppModel keeps the cached liked list in step.
            if let cached = app.cachedTracks(of: .liked) { tracks = cached }
        }
    }

    @ViewBuilder
    private func content(_ list: [Track]) -> some View {
        if list.isEmpty {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            case .failed(let message):
                CollectionErrorView(message: message) { Task { await load(force: true) } }
            case .loaded:
                emptyState
            }
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, track in
                TrackRow(track: track) { play(list, from: i) }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch destination {
        case .downloads:
            EmptyStateView(icon: "arrow.down.circle", title: "Скачанных треков нет",
                           subtitle: "Нажмите «Скачать» в плейлисте или альбоме, чтобы слушать без сети.")
        case .liked:
            EmptyStateView(icon: "heart", title: "Здесь пока пусто",
                           subtitle: "Ставьте лайки трекам, и они появятся здесь.")
        default:
            EmptyStateView(icon: "music.note", title: "Нет треков",
                           subtitle: "Здесь пока нечего слушать.")
        }
    }

    private func play(_ list: [Track], from i: Int) {
        CollectionPlayback.play(list, startAt: i, player: player, store: store, offline: app.isOffline)
    }

    /// Cached copy instantly, then a fresh one. Errors only surface when nothing is cached.
    private func load(force: Bool = false) async {
        if isDownloads { phase = .loaded; return }
        if refreshed && !force { return }
        if tracks.isEmpty, let cached = app.cachedTracks(of: destination) {
            tracks = cached
            phase = .loaded
        }
        guard app.network.isOnline else {
            if tracks.isEmpty {
                phase = .failed(CollectionText.loadError(URLError(.notConnectedToInternet), offline: true))
            }
            return
        }
        if case .failed = phase { phase = .loading }
        do {
            let fresh = try await app.tracks(of: destination)
            tracks = fresh
            phase = .loaded
            refreshed = true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if tracks.isEmpty { phase = .failed(CollectionText.loadError(error, offline: app.isOffline)) }
        }
    }
}

// MARK: - Header

private struct DestinationHeader: View {
    let destination: Destination
    /// nil while loading.
    let count: Int?

    var body: some View {
        VStack(spacing: 8) {
            art
                .frame(width: 180, height: 180)
                .padding(.bottom, 8)
            Text(destination.kindLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
            Text(destination.screenTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let sub = destination.subtitle {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            if let count {
                Text(CollectionText.tracks(count))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var art: some View {
        switch destination {
        case .liked:
            CollectionSymbolTile(symbol: "heart.fill", colors: CollectionSymbolTile.liked,
                                 cornerRadius: 24, symbolSize: 72)
        case .history:
            CollectionSymbolTile(symbol: "clock.arrow.circlepath", colors: CollectionSymbolTile.history,
                                 cornerRadius: 24, symbolSize: 68)
        case .downloads:
            CollectionSymbolTile(symbol: "arrow.down", colors: CollectionSymbolTile.downloads,
                                 cornerRadius: 24, symbolSize: 72)
        case .playlist(let p):
            CoverImage(url: p.coverURL(400), cornerRadius: 18)
        case .album(let a):
            CoverImage(url: a.coverURL(400), cornerRadius: 18)
        case .artist(let a):
            CoverImage(url: a.coverURL(400), cornerRadius: 90)
        }
    }
}

// MARK: - Actions

/// «Слушать», «Перемешать», download control and the offline note. Its own view so that
/// offline availability / download progress re-render only this block.
private struct DestinationActions: View {
    let isDownloads: Bool
    let tracks: [Track]

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store

    var body: some View {
        let offline = app.isOffline
        // Only offline do we need to look at the store at all.
        let available = offline ? tracks.reduce(0) { $0 + (store.hasLocalCopy($1.id) ? 1 : 0) } : tracks.count

        VStack(alignment: .leading, spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            CollectionPlayback.play(tracks, player: player, store: store, offline: offline)
                        } label: {
                            Label("Слушать", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(.black)
                        .disabled(available == 0)

                        Button {
                            CollectionPlayback.play(tracks, shuffled: true, player: player, store: store, offline: offline)
                        } label: {
                            Label("Перемешать", systemImage: "shuffle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .disabled(available == 0)
                    }
                    .controlSize(.large)

                    if isDownloads {
                        DownloadsManagerBar()
                    } else if !tracks.isEmpty {
                        HStack {
                            ListDownloadButton(tracks: tracks)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if offline && !tracks.isEmpty {
                Label(available == 0
                      ? "Нет сети, а из этого списка ничего не скачано."
                      : "Нет сети — доступно \(available) из \(tracks.count)",
                      systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Labels

fileprivate extension Destination {
    var screenTitle: String {
        switch self {
        case .liked: "Мне нравится"
        case .history: "История"
        case .downloads: "Скачанное"
        case .playlist(let p): p.title
        case .album(let a): a.title
        case .artist(let a): a.name
        }
    }

    var subtitle: String? {
        switch self {
        case .playlist(let p):
            return p.ownerName
        case .album(let a):
            let parts = [a.artists.map(\.name).joined(separator: ", "), a.year.map(String.init) ?? ""]
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .downloads:
            return "Доступно без сети"
        default:
            return nil
        }
    }

    var kindLabel: String {
        switch self {
        case .liked: "Коллекция"
        case .history: "Недавно слушали"
        case .downloads: "Офлайн"
        case .playlist: "Плейлист"
        case .album: "Альбом"
        case .artist: "Исполнитель"
        }
    }
}
