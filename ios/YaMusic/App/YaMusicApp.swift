import SwiftUI

@main
struct YaMusicApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.player)
                .environment(app.settings)
                .environment(app.network)
                .environment(app.store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Tab shell. Liquid Glass tab bar with the mini player as the bottom accessory.
struct RootView: View {
    @Environment(AppModel.self) private var app
    /// «Войти» in Settings: show auth only after the settings sheet is gone (two sheets can't swap in one update).
    @State private var authAfterSettings = false

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("Главная", systemImage: "music.note", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Коллекция", systemImage: "heart.text.square", value: AppTab.collection) {
                NavigationStack { CollectionView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayer()
        }
        .overlay(alignment: .top) {
            NoticeToast()
        }
        .fullScreenCover(isPresented: $app.showNowPlaying) {
            NowPlayingView()
        }
        .sheet(isPresented: $app.showAuth) {
            AuthView()
        }
        .sheet(isPresented: $app.showSettings, onDismiss: {
            if authAfterSettings {
                authAfterSettings = false
                app.showAuth = true
            }
        }) {
            SettingsView(onSignIn: {
                authAfterSettings = true
                app.showSettings = false
            })
        }
    }
}
