import ArcaeaCore
import Foundation
import WebKit

@MainActor final class OfficialLoginBridge: NSObject, WKNavigationDelegate {
    private var views: [AccountRole: WKWebView] = [:]
    private var stores: [AccountRole: WKWebsiteDataStore] = [:]

    func webView(role: AccountRole) -> WKWebView {
        if let existing = views[role] { return existing }
        let store = WKWebsiteDataStore.nonPersistent()
        stores[role] = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        views[role] = view
        view.load(URLRequest(url: URL(string: "https://arcaea.lowiro.com/en/login")!))
        return view
    }

    func capture(role: AccountRole) async throws -> AccountSession {
        guard let view = views[role], let store = stores[role] else { throw OnlineError.expiredSession }
        let cookies = await store.httpCookieStore.allCookies()
        var jar = CookieJar()
        jar.merge(cookies.map { SessionCookie($0) })
        let userAgent = try? await view.evaluateJavaScript("navigator.userAgent") as? String
        return AccountSession(cookies: jar, browserUserAgent: userAgent)
    }

    func clear(role: AccountRole) async {
        views[role]?.stopLoading()
        if let store = stores[role] { await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) }
        views[role] = nil; stores[role] = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              ["arcaea.lowiro.com", "webapi.lowiro.com", "challenges.cloudflare.com"].contains(url.host ?? "") else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
}
