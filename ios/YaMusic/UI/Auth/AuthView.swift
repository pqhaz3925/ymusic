import SwiftUI

/// Sign-in sheet: OAuth token required. Two paths — "Войти через Яндекс" (web) or paste a token.
struct AuthView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flow = OAuthFlow()
    @State private var pastedToken = ""
    @State private var showPaste = false
    @State private var submitted = false
    @State private var showWebView = false
    @Namespace private var glass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    primaryButton
                    if let error = flow.errorMessage {
                        errorBanner(error)
                    }
                    pasteSection
                    footnote
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .backgroundExtensionEffect()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Вход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        flow.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showWebView) {
            webViewSheet
        }
        .onChange(of: flow.mode) { _, new in
            if new == .webView { showWebView = true }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.25))
                    .frame(width: 96, height: 96)
                    .blur(radius: 18)
                    .accessibilityHidden(true)
                Image(systemName: "music.note")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: showPaste)
            }
            .padding(.top, 0)

            VStack(spacing: 8) {
                Text("Войдите в Яндекс Музыку")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Для работы нужен OAuth-токен Яндекса. Он хранится только в Keychain на этом устройстве.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var primaryButton: some View {
        Button {
            flow.start { token in
                complete(with: token)
            }
        } label: {
            HStack(spacing: 10) {
                if flow.isLoading {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "person.badge.key.fill")
                }
                Text("Войти через Яндекс")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .foregroundStyle(.black)
        .disabled(flow.isLoading)
        .accessibilityHint("Откроет страницу Яндекса для получения токена")
        .glassEffectID("primary", in: glass)
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassEffect(.regular.tint(.orange.opacity(0.2)), in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { showPaste.toggle() }
            } label: {
                HStack {
                    Label("Вставить токен вручную", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showPaste ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Вставить токен вручную")
            .accessibilityValue(showPaste ? "Раскрыто" : "Свёрнуто")

            if showPaste {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("y0_AgAAAAB…", text: $pastedToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.callout, design: .monospaced))
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cornerRadius))
                        .accessibilityLabel("OAuth-токен")
                        .submitLabel(.go)
                        .onSubmit { submitPasted() }

                    HStack(spacing: 10) {
                        Button {
                            if let s = UIPasteboard.general.string {
                                pastedToken = s
                            }
                        } label: {
                            Label("Из буфера", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        Button("Войти") { submitPasted() }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                            .foregroundStyle(.black)
                            .disabled(YandexOAuth.sanitize(pastedToken) == nil)
                    }
                    .controlSize(.regular)

                    if submitted && YandexOAuth.sanitize(pastedToken) == nil {
                        Text("Токен слишком короткий или содержит пробелы.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var footnote: some View {
        Text("Токен можно получить на oauth.yandex.ru в разделе «Мои приложения» → токен приложения «Яндекс.Музыка для iOS».")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var webViewSheet: some View {
        NavigationStack {
            TokenWebView { token in
                showWebView = false
                complete(with: token)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Яндекс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showWebView = false }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }
    }

    private func submitPasted() {
        submitted = true
        guard let token = YandexOAuth.sanitize(pastedToken) else { return }
        complete(with: token)
    }

    private func complete(with token: String) {
        app.signIn(token: token)
        flow.cancel()
        dismiss()
    }
}
