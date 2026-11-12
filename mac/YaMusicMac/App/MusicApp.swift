import AppKit
import SwiftUI

@main
struct MusicApp: App {
    @State private var app: AppModel
    @State private var window = WindowState()

    init() {
        // Covers are small and re-requested while scrolling long lists: keep them around.
        URLCache.shared = URLCache(memoryCapacity: 48 << 20, diskCapacity: 256 << 20)
        let app = AppModel()
        #if DEBUG
        // `-ymVolume 0`: silent test runs.
        if let raw = UserDefaults.standard.string(forKey: "ymVolume"), let v = Float(raw) {
            app.player.volume = min(max(v, 0), 1)
        }
        DebugControl.install(app: app)
        #endif
        _app = State(initialValue: app)
        SpaceKey.install(player: app.player)
    }

    var body: some Scene {
        Window("Музыка", id: "main") {
            RootView()
                .environment(app)
                .environment(app.player)
                .environment(app.settings)
                .environment(app.store)
                .environment(window)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { PlaybackCommands(app: app) }

        Settings {
            SettingsScreen()
                .environment(app)
                .environment(app.settings)
                .environment(app.store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Whether the main window can be seen at all (not minimised / fully covered / hidden).
/// Only the wave backdrop reads it.
@Observable
final class WindowState {
    var visible = true
}

/// «Воспроизведение» menu.
struct PlaybackCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandMenu("Воспроизведение") {
            // Space itself is handled by `SpaceKey`: as a menu shortcut it would eat spaces
            // typed into the search field.
            Button(app.player.isPlaying ? "Пауза" : "Воспроизвести") { app.player.togglePlay() }
            Button("Следующий трек") { app.player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Предыдущий трек") { app.player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button(likeTitle) { if let t = app.player.current { app.toggleLike(t) } }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(app.player.current == nil || !app.isSignedIn)
            Button("Не нравится, дальше") { app.player.dislikeCurrent() }
                .disabled(app.player.current == nil)
            Divider()
            Picker("Повтор", selection: Binding(get: { app.player.repeatMode },
                                                set: { app.player.repeatMode = $0 })) {
                Text("Выключен").tag(Player.RepeatMode.off)
                Text("Все").tag(Player.RepeatMode.all)
                Text("Один трек").tag(Player.RepeatMode.one)
            }
            Divider()
            Button("Моя волна") { app.player.playWave(HomeScreen.myWave.id) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!app.isSignedIn)
        }
    }

    private var likeTitle: String {
        guard let t = app.player.current, app.isLiked(t) else { return "Мне нравится" }
        return "Убрать из «Мне нравится»"
    }
}

/// Space = play / pause while the main window has focus and no text is being edited.
enum SpaceKey {
    private static var monitor: Any?

    static func install(player: Player) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak player] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty,
                  let window = NSApp.keyWindow, window === NSApp.mainWindow, window.attachedSheet == nil,
                  !(window.firstResponder is NSText)
            else { return event }
            player?.togglePlay()
            return nil
        }
    }
}
