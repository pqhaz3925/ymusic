import SwiftUI

/// Glass player bar pinned to the bottom of the detail column.
/// Only `Scrubber` reads `player.elapsed`; everything else changes on track / state changes.
struct PlayerBar: View {
    @Environment(Player.self) private var player

    var body: some View {
        if player.current != nil || player.waveStationId != nil {
            HStack(spacing: 18) {
                TrackInfo()
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 300, alignment: .leading)
                VStack(spacing: 2) {
                    Transport()
                    Scrubber()
                }
                .frame(maxWidth: 560)
                StreamInfo()
                    .frame(minWidth: 90, idealWidth: 130, maxWidth: 160, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct TrackInfo: View {
    @Environment(Player.self) private var player
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(url: player.current?.coverURL(200), cornerRadius: 7)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.fullTitle ?? "Подбираем музыку…")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(player.current?.artistLine ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let t = player.current {
                let liked = app.isLiked(t)
                Button { app.toggleLike(t) } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Theme.accent : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(liked ? "Убрать из «Мне нравится»" : "Мне нравится")
            }
        }
    }
}

private struct Transport: View {
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 22) {
            Button { cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Theme.accent)
            }
            .help(repeatHelp)
            .disabled(player.waveStationId != nil)

            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .help("Предыдущий трек")
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .frame(width: 26)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(player.isPlaying ? "Пауза" : "Воспроизвести")
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .help("Следующий трек")

            Button { player.dislikeCurrent() } label: { Image(systemName: "hand.thumbsdown") }
                .foregroundStyle(.secondary)
                .help("Не нравится")
                .opacity(player.waveStationId != nil ? 1 : 0)
                .disabled(player.waveStationId == nil)
        }
        .font(.system(size: 15))
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: "Повтор выключен"
        case .all: "Повтор всех"
        case .one: "Повтор трека"
        }
    }

    private func cycleRepeat() {
        player.repeatMode = switch player.repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// The only view that follows the playhead (~2 updates a second while playing).
private struct Scrubber: View {
    @Environment(Player.self) private var player
    @State private var dragging: Double?

    var body: some View {
        let duration = max(player.duration, 1)
        let shown = min(dragging ?? player.elapsed, duration)
        HStack(spacing: 8) {
            Text(Fmt.time(shown))
                .frame(width: 44, alignment: .trailing)
            Slider(value: Binding(get: { shown }, set: { dragging = $0 }),
                   in: 0...duration) { editing in
                if !editing, let v = dragging {
                    player.seek(to: v)
                    dragging = nil
                }
            }
            .controlSize(.mini)
            .disabled(player.current == nil || player.duration <= 0)
            Text(Fmt.time(player.duration))
                .frame(width: 44, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// Quality badge, buffering, notices.
private struct StreamInfo: View {
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            if player.buffering {
                ProgressView().controlSize(.small)
                    .help("Загрузка…")
            }
            if let notice = player.notice {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                    .help(notice)
            }
            if let q = player.currentQuality {
                Text(q.badge)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(q == .lossless ? Theme.accent : .secondary)
                    .overlay(Capsule().strokeBorder(q == .lossless ? Theme.accent.opacity(0.7) : Color.secondary.opacity(0.5)))
                    .help(detail(q))
            }
        }
    }

    private func detail(_ q: AudioQuality) -> String {
        var parts = [q.title]
        if !player.currentCodec.isEmpty { parts.append(player.currentCodec) }
        if let kbps = player.currentBitrateKbps { parts.append("\(kbps) кбит/с") }
        if player.isLocalPlayback { parts.append("из кэша") }
        return parts.joined(separator: " · ")
    }
}
