import SwiftUI
import WebKit

/// Yandex OAuth (implicit grant, the "Yandex Music for iOS" client): the token comes back in
/// the redirect URL's fragment.
enum YandexAuth {
    static let clientID = "23cabbbdc6cd418abb4b39c32c41195d"
    static let authorizeURL = URL(string:
        "https://oauth.yandex.ru/authorize?response_type=token&client_id=\(clientID)")!

    /// `access_token` from `#access_token=…&…` or `?access_token=…`.
    static func token(from url: URL) -> String? {
        guard let raw = url.absoluteString.removingPercentEncoding,
              let range = raw.range(of: "access_token=") else { return nil }
        let value = raw[range.upperBound...].prefix { $0 != "&" && $0 != "#" && $0 != "?" }
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// A pasted token (or a whole redirect URL) if it looks like an OAuth token.
    static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), let t = token(from: url) { s = t }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "=\"' "))
        guard s.count >= 20, s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return s
    }
}

/// Sign-in sheet: the Yandex login page in a web view, or a pasted token.
struct SignInSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""

    var body: some View {
        VStack(spacing: 0) {
            TokenWebView { complete($0) }
                .frame(minHeight: 380)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Или вставьте OAuth-токен")
                    .font(.headline)
                HStack {
                    SecureField("y0_AgAAAAB…", text: $pasted)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(submitPasted)
                    Button("Войти", action: submitPasted)
                        .keyboardShortcut(.defaultAction)
                        .disabled(YandexAuth.sanitize(pasted) == nil)
                }
                Text("Токен хранится только в Связке ключей на этом Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private func submitPasted() {
        guard let token = YandexAuth.sanitize(pasted) else { return }
        complete(token)
    }

    private func complete(_ token: String) {
        app.signIn(token: token)
        dismiss()
    }
}

/// WKWebView that watches every navigation for an `access_token`.
struct TokenWebView: NSViewRepresentable {
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: YandexAuth.authorizeURL))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onToken: (String) -> Void
        private var done = false
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        private func check(_ url: URL?) {
            guard !done, let url, let token = YandexAuth.token(from: url) else { return }
            done = true
            onToken(token)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, YandexAuth.token(from: url) != nil {
                check(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The fragment isn't part of the navigation action; read the final URL too.
            check(webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            check(webView.url)
        }
    }
}
