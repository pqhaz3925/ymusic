import SwiftUI

/// "Поиск" tab: debounced search with best result, tracks, albums, artists, playlists.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player

    @State private var query = ""
    @State private var results: SearchResults?
    @State private var isSearching = false
    @State private var recents: [String] = RecentQueries.load()
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if app.isOffline {
                    offlineState
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    recentSection
                } else if isSearching && results == nil {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let r = results {
                    resultContent(r)
                } else {
                    EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено",
                                   subtitle: "Попробуйте другой запрос.")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Поиск")
        .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Треки, альбомы, исполнители")
        .onChange(of: query) { _, new in scheduleSearch(new) }
        .onChange(of: app.isOffline) { _, offline in
            // Back online: run the query that was typed while offline.
            if !offline { scheduleSearch(query) }
        }
        .onSubmit(of: .search) { remember(query) }
    }

    // MARK: Sections

    private var offlineState: some View {
        VStack(spacing: 4) {
            EmptyStateView(icon: "wifi.slash", title: "Поиск недоступен офлайн",
                           subtitle: app.network.isOnline
                               ? "Включён режим «Только скачанное». Выключите его в настройках, чтобы искать."
                               : "Нет подключения к интернету. Скачанные треки можно слушать в Коллекции.")
            NavigationLink(value: Destination.downloads) {
                Label("Открыть скачанное", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Недавние запросы").font(.title3.weight(.bold))
                    Spacer()
                    Button("Очистить") { clearRecents() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                FlowChips(items: recents) { q in
                    query = q
                } onRemove: { q in
                    recents.removeAll { $0 == q }
                    RecentQueries.save(recents)
                }
            }
        } else {
            EmptyStateView(icon: "magnifyingglass", title: "Что послушаем?",
                           subtitle: "Найдите треки, альбомы и исполнителей.")
        }
    }

    @ViewBuilder
    private func resultContent(_ r: SearchResults) -> some View {
        if r.best == nil && r.tracks.isEmpty && r.albums.isEmpty && r.artists.isEmpty && r.playlists.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "Ничего не найдено",
                           subtitle: "Попробуйте другой запрос.")
        } else {
            if let best = r.best { BestResultCard(item: best) }

            if !r.tracks.isEmpty {
                sectionTitle("Треки")
                LazyVStack(spacing: 0) {
                    ForEach(Array(r.tracks.prefix(20).enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t) { player.play(r.tracks, startAt: i) }
                    }
                }
            }
            if !r.albums.isEmpty {
                sectionTitle("Альбомы")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(r.albums) { a in
                        NavigationLink(value: Destination.album(a)) {
                            ShelfCard(title: a.title, subtitle: a.artists.map(\.name).joined(separator: ", "),
                                      url: a.coverURL(400), circular: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !r.artists.isEmpty {
                sectionTitle("Исполнители")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(r.artists) { a in
                        NavigationLink(value: Destination.artist(a)) {
                            ShelfCard(title: a.name, subtitle: "Исполнитель",
                                      url: a.coverURL(400), circular: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !r.playlists.isEmpty {
                sectionTitle("Плейлисты")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(r.playlists) { p in
                        NavigationLink(value: Destination.playlist(p)) {
                            ShelfCard(title: p.title, subtitle: p.ownerName,
                                      url: p.coverURL(400), circular: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.title3.weight(.bold)).padding(.top, 4)
    }

    // MARK: Search

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1, !app.isOffline else {
            withAnimation(.easeOut(duration: 0.15)) {
                results = nil
                isSearching = false
            }
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let r = try? await app.service.search(q)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { results = r }
                isSearching = false
            }
        }
    }

    private func remember(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recents.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recents.insert(q, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
        RecentQueries.save(recents)
    }

    private func clearRecents() {
        withAnimation { recents = [] }
        RecentQueries.save([])
    }
}

/// Big card for the top "best" result.
private struct BestResultCard: View {
    let item: ShelfItem
    @Environment(Player.self) private var player

    var body: some View {
        Group {
            switch item {
            case .track(let t):
                Button { player.play([t]) } label: {
                    card(title: t.fullTitle, subtitle: t.artistLine, url: t.coverURL(600))
                }
                .buttonStyle(.plain)
            case .album(let a):
                NavigationLink(value: Destination.album(a)) {
                    card(title: a.title, subtitle: a.artists.map(\.name).joined(separator: ", "), url: a.coverURL(600))
                }
                .buttonStyle(.plain)
            case .artist(let a):
                NavigationLink(value: Destination.artist(a)) {
                    card(title: a.name, subtitle: "Исполнитель", url: a.coverURL(600))
                }
                .buttonStyle(.plain)
            case .playlist(let p):
                NavigationLink(value: Destination.playlist(p)) {
                    card(title: p.title, subtitle: p.ownerName, url: p.coverURL(600))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(title: String, subtitle: String?, url: URL?) -> some View {
        HStack(spacing: 14) {
            CoverImage(url: url, cornerRadius: 10)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text("Лучший результат")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(title).font(.headline).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct ShelfCard: View {
    let title: String
    let subtitle: String?
    let url: URL?
    let circular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: url, cornerRadius: circular ? 999 : Theme.cornerRadius)
                .aspectRatio(1, contentMode: .fit)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Simple wrapping chip row for recent queries.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { q in
                HStack(spacing: 4) {
                    Button { onTap(q) } label: {
                        Text(q).font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    Button { onRemove(q) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить запрос \(q)")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

enum RecentQueries {
    private static let key = "recentSearchQueries"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ q: [String]) {
        UserDefaults.standard.set(q, forKey: key)
    }
}
