import SwiftUI

/// Toolbar account entry: opens Settings (account, quality, offline, storage).
struct AccountButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let signedIn = app.isSignedIn
        Button {
            app.showSettings = true
        } label: {
            Image(systemName: signedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(signedIn ? Theme.accent : Color.primary)
        }
        .accessibilityLabel("Профиль и настройки")
        .accessibilityHint("Открывает настройки")
        .accessibilityValue(signedIn ? "Выполнен вход" : "Вход не выполнен")
    }
}
