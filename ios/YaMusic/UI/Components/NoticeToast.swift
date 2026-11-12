import SwiftUI

/// Transient glass capsule for `player.notice`. Appears when the notice changes, hides after ~3 s.
/// Uses one sleeping task per notice; nothing runs while it is hidden.
struct NoticeToast: View {
    /// Post a VoiceOver announcement too (only one toast on screen should).
    var announces = true

    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text: String?

    var body: some View {
        ZStack {
            if let text {
                Label(text, systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 4)
                    .onTapGesture { hide() }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.2), value: text)
        .onChange(of: player.notice) { _, new in
            text = new
            if let new, announces { AccessibilityNotification.Announcement(new).post() }
        }
        .task(id: text) {
            guard text != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { hide() }
        }
    }

    private func hide() { text = nil }
}
