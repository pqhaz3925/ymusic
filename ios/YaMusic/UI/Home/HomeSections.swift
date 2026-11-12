import SwiftUI

// MARK: - Feed sections

/// Everything under the hero. Observes nothing scroll-related, so scrolling never
/// re-evaluates it; it changes only when the feed does.
struct HomeFeedSections: View {
    let feed: HomeFeed

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !feed.mixes.isEmpty {
                MixCapsules(mixes: feed.mixes)
            }
            if !feed.quickAccess.isEmpty {
                QuickGrid(tiles: feed.quickAccess)
                    .padding(.horizontal, Theme.gutter)
            }
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(feed.shelves) { shelf in
                    if ReleaseCarousel.matches(shelf) {
                        ReleaseCarousel(shelf: shelf)
                    } else {
                        ShelfCarousel(shelf: shelf)
                    }
                }
            }
        }
    }
}

// MARK: - Mix capsules ("Для вас", "Тренды")

/// Horizontal Liquid Glass capsules with an overlapping cover pair; tap starts that wave.
/// The capsule whose station is playing is tinted yellow.
struct MixCapsules: View {
    let mixes: [MixCard]
    @Environment(Player.self) private var player

    var body: some View {
        let playing = player.waveStationId
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(mixes) { mix in
                        let active = mix.stationId == playing
                        Button { player.playWave(mix.stationId) } label: { capsule(mix, active: active) }
                            .buttonStyle(.plain)
                            .glassEffect(active ? .regular.tint(Theme.accent.opacity(0.3)).interactive()
                                                : .regular.interactive(),
                                         in: .capsule)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(mix.title), \(mix.subtitle)")
                            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func capsule(_ mix: MixCard, active: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: -16) {
                ForEach(Array(mix.coverURIs.prefix(2).enumerated()), id: \.offset) { _, uri in
                    CoverImage(url: CoverURL.make(uri, size: 100), cornerRadius: 0)
                        .frame(width: 46, height: 46)
                        .background(LinearGradient(colors: [.pink.opacity(0.55), .purple.opacity(0.55)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(.circle)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1.5))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(mix.title)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(active ? Theme.accent : .white)
                    if active {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(mix.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 20)
        .padding(.vertical, 7)
        .contentShape(.capsule)
    }
}

// MARK: - Quick access grid

/// Two columns of cover + title + subtitle, on plain black like the reference.
struct QuickGrid: View {
    let tiles: [QuickTile]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(tiles) { tile in
                NavigationLink(value: tile.destination) { label(tile) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func label(_ tile: QuickTile) -> some View {
        HStack(spacing: 12) {
            // Cover with a dim card peeking out behind it ("stack" look of the reference).
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.13))
                    .frame(width: 46, height: 46)
                    .offset(x: 7, y: -6)
                CoverImage(url: CoverURL.make(tile.coverURI, size: 100), cornerRadius: 8)
                    .frame(width: 50, height: 50)
            }
            .frame(width: 58, height: 56, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let s = tile.subtitle, !s.isEmpty {
                    Text(s).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shelves

/// 140 pt cover carousel.
struct ShelfCarousel: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title3.weight(.heavy))
                .padding(.horizontal, Theme.gutter)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.items) { item in
                        ShelfLink(item: item, shelf: shelf) { ShelfCard(item: item) }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// «Новые релизы»: a paged carousel of big artwork cards with the title over a bottom
/// gradient and a centred "Title ›" header.
struct ReleaseCarousel: View {
    let shelf: Shelf

    static func matches(_ shelf: Shelf) -> Bool {
        shelf.id.lowercased().contains("release") || shelf.title.lowercased().contains("релиз")
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(shelf.title)
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.bold))
            }
            .font(.title2.weight(.heavy))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.gutter)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(shelf.items) { item in
                        ShelfLink(item: item, shelf: shelf) { ReleaseCard(item: item) }
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, Theme.gutter)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// Square cover, title and subtitle centred over a bottom gradient.
private struct ReleaseCard: View {
    let item: ShelfItem

    var body: some View {
        let info = item.card(size: 1000)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { CoverImage(url: info.url, cornerRadius: 0) }
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    Text(info.title)
                        .font(.system(size: 30, weight: .black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let s = info.subtitle, !s.isEmpty {
                        Text(s)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 80)
                .padding(.bottom, 22)
                .background {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(.rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
            .accessibilityElement(children: .combine)
    }
}

/// 140 pt cover with title and subtitle under it.
private struct ShelfCard: View {
    let item: ShelfItem

    var body: some View {
        let info = item.card(size: 400)
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: info.url, cornerRadius: info.round ? 70 : Theme.cornerRadius)
                .frame(width: 140, height: 140)
                .clipShape(.rect(cornerRadius: info.round ? 70 : Theme.cornerRadius))
            Text(info.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let s = info.subtitle {
                Text(s).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .frame(width: 140, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps a card in the right action: navigation for albums / playlists / artists, play for
/// tracks (with the track context menu).
private struct ShelfLink<Label: View>: View {
    let item: ShelfItem
    let shelf: Shelf
    @ViewBuilder let label: () -> Label

    @Environment(Player.self) private var player

    var body: some View {
        switch item {
        case .album(let a):
            NavigationLink(value: Destination.album(a)) { label() }.buttonStyle(.plain)
        case .playlist(let p):
            NavigationLink(value: Destination.playlist(p)) { label() }.buttonStyle(.plain)
        case .artist(let a):
            NavigationLink(value: Destination.artist(a)) { label() }.buttonStyle(.plain)
        case .track(let t):
            Button { play(t) } label: { label() }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { play(t) } label: { SwiftUI.Label("Слушать", systemImage: "play.fill") }
                    // Shared with track lists (UI/Collection/TrackRow.swift): queue, like, download, wave.
                    TrackMenuItems(track: t)
                }
        }
    }

    /// Plays the shelf's tracks starting at `t`.
    private func play(_ t: Track) {
        let tracks = shelf.items.compactMap { if case .track(let x) = $0 { x } else { nil } }
        player.play(tracks, startAt: tracks.firstIndex(of: t) ?? 0)
    }
}

private extension ShelfItem {
    /// Cover URL (`size` px), title and subtitle for a card; `round` for artists.
    func card(size: Int) -> (url: URL?, title: String, subtitle: String?, round: Bool) {
        switch self {
        case .album(let a): (a.coverURL(size), a.title, a.artists.map(\.name).joined(separator: ", "), false)
        case .playlist(let p): (p.coverURL(size), p.title, p.ownerName, false)
        case .artist(let a): (a.coverURL(size), a.name, "Исполнитель", true)
        case .track(let t): (t.coverURL(size), t.title, t.artistLine, false)
        }
    }
}

// MARK: - Offline banner

/// Slim glass pill under the top bar while offline; opens the downloads.
struct OfflineBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isOffline {
            NavigationLink(value: Destination.downloads) {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                    Text("Офлайн")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .transition(.opacity)
        }
    }
}

// MARK: - Loading skeleton

/// Static dim placeholders: no animation, nothing re-evaluates while it is shown.
struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                block(180, 60, 30)
                block(nil, 60, 30)
            }
            LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in block(nil, 56, 8) }
            }
            VStack(alignment: .leading, spacing: 12) {
                block(150, 20, 6)
                HStack(spacing: 12) {
                    block(140, 140, Theme.cornerRadius)
                    block(140, 140, Theme.cornerRadius)
                    block(nil, 140, Theme.cornerRadius)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загрузка")
    }

    private func block(_ w: CGFloat?, _ h: CGFloat, _ r: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r)
            .fill(.white.opacity(0.08))
            .frame(width: w, height: h)
            .frame(maxWidth: w == nil ? .infinity : nil)
    }
}
