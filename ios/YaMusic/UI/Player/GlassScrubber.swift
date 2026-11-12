import SwiftUI

/// Seek bar with a Liquid Glass thumb. Drag or tap to seek; VoiceOver adjusts in 10 s steps.
struct GlassScrubber: View {
    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragFraction: Double?
    @State private var isDragging = false
    @State private var width: CGFloat = 0

    private let trackHeight: CGFloat = 6
    private let thumb: CGFloat = 22

    private var fraction: Double { min(1, max(0, dragFraction ?? player.progress)) }
    private var shownElapsed: TimeInterval { dragFraction.map { $0 * player.duration } ?? player.elapsed }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: trackHeight)
                Capsule().fill(.white.opacity(0.9))
                    .frame(width: max(0, fraction * width), height: trackHeight)
                Color.clear
                    .frame(width: thumb, height: thumb)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .scaleEffect(isDragging ? 1.35 : 1)
                    .offset(x: fraction * width - thumb / 2)
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.4), value: isDragging)
            }
            .frame(height: 36)
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging = true
                        dragFraction = clamp(v.location.x)
                    }
                    .onEnded { v in
                        let f = clamp(v.location.x)
                        dragFraction = f
                        isDragging = false
                        player.seek(to: f * player.duration)
                        // Hold the thumb in place until the player reports the new position.
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            if !isDragging { dragFraction = nil }
                        }
                    }
            )

            HStack {
                Text(PlayerFormat.time(shownElapsed))
                Spacer()
                Text("-" + PlayerFormat.time(max(0, player.duration - shownElapsed)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Перемотка")
        .accessibilityValue("\(PlayerFormat.time(player.elapsed)) из \(PlayerFormat.time(player.duration))")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 10
            switch direction {
            case .increment: player.seek(to: min(player.duration, player.elapsed + step))
            case .decrement: player.seek(to: max(0, player.elapsed - step))
            @unknown default: break
            }
        }
    }

    private func clamp(_ x: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }
}
