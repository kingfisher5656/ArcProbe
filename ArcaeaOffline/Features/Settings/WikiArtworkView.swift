import SwiftUI
import WebKit

struct WikiArtworkView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reader = WikiArtwork()
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(reader.status).font(.headline).padding(.horizontal)
                Text("Uses original files from Arcaea Fan Wiki. Song IDs and difficulty labels must match; ambiguous covers keep the official artwork. Keep this screen open while downloading. A website check, if shown, must be completed manually.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                if reader.running { ProgressView().padding(.horizontal) }
                else { Button("Download missing wiki covers") { reader.start(charts: Array(model.catalog.charts.values)) }.buttonStyle(.borderedProminent).padding(.horizontal) }
                WikiArtworkBrowser(webView: reader.webView)
                Text("Artwork belongs to its credited artists and rights holders. Source: Arcaea Fan Wiki on Miraheze.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            .navigationTitle("Sharper cover artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(reader.running ? "Stop & close" : "Done") { reader.stop(); dismiss() } }
        }.interactiveDismissDisabled(reader.running).onDisappear { reader.stop() }
    }
}
private struct WikiArtworkBrowser: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
