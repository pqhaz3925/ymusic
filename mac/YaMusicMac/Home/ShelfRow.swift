import SwiftUI

/// A titled horizontal row of covers. Albums / playlists / artists open their track list;
/// tracks play (the shelf's tracks become the queue).
struct ShelfRow: View {
    let shelf: Shelf

    var body: some View {
        CoverShelf(title: shelf.title, items: shelf.items)
    }
}

struct CoverShelf: View {
    let title: String
    let items: [ShelfItem]

    @Environment(AppModel.self) private var app
    private var player: Player { app.player }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, Layout.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        cell(item)
                    }
                }
                .padding(.horizontal, Layout.gutter)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder
    private func cell(_ item: ShelfItem) -> some View {
        switch item {
        case .album(let a):
            NavigationLink(value: Destination.album(a)) { ShelfCard(item: item) }.buttonStyle(.plain)
        case .playlist(let p):
            NavigationLink(value: Destination.playlist(p)) { ShelfCard(item: item) }.buttonStyle(.plain)
        case .artist(let a):
            NavigationLink(value: Destination.artist(a)) { ShelfCard(item: item) }.buttonStyle(.plain)
        case .track(let t):
            Button { play(t) } label: { ShelfCard(item: item) }
                .buttonStyle(.plain)
                .contextMenu { TrackMenuItems(app: app, tracks: [t]) }
        }
    }

    private func play(_ track: Track) {
        let tracks = items.compactMap { if case .track(let x) = $0 { x } else { nil } }
        player.play(tracks, startAt: tracks.firstIndex(of: track) ?? 0)
    }
}

/// Cover + two lines. Highlights on hover.
struct ShelfCard: View {
    let item: ShelfItem
    @State private var hover = false

    var body: some View {
        let info = Self.info(item)
        VStack(alignment: info.round ? .center : .leading, spacing: 6) {
            CoverImage(url: info.url, cornerRadius: info.round ? Layout.card / 2 : 10)
                .frame(width: Layout.card, height: Layout.card)
                .overlay(alignment: .bottomTrailing) {
                    if hover, info.playable {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Theme.accent, in: .circle)
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(hover ? 0.4 : 0), radius: 8, y: 4)
            Text(info.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let sub = info.subtitle, !sub.isEmpty {
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: Layout.card)
        .contentShape(.rect)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private static func info(_ item: ShelfItem) -> (url: URL?, title: String, subtitle: String?, round: Bool, playable: Bool) {
        let size = 400
        return switch item {
        case .album(let a): (a.coverURL(size), a.title, a.artists.map(\.name).joined(separator: ", "), false, false)
        case .playlist(let p): (p.coverURL(size), p.title, p.ownerName, false, false)
        case .artist(let a): (a.coverURL(size), a.name, "Исполнитель", true, false)
        case .track(let t): (t.coverURL(size), t.title, t.artistLine, false, true)
        }
    }
}
