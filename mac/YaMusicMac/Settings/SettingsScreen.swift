import SwiftUI

/// ⌘, window: quality, wave animation, cache, account.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(TrackStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    @State private var clearing = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Воспроизведение") {
                // One choice on the Mac: also used on a tethered (expensive) link.
                Picker("Качество", selection: Binding(get: { settings.streamQualityWiFi }, set: {
                    settings.streamQualityWiFi = $0
                    settings.streamQualityCellular = $0
                })) {
                    ForEach(AudioQuality.allCases) { q in
                        Text(q.title).tag(q)
                    }
                }
                Text(settings.streamQualityWiFi.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $settings.adaptiveQuality) {
                    Text("Адаптивное качество")
                    Text("Временно понижать качество, если сеть не успевает")
                }
            }

            Section("Моя волна") {
                Picker("Анимация фона", selection: $settings.waveMotion) {
                    ForEach(WaveMotion.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
            }

            Section("Хранилище") {
                LabeledContent("Кэш треков") {
                    HStack(spacing: 12) {
                        Text(Fmt.bytes(store.cacheBytes)).monospacedDigit()
                        Button("Очистить") {
                            clearing = true
                            Task {
                                await store.clearCache()
                                clearing = false
                            }
                        }
                        .disabled(clearing || store.cacheBytes == 0)
                    }
                }
            }

            Section("Аккаунт") {
                if app.isSignedIn {
                    LabeledContent("Яндекс Музыка", value: "Вход выполнен")
                    Button("Выйти", role: .destructive) { app.signOut() }
                } else {
                    LabeledContent("Яндекс Музыка", value: "Вход не выполнен")
                    Button("Войти…") {
                        openWindow(id: "main")
                        app.showAuth = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
