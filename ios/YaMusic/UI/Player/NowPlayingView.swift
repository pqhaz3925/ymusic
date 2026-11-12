import AVKit
import SwiftUI

/// Full-screen player. Presented from `RootView` via `fullScreenCover(isPresented: $app.showNowPlaying)`.
///
/// Frequently changing state (elapsed time, buffering, download progress) is read only by small
/// subviews, so the screen as a whole re-renders on track/play-state changes only.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showQueue = false
    @State private var showSettings = false
    @State private var headerDrag: CGFloat = 0

    var body: some View {
        ZStack {
            // Static, pre-blurred backdrop: no live blur, no animated wave.
            BlurredCover(url: player.current?.coverURL(100))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let track = player.current {
                    content(track)
                } else {
                    empty
                }
            }
            .padding(.horizontal, Theme.gutter + 8)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .top) { NoticeToast(announces: false) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .modifier(ZoomFromMiniPlayer())
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 6)
            HStack {
                Button {
                    app.showNowPlaying = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Свернуть плеер")

                Spacer()

                if player.waveStationId != nil {
                    Label("Моя волна", systemImage: "waveform")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                }

                Spacer()
                // Balances the chevron so the wave badge stays centered.
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .contentShape(.rect)
        .offset(y: max(0, headerDrag) * 0.5)
        .gesture(
            DragGesture()
                .onChanged { headerDrag = $0.translation.height }
                .onEnded { v in
                    if v.translation.height > 100 || v.predictedEndTranslation.height > 260 {
                        app.showNowPlaying = false
                    }
                    withAnimation(.spring(duration: 0.3)) { headerDrag = 0 }
                }
        )
    }

    // MARK: Content

    private func content(_ track: Track) -> some View {
        VStack(spacing: 18) {
            CoverPager(track: track)
            titleRow(track)
            // The quality chip sits on the time row, centred between the two labels.
            GlassScrubber()
                .overlay(alignment: .bottom) {
                    QualityBadge(openSettings: { showSettings = true })
                        .offset(y: 11)
                }
            ControlDeck(track: track, showQueue: $showQueue)
                .padding(.top, 6)
        }
    }

    private func titleRow(_ track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                PlayerMarquee(text: track.fullTitle, style: .title2, weight: .bold)
                PlayerMarquee(text: track.artistLine, style: .title3, secondary: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(track.fullTitle), \(track.artistLine)")

            likeButton(track)
        }
    }

    private func likeButton(_ track: Track) -> some View {
        let liked = app.isLiked(track)
        return Button {
            app.toggleLike(track)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(liked ? Theme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : liked)
                .frame(width: 46, height: 46)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(liked ? "Убрать из «Мне нравится»" : "Добавить в «Мне нравится»")
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ничего не играет")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cover

/// The artwork. Swipe left / right to go to the next / previous track: the cover follows the
/// finger, flies out, and the new one comes in from the other side.
private struct CoverPager: View {
    let track: Track

    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragX: CGFloat = 0
    @State private var switches = 0

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CoverImage(url: track.coverURL(800), cornerRadius: 28)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                    .scaleEffect(player.isPlaying ? 1 : 0.88)
                    .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragX) / 45), anchor: .bottom)
                    .offset(x: dragX)
                    .opacity(1 - min(abs(dragX) / 420, 0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)
            .contentShape(.rect)
            // Simultaneous, so the system's pull-down-to-dismiss still works from the cover.
            .simultaneousGesture(swipe)
            .sensoryFeedback(.impact(weight: .light), trigger: switches)
            .accessibilityElement()
            .accessibilityLabel("Обложка")
            .accessibilityHint("Смахните влево или вправо, чтобы сменить трек")
            .accessibilityAction(named: "Следующий трек") { player.next() }
            .accessibilityAction(named: "Предыдущий трек") { player.previous() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                // Mostly-vertical drags belong to the dismiss gesture.
                guard abs(v.translation.width) > abs(v.translation.height) || dragX != 0 else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                let dx = v.translation.width, flick = v.predictedEndTranslation.width
                guard dragX != 0, abs(dx) > abs(v.translation.height) else { settle(); return }
                if dx < -90 || flick < -280 {
                    commit(forward: true)
                } else if dx > 90 || flick > 280 {
                    commit(forward: false)
                } else {
                    settle()
                }
            }
    }

    private func settle() {
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dragX = 0 }
    }

    private func commit(forward: Bool) {
        let out: CGFloat = forward ? -520 : 520
        switches += 1
        withAnimation(.easeIn(duration: 0.15)) { dragX = out }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if forward { player.next() } else { player.previous() }
            // Jump to the other side unseen, then slide the new cover in.
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump) { dragX = -out }
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { dragX = 0 }
        }
    }
}

// MARK: - Controls

/// Press feedback for glyph buttons that carry no background of their own.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// The control deck: two Liquid Glass capsules — transport on top, secondary actions under it.
/// Two glass surfaces in total (it used to be eight separate glass circles).
private struct ControlDeck: View {
    let track: Track
    @Binding var showQueue: Bool

    @Environment(Player.self) private var player

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                transport
                actions
            }
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 0) {
            skip("backward.fill", label: "Предыдущий трек") { player.previous() }
            PlayPauseButton()
            skip("forward.fill", label: "Следующий трек") { player.next() }
        }
        .padding(.horizontal, 10)
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    private func skip(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    // MARK: Secondary actions

    private var actions: some View {
        HStack(spacing: 0) {
            action("hand.thumbsdown", label: "Не рекомендовать") { player.dislikeCurrent() }
            repeatButton
            DownloadButton(track: track)
            AirPlayButton()
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
            action("list.bullet", label: "Очередь воспроизведения") { showQueue = true }
        }
        .padding(.horizontal, 8)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    private func action(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DeckIcon(systemName: symbol)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private var repeatButton: some View {
        let mode = player.repeatMode
        return Button {
            player.repeatMode = switch mode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        } label: {
            DeckIcon(systemName: mode == .one ? "repeat.1" : "repeat", active: mode != .off)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Повтор")
        .accessibilityValue(Self.title(mode))
    }

    private static func title(_ mode: Player.RepeatMode) -> String {
        switch mode {
        case .off: "Выключен"
        case .all: "Вся очередь"
        case .one: "Один трек"
        }
    }
}

/// One glyph of the secondary row: white, or accent when its state is on.
private struct DeckIcon: View {
    let systemName: String
    var active = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : .white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
    }
}

/// Solid accent disc inside the glass transport capsule; a spinner while the track is being fetched.
private struct PlayPauseButton: View {
    @Environment(Player.self) private var player

    var body: some View {
        Button { player.togglePlay() } label: {
            ZStack {
                Circle().fill(Theme.accent)
                if player.buffering {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.black)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(.circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
        .accessibilityValue(player.buffering ? "Загрузка" : "")
    }
}

// MARK: - Quality badge

/// "HQ · 256 кбит/с" capsule. Opens a menu with what is playing and a quick quality switch.
private struct QualityBadge: View {
    let openSettings: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(NetworkMonitor.self) private var network

    private var onCellular: Bool { network.isExpensive || network.link == .cellular }

    var body: some View {
        @Bindable var settings = settings
        let quality = app.quality
        Menu {
            Section(detailLine) {
                if player.isLocalPlayback {
                    Label("Играет с телефона", systemImage: "arrow.down.circle.fill")
                } else if quality.isDegraded {
                    Button {
                        quality.reset()
                    } label: {
                        Label("Сеть слабая — вернуть «\(quality.preferred.title)»",
                              systemImage: "arrow.uturn.up")
                    }
                }
            }
            Picker(selection: onCellular ? $settings.streamQualityCellular : $settings.streamQualityWiFi) {
                ForEach(AudioQuality.allCases.reversed()) { q in
                    Text(q.title).tag(q)
                }
            } label: {
                Text(onCellular ? "Качество в сотовой сети" : "Качество по Wi-Fi")
            }
            .pickerStyle(.menu)
            Button {
                openSettings()
            } label: {
                Label("Настройки качества", systemImage: "gearshape")
            }
        } label: {
            label
        }
        .onChange(of: settings.streamQualityWiFi) { quality.reset() }
        .onChange(of: settings.streamQualityCellular) { quality.reset() }
        .accessibilityLabel("Качество звука")
        .accessibilityValue(badgeText ?? "Неизвестно")
        .accessibilityHint("Открывает меню качества")
    }

    /// A small flat pill (not glass: it sits inside the scrubber). Lossless gets the accent
    /// colour and a waveform mark; a temporary downgrade is flagged in orange.
    private var label: some View {
        let lossless = player.currentQuality == .lossless
        let degraded = app.quality.isDegraded && !player.isLocalPlayback
        let color: Color = degraded ? .orange : lossless ? Theme.accent : .white.opacity(0.85)
        return HStack(spacing: 4) {
            if degraded {
                Image(systemName: "arrow.down.right")
            } else if lossless {
                Image(systemName: "waveform")
            }
            Text(badgeText ?? "Качество")
                .kerning(0.5)
        }
        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(color.opacity(0.14), in: .capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
        // Comfortable hit area around a deliberately small pill.
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(.rect)
    }

    /// "LOSSLESS", "HQ · 256", "SD · 192", "ЭКО · 64"; nil until the track starts.
    private var badgeText: String? {
        guard let q = player.currentQuality else { return nil }
        if q == .lossless { return "LOSSLESS" }
        if let kbps = player.currentBitrateKbps { return "\(q.badge) · \(kbps)" }
        return q.badge
    }

    private var detailLine: String {
        var parts: [String] = []
        if let q = player.currentQuality { parts.append(q.title) }
        let codec = PlayerFormat.codec(player.currentCodec)
        if !codec.isEmpty { parts.append(codec) }
        if let kbps = player.currentBitrateKbps { parts.append("\(kbps) кбит/с") }
        if !player.isLocalPlayback, let speed = app.quality.throughputKbps {
            parts.append("сеть " + PlayerFormat.speed(kbps: speed))
        }
        return parts.isEmpty ? "Сейчас играет" : parts.joined(separator: " · ")
    }
}

// MARK: - Deck items

/// Offline toggle for one track; reflects `TrackStore.state(of:)`.
private struct DownloadButton: View {
    let track: Track

    @Environment(TrackStore.self) private var store
    @State private var confirmRemove = false

    var body: some View {
        let state = store.state(of: track.id)
        Button {
            switch state {
            case nil, .failed: store.download([track])
            case .queued, .downloading: store.remove([track.id])
            case .downloaded: confirmRemove = true
            }
        } label: {
            icon(state)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label(state))
        .confirmationDialog("Удалить трек с телефона?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Удалить загрузку", role: .destructive) { store.remove([track.id]) }
        }
    }

    @ViewBuilder
    private func icon(_ state: DownloadState?) -> some View {
        switch state {
        case nil:
            Image(systemName: "arrow.down.to.line")
        case .failed:
            Image(systemName: "exclamationmark.arrow.circlepath")
                .foregroundStyle(.orange)
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .downloading(let p):
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, p)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
            }
            .frame(width: 20, height: 20)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        }
    }

    private func label(_ state: DownloadState?) -> String {
        switch state {
        case nil: "Скачать"
        case .failed: "Ошибка загрузки, повторить"
        case .queued: "В очереди на загрузку, отменить"
        case .downloading(let p): "Загрузка \(Int(p * 100))%, отменить"
        case .downloaded: "Скачан, удалить загрузку"
        }
    }
}

/// System AirPlay / route picker.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.9)
        v.activeTintColor = UIColor(Theme.accent)
        v.prioritizesVideoDevices = false
        v.backgroundColor = .clear
        v.accessibilityLabel = "AirPlay"
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
