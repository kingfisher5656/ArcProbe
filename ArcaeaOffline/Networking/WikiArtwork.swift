import ArcaeaCore
import Foundation
import Observation
import WebKit

struct WikiJacket: Codable, Equatable {
    let filePage: String
    let difficulties: String
}
struct WikiSongArticle: Codable {
    /// A page can describe more than one song ID ("Last" also carries "lasteternity").
    let songIDs: [String]
    let jackets: [WikiJacket]
    private static let names = ["past", "present", "future", "beyond", "eternal"]
    private static let suffixes = ["pst", "prs", "ftr", "byd", "etr"]
    private static func labels(_ jacket: WikiJacket) -> [String] {
        jacket.difficulties.lowercased().split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    /// "…/File:Songs_last_byd.jpg" → "songs_last_byd"
    private static func fileName(_ jacket: WikiJacket) -> String {
        let last = jacket.filePage.split(separator: "/").last.map(String.init) ?? ""
        let name = (last.removingPercentEncoding ?? last).lowercased()
        guard let colon = name.firstIndex(of: ":") else { return "" }
        return String(name[name.index(after: colon)...].split(separator: ".").first ?? "")
    }
    private static func only(_ jackets: [WikiJacket]) -> WikiJacket? {
        Set(jackets.map(\.filePage)).count == 1 ? jackets.first : nil
    }
    func jacket(for chart: ChartID) -> WikiJacket? {
        let name = Self.names[chart.difficulty.rawValue]
        // 1. A tab that names this difficulty.
        let explicit = jackets.filter { Self.labels($0).contains(name) }
        if !explicit.isEmpty { return Self.only(explicit) }
        // 2. An unlabelled single jacket covers the song.
        if Set(jackets.map(\.filePage)).count == 1, let single = jackets.first, single.difficulties.isEmpty { return single }
        // 3. Tabs named for something else ("Moment", "Day", "English"): go by the wiki's file names.
        //    Songs_<id>_byd is that song's Beyond jacket; Songs_<id> is its default one.
        let base = "songs_" + chart.songID.lowercased()
        let suffixed = jackets.filter { Self.fileName($0) == base + "_" + Self.suffixes[chart.difficulty.rawValue] }
        if !suffixed.isEmpty { return Self.only(suffixed) }
        // Never infer a Beyond image from a tab that is labelled for other difficulties.
        let standard = jackets.filter { Self.fileName($0) == base && Set(Self.labels($0)).isDisjoint(with: Self.names) }
        return Self.only(standard)
    }
}

enum WikiArtworkError: LocalizedError {
    case unavailable, unsupported, cancelled
    var errorDescription: String? {
        switch self {
        case .unavailable: "The wiki did not load. Existing covers are retained. If a browser check is shown, complete it yourself, then retry."
        case .unsupported: "The wiki page could not be matched safely to this song and difficulty. Existing covers are retained."
        case .cancelled: "Wiki download stopped. Completed covers are retained."
        }
    }
}

@MainActor @Observable final class WikiArtwork: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let webView: WKWebView
    private(set) var running = false
    private(set) var status = "Download original wiki jackets for imported songs. Keep this screen open."
    private var task: Task<Void, Never>?
    private var currentNavigation: WKNavigation?
    private var navigation: CheckedContinuation<Void, Error>?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var download: WKDownload?
    private var downloadedFile: URL?
    private var timeout: Task<Void, Never>?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }
    static func wikiURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.host == "arcaea.miraheze.org", url.path.hasPrefix("/wiki/"), url.user == nil, url.password == nil, url.port == nil, url.query == nil else { return nil }
        return url
    }
    static func imageURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.host == "static.wikitide.net", url.path.hasPrefix("/arcaeawiki/"), !url.path.contains("/thumb/"), url.user == nil, url.password == nil, url.port == nil, url.query == nil, ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)); self?.fail(WikiArtworkError.unavailable) } catch {}
        }
    }
    private func fail(_ error: Error) {
        timeout?.cancel(); timeout = nil
        currentNavigation = nil
        webView.stopLoading()
        navigation?.resume(throwing: error); navigation = nil
        downloadContinuation?.resume(throwing: error); downloadContinuation = nil
        download?.cancel { _ in }; download = nil
        if let file = downloadedFile { try? FileManager.default.removeItem(at: file) }; downloadedFile = nil
    }
    func stop() { task?.cancel(); fail(WikiArtworkError.cancelled) }
    private func load(_ url: URL) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation; armTimeout(); currentNavigation = webView.load(URLRequest(url: url))
        }
        try Task.checkCancellation()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        currentNavigation = nil
        timeout?.cancel(); timeout = nil
        self.navigation?.resume(); self.navigation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === currentNavigation { fail(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === currentNavigation { fail(error) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == false { decisionHandler(.cancel); return }
        decisionHandler(action.request.url.flatMap { Self.wikiURL($0.absoluteString) } == nil ? .cancel : .allow)
    }
    private func original(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let file: URL = try await withCheckedThrowingContinuation { continuation in
            downloadContinuation = continuation; armTimeout()
            webView.startDownload(using: URLRequest(url: url)) { [weak self] value in
                guard let self else { value.cancel { _ in }; return }
                guard self.downloadContinuation != nil else { value.cancel { _ in }; return }
                self.download = value; value.delegate = self
            }
        }
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8 * 1024 * 1024 else { throw LibraryResourceError.tooLarge }
        return try Data(contentsOf: file)
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        guard response.url.flatMap({ Self.imageURL($0.absoluteString) }) != nil,
              (response as? HTTPURLResponse)?.statusCode == 200, response.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength > 0, response.expectedContentLength <= 8 * 1024 * 1024 else {
            completionHandler(nil); fail(WikiArtworkError.unavailable); return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wiki-cover-" + UUID().uuidString)
        downloadedFile = file; completionHandler(file)
    }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(.cancel); fail(WikiArtworkError.unavailable)
    }
    func downloadDidFinish(_ download: WKDownload) {
        timeout?.cancel(); timeout = nil
        guard let file = downloadedFile else { fail(WikiArtworkError.unavailable); return }
        downloadedFile = nil; self.download = nil
        downloadContinuation?.resume(returning: file); downloadContinuation = nil
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { fail(error) }

    private func evaluate<T: Decodable>(_ script: String, as type: T.Type) async throws -> T {
        guard let value = try await webView.evaluateJavaScript(script) as? String, let data = value.data(using: .utf8) else { throw WikiArtworkError.unsupported }
        return try JSONDecoder().decode(type, from: data)
    }
    static let articleScript = #"""
    (() => {
      const box = document.querySelector('.arcaeabox');
      if (!box) return JSON.stringify({songIDs:[],jackets:[]});
      const label = Array.from(box.querySelectorAll('.label')).find(e => e.textContent.trim() === 'Song ID');
      const songIDs = [];
      for (let e = label?.nextElementSibling; e && !e.classList.contains('label'); e = e.nextElementSibling) {
        const text = e.textContent.trim();
        if (text) songIDs.push(text);
      }
      const jackets = Array.from(box.querySelectorAll('.art-container a[href*="File:"]')).map(a => {
        const panel = a.closest('[role="tabpanel"]');
        const tab = panel && document.getElementById(panel.getAttribute('aria-labelledby'));
        return {filePage:a.href,difficulties:tab ? tab.textContent.trim() : (panel ? panel.id.replace(/^tabber-/, '') : '')};
      });
      return JSON.stringify({songIDs,jackets});
    })()
    """#

    // Charts whose wiki page was read without finding a jacket. They are left alone on later
    // runs so the same pages are not opened every time; an app update tries them again.
    private struct Unmatched: Codable { var version: String; var charts: Set<String> }
    private static let unmatchedKey = "wikiUnmatchedCharts"
    private static func key(_ chart: ChartID) -> String { "\(chart.songID):\(chart.difficulty.rawValue)" }
    private static func loadUnmatched() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: unmatchedKey), let saved = try? JSONDecoder().decode(Unmatched.self, from: data),
              saved.version == AppInfo.version else { return [] }
        return saved.charts
    }
    private(set) var unmatchedCount = WikiArtwork.loadUnmatched().count
    private func saveUnmatched(_ charts: Set<String>) {
        unmatchedCount = charts.count
        UserDefaults.standard.set(try? JSONEncoder().encode(Unmatched(version: AppInfo.version, charts: charts)), forKey: Self.unmatchedKey)
    }
    func start(charts: [ChartMetadata], retryUnmatched: Bool = false) {
        guard !running else { return }
        running = true
        task = Task {
            defer { running = false; task = nil }
            var unmatched = retryUnmatched ? [] : Self.loadUnmatched()
            defer { saveUnmatched(unmatched) }
            do {
                status = "Reading the song list…"
                try await load(URL(string: "https://arcaea.miraheze.org/wiki/Song_list")!)
                struct Link: Decodable { let title: String; let url: String }
                let links = try await evaluate(#"JSON.stringify(Array.from(document.querySelectorAll('table tr')).flatMap(r => {const a=r.querySelector('td a');return a?[{title:a.textContent.trim(),url:a.href}]:[]}))"#, as: [Link].self)
                guard !links.isEmpty else { throw WikiArtworkError.unavailable }
                let groups = Dictionary(grouping: charts, by: { $0.id.songID }).sorted { $0.key < $1.key }
                var saved = 0, skipped = 0
                for (index, group) in groups.enumerated() {
                    try Task.checkCancellation()
                    let missing = group.value.filter { !LibraryResources.shared.hasWikiCover($0.id) }
                    let needed = missing.filter { !unmatched.contains(Self.key($0.id)) }
                    skipped += missing.count - needed.count
                    if needed.isEmpty { continue }
                    let titles = Set(needed.compactMap(\.title).map { $0.lowercased() })
                    let candidates = Set(links.filter { titles.contains($0.title.lowercased()) }.map(\.url))
                    guard candidates.count == 1, let address = candidates.first, let url = Self.wikiURL(address) else { skipped += needed.count; continue }
                    status = "Song \(index + 1) of \(groups.count) · \(needed.first?.title ?? group.key)"
                    try await load(url)
                    let article = try await evaluate(Self.articleScript, as: WikiSongArticle.self)
                    guard !article.songIDs.isEmpty else { throw WikiArtworkError.unavailable }
                    guard article.songIDs.contains(group.key) else {
                        skipped += needed.count; unmatched.formUnion(needed.map { Self.key($0.id) }); continue
                    }
                    var files: [String: Data] = [:]
                    for chart in needed {
                        guard let jacket = article.jacket(for: chart.id), let page = Self.wikiURL(jacket.filePage) else {
                            skipped += 1; unmatched.insert(Self.key(chart.id)); continue
                        }
                        let bytes: Data
                        if let cached = files[jacket.filePage] { bytes = cached }
                        else {
                            try await load(page)
                            let address = try await evaluate(#"JSON.stringify(document.querySelector('.fullMedia a.internal')?.href || '')"#, as: String.self)
                            guard let image = Self.imageURL(address) else { skipped += 1; unmatched.insert(Self.key(chart.id)); continue }
                            bytes = try await original(image)
                            files[jacket.filePage] = bytes
                        }
                        try Task.checkCancellation()
                        do {
                            try LibraryResources.shared.saveWikiCover(bytes, chart: chart.id)
                            saved += 1
                        } catch LibraryResourceError.invalidImage {
                            // A small or malformed original must not prevent later charts from downloading.
                            skipped += 1; unmatched.insert(Self.key(chart.id))
                        }
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                status = "Saved \(saved) chart covers. \(skipped) charts without a matching wiki jacket keep their existing artwork."
            } catch is CancellationError { status = "Stopped. Completed covers are retained." }
            catch { status = error.localizedDescription }
        }
    }
}
