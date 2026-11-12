#if DEBUG
import AppKit

/// Dev-only remote control for scripted test runs: a distributed notification named
/// `az.pqh.yamusic.debug` whose object is a command — `toggle`, `next`, `previous`,
/// `seek:<seconds>`, `wave`, `like`, `state` (prints), `signin`, `space`, `scroll-end`, `scroll:<dy>`, `show:<home|liked|history|settings|first-playlist|search:<query>>`.
enum DebugControl {
    static let show = Notification.Name("ym.debug.show")
    private static var token: (any NSObjectProtocol)?

    static func install(app: AppModel) {
        guard token == nil else { return }
        token = DistributedNotificationCenter.default().addObserver(
            forName: .init("az.pqh.yamusic.debug"), object: nil, queue: .main) { [weak app] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let app else { return }
                run(command, app: app)
            }
        }
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for sub in view.subviews { if let t = firstTable(in: sub) { return t } }
        return nil
    }

    private static func collect(_ view: NSView, into out: inout [NSScrollView]) {
        if let s = view as? NSScrollView { out.append(s) }
        for sub in view.subviews { collect(sub, into: &out) }
    }

    private static func run(_ command: String, app: AppModel) {
        let player = app.player
        switch command {
        case "toggle": player.togglePlay()
        case "next": player.next()
        case "previous": player.previous()
        case "wave": player.playWave(HomeScreen.myWave.id)
        case "like": if let t = player.current { app.toggleLike(t) }
        case "state":
            print("STATE track=\(player.current?.fullTitle ?? "-") index=\(player.index)/\(player.queue.count) "
                  + "playing=\(player.isPlaying) buffering=\(player.buffering) t=\(Int(player.elapsed))/\(Int(player.duration)) "
                  + "q=\(player.currentQuality?.rawValue ?? "-") liked=\(app.likedIds.count)")
            fflush(stdout)
        case "play-liked": if let l = app.cachedTracks(of: .liked) { player.play(l, startAt: 2) }
        case "signin": app.showAuth = true
        case "space":
            // A real Space key-down through the app's event queue (exercises `SpaceKey`).
            NSApp.activate()
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) else { break }
            w.makeKeyAndOrderFront(nil)
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: w.windowNumber, context: nil, characters: " ",
                                        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) {
                NSApp.postEvent(e, atStart: false)
            }
        case "scroll-end":
            // Last row of the first table in the main window (checks the player-bar inset).
            if let table = NSApp.windows.lazy.compactMap({ $0.contentView.flatMap(firstTable) }).first {
                table.scrollRowToVisible(table.numberOfRows - 1)
            }
        case _ where command.hasPrefix("scroll:"):
            // Scroll the main window's largest scroll view by N points.
            guard let dy = Double(command.dropFirst(7)), let root = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 })?.contentView else { break }
            var views: [NSScrollView] = []
            collect(root, into: &views)
            if let sv = views.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) {
                var p = sv.contentView.bounds.origin
                p.y += dy
                sv.contentView.scroll(to: p)
                sv.reflectScrolledClipView(sv.contentView)
            }
        case _ where command.hasPrefix("seek:"):
            if let t = Double(command.dropFirst(5)) { player.seek(to: t) }
        case _ where command.hasPrefix("show:"):
            NotificationCenter.default.post(name: show, object: String(command.dropFirst(5)))
        default: break
        }
    }
}
#endif
