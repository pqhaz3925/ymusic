import SwiftUI

/// Playback queue. Tap a row to jump to it.
struct QueueSheet: View {
    @Environment(Player.self) private var player
    @Environment(TrackStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { i, track in
                        row(track, index: i)
                            .id(i)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if player.queue.isEmpty {
                        ContentUnavailableView("Очередь пуста", systemImage: "music.note.list")
                    }
                }
                .onAppear { proxy.scrollTo(player.index, anchor: .top) }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ track: Track, index: Int) -> some View {
        let isCurrent = index == player.index
        return Button {
            player.play(player.queue, startAt: index)
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: track.coverURL(100), cornerRadius: 8)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isCurrent {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.45))
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.fullTitle)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                    if !track.artistLine.isEmpty {
                        Text(track.artistLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if store.isDownloaded(track.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if track.durationMs > 0 {
                    Text(PlayerFormat.time(Double(track.durationMs) / 1000))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.fullTitle), \(track.artistLine)")
        .accessibilityValue([isCurrent ? "Сейчас играет" : nil,
                             store.isDownloaded(track.id) ? "Скачан" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
