import SwiftUI

/// Content for `.tabViewBottomAccessory`. Adapts to the inline (minimized tab bar) placement.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Namespace private var zoomNamespace

    private var isInline: Bool { placement == .inline }

    var body: some View {
        Group {
            if let track = player.current {
                playing(track)
            } else {
                Text("Ничего не играет")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Ничего не играет")
            }
        }
        .onAppear { NowPlayingTransition.namespace = zoomNamespace }
    }

    private func playing(_ track: Track) -> some View {
        HStack(spacing: isInline ? 8 : 12) {
            MiniTrackInfo(track: track, isInline: isInline, namespace: zoomNamespace)

            if !isInline {
                let liked = app.isLiked(track)
                Button {
                    app.toggleLike(track)
                } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Theme.accent : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Убрать из «Мне нравится»" : "Добавить в «Мне нравится»")
            }

            Button {
                player.togglePlay()
            } label: {
                ZStack {
                    if player.buffering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
            .accessibilityValue(player.buffering ? "Загрузка" : "")
        }
        .padding(.horizontal, isInline ? 8 : 16)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { MiniProgressLine() }
    }
}

/// Cover + titles. Tap opens the player; a horizontal swipe changes the track (left = next,
/// right = previous), with the titles following the finger.
private struct MiniTrackInfo: View {
    let track: Track
    let isInline: Bool
    let namespace: Namespace.ID

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @State private var dragX: CGFloat = 0
    @State private var switches = 0

    var body: some View {
        HStack(spacing: isInline ? 8 : 12) {
            CoverImage(url: track.coverURL(100), cornerRadius: isInline ? 6 : 8)
                .frame(width: isInline ? 28 : 40, height: isInline ? 28 : 40)
                .matchedTransitionSource(id: NowPlayingTransition.sourceID, in: namespace)

            Group {
                if isInline {
                    PlayerMarquee(text: track.fullTitle, style: .subheadline, weight: .semibold)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        PlayerMarquee(text: track.fullTitle, style: .subheadline, weight: .semibold)
                        if !track.artistLine.isEmpty {
                            Text(track.artistLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .offset(x: dragX)
            .opacity(1 - min(abs(dragX) / 110, 1))
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { app.showNowPlaying = true }
        .gesture(swipe)
        .sensoryFeedback(.impact(weight: .light), trigger: switches)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(track.fullTitle), \(track.artistLine)")
        .accessibilityHint("Открыть плеер. Смахните влево или вправо, чтобы сменить трек")
        .accessibilityAction { app.showNowPlaying = true }
        .accessibilityAction(named: "Следующий трек") { player.next() }
        .accessibilityAction(named: "Предыдущий трек") { player.previous() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) || dragX != 0 else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                let dx = v.translation.width, flick = v.predictedEndTranslation.width
                if dragX != 0, dx < -48 || flick < -160 {
                    commit(forward: true)
                } else if dragX != 0, dx > 48 || flick > 160 {
                    commit(forward: false)
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { dragX = 0 }
                }
            }
    }

    private func commit(forward: Bool) {
        let out: CGFloat = forward ? -140 : 140
        switches += 1
        withAnimation(.easeIn(duration: 0.12)) { dragX = out }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            if forward { player.next() } else { player.previous() }
            // New titles come in from the opposite side.
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump) { dragX = -out }
            withAnimation(.spring(duration: 0.38, bounce: 0.2)) { dragX = 0 }
        }
    }
}

/// Separate view so only this line re-renders on `player.progress` ticks (~2 Hz), not the whole accessory.
private struct MiniProgressLine: View {
    @Environment(Player.self) private var player

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.accent)
                .frame(width: geo.size.width * min(1, max(0, player.progress)), height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
