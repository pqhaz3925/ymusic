import SwiftUI

/// Async cover art with a soft placeholder. Shared by every screen.
struct CoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default: Rectangle().fill(.white.opacity(0.08))
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}
