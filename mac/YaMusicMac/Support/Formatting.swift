import Foundation
import SwiftUI

/// Small text formatters for the Mac UI.
enum Fmt {
    /// `3:07`, `1:02:45`.
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func duration(ms: Int) -> String { ms > 0 ? time(Double(ms) / 1000) : "" }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "1 трек", "3 трека", "12 треков".
    static func tracks(_ n: Int) -> String { "\(n) " + plural(n, "трек", "трека", "треков") }

    /// "2 ч 14 мин" / "47 мин".
    static func total(ms: Int) -> String {
        let minutes = ms / 60_000
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}

extension Destination {
    var title: String {
        switch self {
        case .liked: "Мне нравится"
        case .history: "История"
        case .downloads: "Скачанное"
        case .playlist(let p): p.title
        case .album(let a): a.title
        case .artist(let a): a.name
        }
    }

    var kind: String {
        switch self {
        case .liked, .history, .downloads: "Коллекция"
        case .playlist: "Плейлист"
        case .album: "Альбом"
        case .artist: "Исполнитель"
        }
    }

    var subtitle: String? {
        switch self {
        case .playlist(let p): p.ownerName
        case .album(let a):
            ([a.artists.map(\.name).joined(separator: ", ")] + (a.year.map { ["\($0)"] } ?? []))
                .filter { !$0.isEmpty }.joined(separator: " · ")
        default: nil
        }
    }

    func coverURL(_ size: Int) -> URL? {
        switch self {
        case .playlist(let p): p.coverURL(size)
        case .album(let a): a.coverURL(size)
        case .artist(let a): a.coverURL(size)
        default: nil
        }
    }

    /// Placeholder symbol for destinations without art.
    var symbol: String {
        switch self {
        case .liked: "heart.fill"
        case .history: "clock.fill"
        case .downloads: "arrow.down.circle.fill"
        case .playlist: "music.note.list"
        case .album: "square.stack"
        case .artist: "music.mic"
        }
    }
}

/// Yandex-yellow capsule with black text; keeps its colour in inactive windows.
struct AccentButtonStyle: ButtonStyle {
    /// Neutral variant for secondary actions.
    var secondary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(secondary ? Color.white : .black)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background((secondary ? Color.white.opacity(0.14) : Theme.accent)
                .opacity(configuration.isPressed ? 0.75 : 1), in: .capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.capsule)
    }
}
