import SwiftUI

/// App settings. Presented as a sheet from `RootView` (`app.showSettings`) and from the player.
struct SettingsView: View {
    /// Called for «Войти» instead of flipping both sheet flags at once, so the presenter can
    /// show the auth sheet after this one is gone. `nil` hides the account section.
    var onSignIn: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(TrackStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// `app.isSignedIn` reads the Keychain and is not observable; mirror it here.
    @State private var signedIn = false
    @State private var confirmSignOut = false
    @State private var confirmRemoveDownloads = false
    @State private var clearingCache = false

    private static let cacheLimits: [Int64] = [500 << 20, 1 << 30, 2 << 30, 5 << 30]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                if onSignIn != nil { accountSection }
                qualitySection($settings)
                offlineSection($settings)
                storageSection($settings)
                appearanceSection($settings)
                aboutSection
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { signedIn = app.isSignedIn }
        // A new choice deserves a fresh try at full quality.
        .onChange(of: settings.streamQualityWiFi) { app.quality.reset() }
        .onChange(of: settings.streamQualityCellular) { app.quality.reset() }
        .onChange(of: settings.adaptiveQuality) { app.quality.reset() }
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Аккаунт") {
            if signedIn {
                Label("Выполнен вход в Яндекс", systemImage: "person.crop.circle.fill")
                    .foregroundStyle(.primary)
                Button("Выйти", role: .destructive) { confirmSignOut = true }
                    .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Выйти", role: .destructive) {
                            app.signOut()
                            signedIn = app.isSignedIn
                        }
                    } message: {
                        Text("Скачанная музыка останется на телефоне.")
                    }
            } else {
                Label("Вход не выполнен", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
                Button("Войти") {
                    if let onSignIn {
                        onSignIn()
                    } else {
                        app.showSettings = false
                        app.showAuth = true
                    }
                }
            }
        }
    }

    // MARK: Quality

    private func qualitySection(_ b: Bindable<AppSettings>) -> some View {
        Section {
            QualityLink(title: "Wi-Fi", systemImage: "wifi", selection: b.streamQualityWiFi)
            QualityLink(title: "Сотовая сеть", systemImage: "antenna.radiowaves.left.and.right",
                        selection: b.streamQualityCellular)
            QualityLink(title: "Загрузки", systemImage: "arrow.down.circle", selection: b.downloadQuality)
            Toggle(isOn: b.adaptiveQuality) {
                Label("Адаптивное качество", systemImage: "dial.medium")
            }
            NetworkStatusRow()
        } header: {
            Text("Качество звука")
        } footer: {
            Text("При слабом соединении качество автоматически снижается, чтобы музыка не прерывалась, и возвращается, когда связь восстановится.")
        }
    }

    // MARK: Offline

    private func offlineSection(_ b: Bindable<AppSettings>) -> some View {
        Section {
            Toggle(isOn: b.offlineMode) {
                Label("Только скачанное", systemImage: "icloud.slash")
            }
            Toggle(isOn: b.autoDownloadLiked) {
                Label("Скачивать «Мне нравится» автоматически", systemImage: "heart.circle")
            }
            .onChange(of: settings.autoDownloadLiked) { _, on in
                // Catch up on likes made before the switch was turned on.
                if on, let liked = app.library.cached(.liked) { store.download(liked) }
            }
            Toggle(isOn: b.downloadOverCellular) {
                Label("Загрузки через сотовую сеть", systemImage: "antenna.radiowaves.left.and.right")
            }
            DownloadsSummaryRow()
            Button("Удалить все загрузки", role: .destructive) { confirmRemoveDownloads = true }
                .disabled(store.downloaded.isEmpty && store.states.isEmpty)
                .confirmationDialog("Удалить все загрузки?", isPresented: $confirmRemoveDownloads,
                                    titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) { store.removeAllDownloads() }
                } message: {
                    Text("Скачанные треки будут удалены с телефона. Их можно будет скачать снова.")
                }
        } header: {
            Text("Офлайн")
        } footer: {
            Text("«Только скачанное» не использует сеть для воспроизведения, даже когда она есть.")
        }
    }

    // MARK: Storage

    private func storageSection(_ b: Bindable<AppSettings>) -> some View {
        Section {
            LabeledContent("Кэш") {
                Text(PlayerFormat.bytes(store.cacheBytes)).monospacedDigit()
            }
            Picker("Лимит кэша", selection: b.cacheLimitBytes) {
                ForEach(Self.cacheLimits, id: \.self) { limit in
                    Text(PlayerFormat.bytes(limit)).tag(limit)
                }
            }
            Button {
                clearingCache = true
                Task {
                    await store.clearCache()
                    clearingCache = false
                }
            } label: {
                HStack {
                    Text("Очистить кэш")
                    Spacer()
                    if clearingCache { ProgressView() }
                }
            }
            .disabled(clearingCache)
        } header: {
            Text("Хранилище")
        } footer: {
            Text("В кэше хранятся недавно прослушанные треки. Скачанная музыка в кэш не входит и не удаляется при очистке.")
        }
    }

    // MARK: Appearance

    private func appearanceSection(_ b: Bindable<AppSettings>) -> some View {
        Section {
            Picker(selection: b.waveMotion) {
                ForEach(WaveMotion.allCases) { m in
                    Text(m.title).tag(m)
                }
            } label: {
                Label("Анимация волны", systemImage: "waveform")
            }
        } header: {
            Text("Оформление")
        } footer: {
            Text("Анимированная волна нагружает видеочип и расходует батарею. «Экономная» вдвое снижает частоту кадров, «Статичная» останавливает анимацию.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent("Версия", value: Self.version)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

// MARK: - Rows

/// Row that opens a quality chooser for one setting.
private struct QualityLink: View {
    let title: String
    let systemImage: String
    @Binding var selection: AudioQuality

    var body: some View {
        NavigationLink {
            QualityChoiceList(title: title, selection: $selection)
        } label: {
            LabeledContent {
                Text(selection.title)
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

/// Checkmark list over `AudioQuality.allCases` with each option's size/bitrate detail.
private struct QualityChoiceList: View {
    let title: String
    @Binding var selection: AudioQuality
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(AudioQuality.allCases.reversed()) { q in
                    Button {
                        selection = q
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.title).foregroundStyle(.primary)
                                Text(q.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if q == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(q == selection ? .isSelected : [])
                }
            } footer: {
                Text("Если сервер не отдаёт выбранное качество, играет ближайшее доступное.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Live link / requested quality / measured speed, plus the "weak network" note.
private struct NetworkStatusRow: View {
    @Environment(AppModel.self) private var app
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        let quality = app.quality
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Сеть") {
                Text(linkTitle)
            }
            LabeledContent("Запрашивается") {
                Text(network.isOnline ? quality.effective.title : "—")
            }
            if let kbps = quality.throughputKbps {
                LabeledContent("Скорость") {
                    Text(PlayerFormat.speed(kbps: kbps)).monospacedDigit()
                }
            }
            if quality.isDegraded {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Сеть слабая — качество временно снижено до «\(quality.effective.title)»")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Вернуть") { quality.reset() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }

    private var linkTitle: String {
        let base: String = switch network.link {
        case .none: "Нет сети"
        case .wifi: "Wi-Fi"
        case .cellular: "Сотовая"
        case .wired: "Проводная"
        case .other: network.isOnline ? (network.isExpensive ? "Сотовая" : "Есть") : "Нет сети"
        }
        return network.isConstrained && network.isOnline ? base + " · Экономия данных" : base
    }
}

/// Downloaded count + size, and progress of the running queue.
private struct DownloadsSummaryRow: View {
    @Environment(TrackStore.self) private var store

    var body: some View {
        let pending = store.states.values.reduce(into: 0) { n, s in
            switch s {
            case .queued, .downloading: n += 1
            default: break
            }
        }
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(PlayerFormat.bytes(store.downloadsBytes)).monospacedDigit()
                if pending > 0 {
                    Text("в очереди: \(pending)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(store.downloaded.isEmpty ? "Нет загрузок" : "Скачано: " + PlayerFormat.tracks(store.downloaded.count),
                  systemImage: "arrow.down.circle.fill")
        }
    }
}
