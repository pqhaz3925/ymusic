import SwiftUI

/// Results for the toolbar search field: tracks, then albums / artists / playlists shelves.
struct SearchScreen: View {
    let query: String

    @Environment(AppModel.self) private var app
    @State private var results: SearchResults?
    @State private var resultsFor = ""
    @State private var failure: String?

    var body: some View {
        Group {
            if let results {
                if isEmpty(results) {
                    ContentUnavailableView.search(text: resultsFor)
                } else {
                    content(results)
                }
            } else if let failure {
                ContentUnavailableView("Поиск не удался", systemImage: "exclamationmark.magnifyingglass",
                                       description: Text(failure))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Поиск")
        .task(id: query) { await search() }
    }

    private func content(_ r: SearchResults) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !r.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Треки").font(.title2.bold()).padding(.horizontal, Layout.gutter)
                        VStack(spacing: 0) {
                            ForEach(Array(r.tracks.prefix(12).enumerated()), id: \.offset) { i, t in
                                CompactTrackRow(track: t, index: i, all: Array(r.tracks.prefix(12)))
                            }
                        }
                        .padding(.horizontal, Layout.gutter - 8)
                    }
                }
                if !r.artists.isEmpty { CoverShelf(title: "Исполнители", items: r.artists.map(ShelfItem.artist)) }
                if !r.albums.isEmpty { CoverShelf(title: "Альбомы", items: r.albums.map(ShelfItem.album)) }
                if !r.playlists.isEmpty { CoverShelf(title: "Плейлисты", items: r.playlists.map(ShelfItem.playlist)) }
            }
            .padding(.vertical, 20)
        }
    }

    private func isEmpty(_ r: SearchResults) -> Bool {
        r.tracks.isEmpty && r.albums.isEmpty && r.artists.isEmpty && r.playlists.isEmpty
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let r = try await app.service.search(q)
            guard !Task.isCancelled else { return }
            results = r
            resultsFor = q
            failure = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            failure = error.localizedDescription
        }
    }
}

/// One track line for short lists: click plays, hover shows a play glyph.
struct CompactTrackRow: View {
    let track: Track
    let index: Int
    let all: [Track]

    @Environment(Player.self) private var player
    @Environment(AppModel.self) private var app
    @State private var hover = false

    var body: some View {
        let current = player.current?.id == track.id
        Button { player.play(all, startAt: index) } label: {
            HStack(spacing: 12) {
                CoverImage(url: track.coverURL(100), cornerRadius: 5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        if hover || current {
                            Image(systemName: current && player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .foregroundStyle(current ? Theme.accent : .white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black.opacity(0.45), in: .rect(cornerRadius: 5))
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.fullTitle)
                        .fontWeight(current ? .semibold : .regular)
                        .foregroundStyle(current ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text(track.artistLine).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if app.isLiked(track) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.caption)
                }
                Text(Fmt.duration(ms: track.durationMs))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hover ? Color.white.opacity(0.07) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { TrackMenuItems(app: app, tracks: [track], playFrom: index, all: all) }
    }
}
