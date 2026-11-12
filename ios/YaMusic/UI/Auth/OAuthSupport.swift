import Foundation
import SwiftUI
import AuthenticationServices
import WebKit

/// Yandex Music's public "Yandex Music for iOS" OAuth client id (the one used by the
/// official app / MarshalX's python client). Implicit grant: the token comes back in the
/// URL fragment, so no client secret is needed.
enum YandexOAuth {
    static let clientID = "23cabbbdc6cd418abb4b39c32c41195d"
    static let authorizeURL = URL(string:
        "https://oauth.yandex.ru/authorize?response_type=token&client_id=\(clientID)")!
    /// The site the token is handed back to when using the web flow.
    static let landingURL = "https://music.yandex.ru/"
    /// Custom scheme we pass to ASWebAuthenticationSession. Yandex does not redirect to it,
    /// but the session still ends when the user lands on `landingURL`, whose fragment we read.
    static let callbackScheme = "yamusic"

    /// Pulls `access_token` out of either `#access_token=...&...` or `?access_token=...`.
    static func token(from url: URL) -> String? {
        guard let raw = url.absoluteString.removingPercentEncoding else { return nil }
        for marker in ["access_token="] {
            guard let range = raw.range(of: marker) else { continue }
            let rest = raw[range.upperBound...]
            let value = rest.prefix { $0 != "&" && $0 != "#" && $0 != "?" }
            let trimmed = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// A pasted token is fine if it looks like an OAuth token (no spaces, long enough).
    static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = token(from: URL(string: s) ?? URL(string: "https://x/#\(s)")!) { s = t }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "=\"' "))
        guard s.count >= 20, s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return s
    }
}

/// Drives ASWebAuthenticationSession and, if the fragment cannot be captured, falls back
/// to an in-app WKWebView sheet that watches the URL.
@Observable
final class OAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Mode { case webAuthSession, webView }

    var mode: Mode = .webAuthSession
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var anchor: UIWindow?

    func start(onToken: @escaping (String) -> Void) {
        errorMessage = nil
        isLoading = true
        let session = ASWebAuthenticationSession(
            url: YandexOAuth.authorizeURL,
            callbackURLScheme: YandexOAuth.callbackScheme
        ) { [weak self] url, error in
            guard let self else { return }
            self.isLoading = false
            if let error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                // Not supported / cannot start: go to the WKWebView path.
                self.mode = .webView
                self.errorMessage = "Не удалось открыть окно входа. Попробуйте ещё раз."
                return
            }
            if let url, let token = YandexOAuth.token(from: url) {
                onToken(token)
            } else {
                // Landed somewhere we cannot read (e.g. music.yandex.ru without a fragment
                // visible to us): let the user finish in the web view.
                self.mode = .webView
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        if !session.start() {
            isLoading = false
            mode = .webView
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        isLoading = false
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor { return anchor }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
            ?? ASPresentationAnchor()
        anchor = window
        return window
    }
}

/// WKWebView that watches every navigation for an `access_token`.
struct TokenWebView: UIViewRepresentable {
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.load(URLRequest(url: YandexOAuth.authorizeURL))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        private func check(_ url: URL?) {
            guard let url, let token = YandexOAuth.token(from: url) else { return }
            onToken(token)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, YandexOAuth.token(from: url) != nil {
                check(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Fragments are not part of the navigation action; read them after load too.
            check(webView.url)
            webView.evaluateJavaScript("location.href") { [weak self] value, _ in
                guard let self, let s = value as? String, let url = URL(string: s) else { return }
                self.check(url)
            }
        }
    }
}
