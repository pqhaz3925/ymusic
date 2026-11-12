import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case home, liked, history
    /// Playlist id: survives a refresh of the playlist list.
    case playlist(String)
}

/// Sidebar + detail stack, player bar at the bottom, search in the toolbar.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(WindowState.self) private var windowState
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    @State private var selection: SidebarItem? = .home
    @State private var path: [Destination] = []
    @State private var query = ""
    @State private var playlists: [Playlist] = []

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            Sidebar(selection: $selection, playlists: playlists)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: Destination.self) { TrackListScreen(destination: $0) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar() }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Треки, альбомы, исполнители")
        .onChange(of: selection) { path = []; query = "" }
        .onChange(of: query) { if !query.isEmpty { path = [] } }
        .sheet(isPresented: $app.showAuth) { SignInSheet() }
        .task(id: app.isSignedIn) { await loadPlaylists() }
        .background(WindowObserver { v in if windowState.visible != v { windowState.visible = v } })
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugControl.show)) { note in
            let target = note.object as? String ?? ""
            switch target {
            case "home": selection = .home
            case "liked": selection = .liked
            case "history": selection = .history
            case "settings": openSettings()
            case _ where target.hasPrefix("search:"): query = String(target.dropFirst(7))
            case _ where target.hasPrefix("playlist:"): selection = .playlist(String(target.dropFirst(9)))
            case "first-playlist": if let p = playlists.first { selection = .playlist(p.id) }
            default: break
            }
        }
        #endif
    }

    @ViewBuilder
    private var detailRoot: some View {
        if !app.isSignedIn {
            SignedOutView()
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchScreen(query: query)
        } else {
            switch selection ?? .home {
            case .home: HomeScreen()
            case .liked: TrackListScreen(destination: .liked).id("liked")
            case .history: TrackListScreen(destination: .history).id("history")
            case .playlist(let id):
                if let p = playlists.first(where: { $0.id == id }) {
                    TrackListScreen(destination: .playlist(p)).id(id)
                } else {
                    ContentUnavailableView("Плейлист не найден", systemImage: "music.note.list")
                }
            }
        }
    }

    private func loadPlaylists() async {
        guard app.isSignedIn else { playlists = []; return }
        if let cached = app.library.cached(.playlists) { playlists = cached }
        if let fresh = try? await app.library.load(.playlists) { playlists = fresh }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem?
    let playlists: [Playlist]

    @Environment(AppModel.self) private var app

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Главная", systemImage: "house").tag(SidebarItem.home)
                Label("Мне нравится", systemImage: "heart").tag(SidebarItem.liked)
                Label("История", systemImage: "clock").tag(SidebarItem.history)
            }
            if !playlists.isEmpty {
                Section("Плейлисты") {
                    ForEach(playlists) { p in
                        Label(p.title, systemImage: "music.note.list")
                            .lineLimit(1)
                            .tag(SidebarItem.playlist(p.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !app.isSignedIn {
                Button("Войти в Яндекс Музыку") { app.showAuth = true }
                    .buttonStyle(AccentButtonStyle())
                    .padding(12)
            }
        }
    }
}

struct SignedOutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Войдите в Яндекс Музыку", systemImage: "music.note")
        } description: {
            Text("Нужен OAuth-токен Яндекса. Он хранится только в Связке ключей на этом Mac.")
        } actions: {
            Button("Войти…") { app.showAuth = true }
                .buttonStyle(AccentButtonStyle())
                .controlSize(.large)
        }
        .navigationTitle("Музыка")
    }
}

/// Reports whether the hosting window is visible (occlusion state), so animated content can
/// stop when the window is minimised or covered.
struct WindowObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let v = ObserverView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var token: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
