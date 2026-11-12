import SwiftUI

/// One track in a list: cover, title, artist, explicit badge, now-playing mark, download
/// state and a «…» menu (same items as the context menu).
///
/// Kept cheap for long lists: download state, the playing animation and the menu each live
/// in their own small view, so a progress tick or a play/pause re-renders only that piece.
struct TrackRow: View {
    let track: Track
    var showCover: Bool = true
    /// Greyed out and not tappable. `nil` = automatic: offline and no local copy.
    var dimmed: Bool? = nil
    var onTap: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store

    /// Short-circuits so that online rows never observe the store.
    private var isDimmed: Bool {
        if let dimmed { return dimmed }
        return app.isOffline && !store.hasLocalCopy(track.id)
    }

    var body: some View {
        let current = player.current?.id == track.id
        let off = isDimmed
        HStack(spacing: 6) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 12) {
                    leading(current: current)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(track.fullTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(current ? Theme.accent : .primary)
                                .lineLimit(1)
                            if track.explicit { ExplicitBadge() }
                        }
                        Text(track.artistLine)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(off)
            .accessibilityLabel(accessibilityText(current: current, off: off))

            TrackDownloadBadge(trackId: track.id)

            Menu {
                TrackMenuItems(track: track, unavailable: off)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 30, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Действия с треком")
        }
        .opacity(off ? 0.4 : 1)
        .contextMenu {
            TrackMenuItems(track: track, unavailable: off)
        }
    }

    @ViewBuilder
    private func leading(current: Bool) -> some View {
        if showCover {
            CoverImage(url: track.coverURL(100), cornerRadius: 6)
                .frame(width: 48, height: 48)
                .overlay {
                    if current {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45))
                            NowPlayingGlyph()
                        }
                    }
                }
        } else {
            Color.clear
                .frame(width: 24, height: 24)
                .overlay {
                    if current { NowPlayingGlyph() }
                }
        }
    }

    private func accessibilityText(current: Bool, off: Bool) -> String {
        var s = "\(track.fullTitle), \(track.artistLine)"
        if current { s += ", сейчас играет" }
        if off { s += ", недоступен без сети" }
        return s
    }
}

/// Menu / context-menu items for a track. A separate view so the row itself doesn't
/// observe likes or download state.
struct TrackMenuItems: View {
    let track: Track
    /// Offline and not on disk: queueing it would only fail.
    var unavailable: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store

    var body: some View {
        Button {
            player.playNext([track])
        } label: {
            Label("Играть следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        .disabled(unavailable)

        Button {
            player.addToQueue([track])
        } label: {
            Label("В очередь", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
        .disabled(unavailable)

        let liked = app.isLiked(track)
        Button {
            app.toggleLike(track)
        } label: {
            Label(liked ? "Убрать из «Мне нравится»" : "Мне нравится",
                  systemImage: liked ? "heart.slash" : "heart")
        }

        switch store.state(of: track.id) {
        case .downloaded?:
            Button(role: .destructive) {
                store.remove([track.id])
            } label: {
                Label("Удалить загрузку", systemImage: "trash")
            }
        case .queued?, .downloading?:
            Button(role: .destructive) {
                store.remove([track.id])
            } label: {
                Label("Отменить загрузку", systemImage: "xmark.circle")
            }
        case .failed?:
            Button {
                store.download([track])
            } label: {
                Label("Повторить загрузку", systemImage: "arrow.clockwise")
            }
        case nil:
            Button {
                store.download([track])
            } label: {
                Label("Скачать", systemImage: "arrow.down.circle")
            }
        }

        Button {
            player.playWave("track:\(track.id)")
        } label: {
            Label("Волна по треку", systemImage: "dot.radiowaves.left.and.right")
        }
        .disabled(app.isOffline)
    }
}

/// Tiny trailing download state of one track. Observes only that track's state.
struct TrackDownloadBadge: View {
    let trackId: String
    @Environment(TrackStore.self) private var store

    var body: some View {
        switch store.state(of: trackId) {
        case .downloaded?:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .accessibilityLabel("Скачан")
        case .downloading(let p)?:
            CollectionProgressRing(progress: p, lineWidth: 2)
                .frame(width: 13, height: 13)
                .accessibilityElement()
                .accessibilityLabel("Скачивается")
                .accessibilityValue("\(Int(p * 100))%")
        case .queued?:
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel("В очереди на скачивание")
        case .failed?:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .accessibilityLabel("Не удалось скачать")
        case nil:
            EmptyView()
        }
    }
}

/// Static determinate ring (no implicit animation, so progress ticks stay cheap).
struct CollectionProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, min(progress, 1)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Now-playing mark; the only part of a row that observes `isPlaying`.
private struct NowPlayingGlyph: View {
    @Environment(Player.self) private var player

    var body: some View {
        EqualizerBars(animating: player.isPlaying)
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 14, height: 14)
            .background(.white.opacity(0.15), in: .rect(cornerRadius: 2.5))
            .accessibilityLabel("Ненормативная лексика")
    }
}

/// Now-playing equalizer. An SF Symbol effect: animated by the render server, so the
/// view body is not re-evaluated per frame.
struct EqualizerBars: View {
    var animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .symbolEffect(.variableColor.iterative, isActive: animating && !reduceMotion)
            .accessibilityHidden(true)
    }
}

/// Formats milliseconds as m:ss.
func formatDuration(ms: Int) -> String {
    let s = max(0, ms) / 1000
    return String(format: "%d:%02d", s / 60, s % 60)
}
