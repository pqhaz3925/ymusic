import SwiftUI

// Shared pieces of the collection screens: text helpers, offline-aware playback,
// empty/error states, symbol tiles and the list download controls.

/// Loading state of a list screen.
enum ListLoadPhase: Equatable {
    case loading, loaded
    case failed(String)
}

enum CollectionText {
    /// Russian plural form for `n`: one (1, 21), few (2–4, 22–24), many (0, 5–20, 25…).
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m100 = abs(n) % 100, m10 = abs(n) % 10
        if (11...14).contains(m100) { return many }
        switch m10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n) \(plural(n, one, few, many))"
    }

    static func tracks(_ n: Int) -> String { count(n, "трек", "трека", "треков") }

    /// "310 МБ", "1,4 ГБ".
    static func bytes(_ b: Int64) -> String {
        let mb = Double(b) / 1_048_576
        if mb < 1 { return b > 0 ? "<1 МБ" : "0 МБ" }
        if mb < 1000 { return "\(Int(mb.rounded())) МБ" }
        let gb = (mb / 1024).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ru_RU")))
        return "\(gb) ГБ"
    }

    /// User-facing reason a list could not be loaded.
    static func loadError(_ error: Error, offline: Bool) -> String {
        offline ? "Нет сети, а этот список ещё не сохранён на устройстве."
                : error.localizedDescription
    }
}

/// Offline-aware queueing: offline, only tracks with a local copy go into the queue.
enum CollectionPlayback {
    /// Plays `tracks` from `startAt`. Offline, unavailable tracks are skipped and playback
    /// starts at `startAt` or the next available track after it.
    static func play(_ tracks: [Track], startAt: Int = 0, shuffled: Bool = false,
                     player: Player, store: TrackStore, offline: Bool) {
        var queue = tracks
        var start = startAt
        if offline {
            queue = []
            start = 0
            for (i, t) in tracks.enumerated() where store.hasLocalCopy(t.id) {
                if i < startAt { start = queue.count + 1 }
                queue.append(t)
            }
            start = min(start, max(queue.count - 1, 0))
        }
        guard !queue.isEmpty else { return }
        if shuffled {
            player.play(queue.shuffled())
        } else {
            player.play(queue, startAt: start)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct CollectionErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text("Не удалось загрузить").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Повторить", action: retry)
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

/// Gradient tile with a white SF Symbol, for lists that have no cover.
struct CollectionSymbolTile: View {
    let symbol: String
    let colors: [Color]
    var cornerRadius: CGFloat = 16
    var symbolSize: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    static let liked: [Color] = [Color(red: 1.0, green: 0.42, blue: 0.48), Color(red: 0.86, green: 0.08, blue: 0.3)]
    static let history: [Color] = [Color(red: 0.42, green: 0.45, blue: 1.0), Color(red: 0.55, green: 0.2, blue: 0.85)]
    static let downloads: [Color] = [Color(red: 0.2, green: 0.8, blue: 0.45), Color(red: 0.05, green: 0.55, blue: 0.45)]
}

// MARK: - Download controls

/// "Скачать" → "12 из 40" → "Скачано" for a whole list. Observes the store itself so
/// progress ticks re-render only this button, never the list.
struct ListDownloadButton: View {
    let tracks: [Track]

    @Environment(TrackStore.self) private var store
    @State private var dialog: Dialog?

    private enum Dialog { case stop, remove }
    private struct Tally { var done = 0, active = 0, failed = 0 }

    private var tally: Tally {
        let states = store.states
        var t = Tally()
        for track in tracks {
            switch states[track.id] {
            case .downloaded?: t.done += 1
            case .queued?, .downloading?: t.active += 1
            case .failed?: t.failed += 1
            case nil: break
            }
        }
        return t
    }

    var body: some View {
        let t = tally
        let total = tracks.count
        Button {
            if total > 0, t.done == total {
                dialog = .remove
            } else if t.active > 0 {
                dialog = .stop
            } else {
                store.download(tracks)
            }
        } label: {
            label(t, total: total)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .buttonStyle(.glass)
        .disabled(tracks.isEmpty)
        .confirmationDialog(dialogTitle(t, total: total),
                            isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } }),
                            titleVisibility: .visible) {
            switch dialog {
            case .stop?:
                Button("Остановить загрузку") { store.remove(pendingIds()) }
                Button("Удалить скачанное из списка", role: .destructive) { store.remove(tracks.map(\.id)) }
            case .remove?:
                Button("Удалить загрузки", role: .destructive) { store.remove(tracks.map(\.id)) }
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func label(_ t: Tally, total: Int) -> some View {
        if total > 0, t.done == total {
            Label("Скачано", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if t.active > 0 {
            HStack(spacing: 8) {
                CollectionProgressRing(progress: total > 0 ? Double(t.done) / Double(total) : 0, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                Text("\(t.done) из \(total)")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Скачивается: \(t.done) из \(total)")
        } else if t.failed > 0 {
            Label(t.done > 0 ? "Докачать · \(t.done) из \(total)" : "Повторить загрузку",
                  systemImage: "exclamationmark.arrow.circlepath")
        } else if t.done > 0 {
            Label("Скачать · \(t.done) из \(total)", systemImage: "arrow.down.circle")
        } else {
            Label("Скачать", systemImage: "arrow.down.circle")
        }
    }

    private func dialogTitle(_ t: Tally, total: Int) -> String {
        switch dialog {
        case .stop?: "Скачано \(t.done) из \(total)"
        default: "Удалить \(CollectionText.tracks(total)) с устройства? Без сети их будет не послушать."
        }
    }

    private func pendingIds() -> [String] {
        tracks.compactMap { track in
            switch store.state(of: track.id) {
            case .queued?, .downloading?: track.id
            default: nil
            }
        }
    }
}

/// Size of all downloads plus «Удалить всё», for the downloads screen.
struct DownloadsManagerBar: View {
    @Environment(TrackStore.self) private var store
    @State private var confirm = false

    var body: some View {
        let bytes = store.downloadsBytes
        HStack(spacing: 10) {
            Label("\(CollectionText.bytes(bytes)) на устройстве", systemImage: "internaldrive")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
            Spacer(minLength: 8)
            Button(role: .destructive) {
                confirm = true
            } label: {
                Label("Удалить всё", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .tint(.red)
            .disabled(store.downloaded.isEmpty)
        }
        .confirmationDialog("Удалить все скачанные треки?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { store.removeAllDownloads() }
        } message: {
            Text("Освободится \(CollectionText.bytes(bytes)). Без сети их будет не послушать.")
        }
    }
}
