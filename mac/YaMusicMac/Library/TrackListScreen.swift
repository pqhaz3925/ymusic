import SwiftUI

/// Tracks of a destination (liked, history, playlist, album, artist): header + native table.
struct TrackListScreen: View {
    let destination: Destination

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player

    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var failure: String?

    private var isLiked: Bool { if case .liked = destination { true } else { false } }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(destination: destination, tracks: tracks, loading: loading)
            if tracks.isEmpty {
                placeholder.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks)
            }
        }
        .navigationTitle(destination.title)
        .task(id: destination) { await load() }
        .onChange(of: isLiked ? app.likedIds.count : 0) {
            // Likes toggled elsewhere: AppModel keeps the cached liked list in step.
            if let cached = app.cachedTracks(of: .liked) { tracks = cached }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if loading {
            ProgressView()
        } else if let failure {
            ContentUnavailableView {
                Label("Не удалось загрузить", systemImage: "exclamationmark.icloud")
            } description: {
                Text(failure)
            } actions: {
                Button("Повторить") { Task { await load() } }
            }
        } else {
            ContentUnavailableView("Здесь пока пусто", systemImage: destination.symbol)
        }
    }

    private func load() async {
        if tracks.isEmpty, let cached = app.cachedTracks(of: destination) {
            tracks = cached
            loading = false
        }
        do {
            let fresh = try await app.tracks(of: destination)
            if fresh != tracks { tracks = fresh }
            failure = nil
        } catch {
            guard !(error is CancellationError) else { return }
            failure = error.localizedDescription
        }
        loading = false
    }
}

/// Cover, title, count / total time, «Слушать» and «Перемешать».
private struct ListHeader: View {
    let destination: Destination
    let tracks: [Track]
    let loading: Bool

    @Environment(Player.self) private var player

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                Text(destination.kind.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(destination.title)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(2)
                if let sub = destination.subtitle, !sub.isEmpty {
                    Text(sub).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(summary).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { player.play(tracks) } label: {
                        Label("Слушать", systemImage: "play.fill")
                    }
                    .buttonStyle(AccentButtonStyle())
                    Button { player.play(tracks.shuffled()) } label: {
                        Label("Перемешать", systemImage: "shuffle")
                    }
                    .buttonStyle(AccentButtonStyle(secondary: true))
                }
                .disabled(tracks.isEmpty)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var summary: String {
        if tracks.isEmpty { return loading ? "Загрузка…" : "Нет треков" }
        let total = tracks.reduce(0) { $0 + $1.durationMs }
        return Fmt.tracks(tracks.count) + (total > 0 ? " · " + Fmt.total(ms: total) : "")
    }

    @ViewBuilder
    private var artwork: some View {
        let round: Bool = if case .artist = destination { true } else { false }
        if let url = destination.coverURL(400) {
            CoverImage(url: url, cornerRadius: round ? 80 : 12)
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.93, green: 0.18, blue: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 160, height: 160)
                .overlay {
                    Image(systemName: destination.symbol)
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }
}

// MARK: - Table

/// A row with a stable, unique id (a list may hold the same track twice).
struct TrackItem: Identifiable, Hashable {
    let id: Int
    let track: Track
}

/// Native table of tracks: double-click / Return plays from that row, context menu acts on
/// the selection. Rows are created lazily by AppKit; cells observe only what they show.
///
/// Cells get the model passed in rather than from the environment: rows that AppKit creates
/// on its own (e.g. a jump-scroll) were seen without the environment objects.
struct TrackTable: View {
    let tracks: [Track]

    @Environment(AppModel.self) private var app
    @State private var selection: Set<Int> = []

    var body: some View {
        let items = tracks.enumerated().map { TrackItem(id: $0.offset, track: $0.element) }
        Table(items, selection: $selection) {
            TableColumn("#") { item in IndexCell(item: item, player: app.player) }
                .width(34)
            TableColumn("Название") { item in TitleCell(track: item.track, player: app.player) }
                .width(min: 200, ideal: 340)
            TableColumn("Исполнитель") { item in
                Text(item.track.artistLine).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 120, ideal: 220)
            TableColumn("") { item in LikeCell(track: item.track, app: app) }
                .width(26)
            TableColumn("Время") { item in
                Text(Fmt.duration(ms: item.track.durationMs))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(52)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: Int.self) { ids in
            TrackMenuItems(app: app, tracks: ids.sorted().compactMap { tracks.indices.contains($0) ? tracks[$0] : nil },
                           playFrom: ids.count == 1 ? ids.first : nil,
                           all: tracks)
        } primaryAction: { ids in
            if let i = ids.min() { app.player.play(tracks, startAt: i) }
        }
    }
}

private struct IndexCell: View {
    let item: TrackItem
    let player: Player

    var body: some View {
        Group {
            if player.current?.id == item.track.id {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundStyle(Theme.accent)
            } else {
                Text("\(item.id + 1)").foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct TitleCell: View {
    let track: Track
    let player: Player

    var body: some View {
        let current = player.current?.id == track.id
        HStack(spacing: 10) {
            CoverImage(url: track.coverURL(100), cornerRadius: 4)
                .frame(width: 32, height: 32)
            Text(track.fullTitle)
                .fontWeight(current ? .semibold : .regular)
                .foregroundStyle(current ? Theme.accent : .primary)
                .lineLimit(1)
            if track.explicit {
                Text("E")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(.quaternary, in: .rect(cornerRadius: 3))
                    .help("Ненормативная лексика")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LikeCell: View {
    let track: Track
    let app: AppModel

    var body: some View {
        let liked = app.isLiked(track)
        Button { app.toggleLike(track) } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .foregroundStyle(liked ? Theme.accent : .secondary)
        }
        .buttonStyle(.borderless)
        .help(liked ? "Убрать из «Мне нравится»" : "Мне нравится")
    }
}

// MARK: - Menu

/// Context-menu items for one or more tracks. Menus are hosted outside the view tree:
/// the model is passed in.
struct TrackMenuItems: View {
    let app: AppModel
    let tracks: [Track]
    /// Index in `all` to start playing from (single-row menus).
    var playFrom: Int? = nil
    var all: [Track] = []

    private var player: Player { app.player }

    var body: some View {
        if let i = playFrom, !all.isEmpty {
            Button("Слушать") { player.play(all, startAt: i) }
        } else if playFrom == nil, all.isEmpty, tracks.count == 1 {
            Button("Слушать") { player.play(tracks) }
        }
        Button("Играть следующим") { player.playNext(tracks) }
        Button("Добавить в очередь") { player.addToQueue(tracks) }
        Divider()
        if tracks.count == 1, let t = tracks.first {
            let liked = app.isLiked(t)
            Button(liked ? "Убрать из «Мне нравится»" : "Мне нравится") { app.toggleLike(t) }
            Button("Волна по треку") { player.playWave("track:\(t.id)") }
        } else if !tracks.isEmpty {
            let allLiked = tracks.allSatisfy(app.isLiked)
            Button(allLiked ? "Убрать из «Мне нравится»" : "Мне нравится") {
                for t in tracks where app.isLiked(t) == allLiked { app.toggleLike(t) }
            }
        }
    }
}
