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
                Text("Keep this screen open while downloading. If the wiki shows a verification check below, complete it and start again.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                if reader.running { ProgressView().padding(.horizontal) }
                else {
                    HStack {
                        Button("Download missing wiki covers") { reader.start(charts: Array(model.catalog.charts.values)) }.buttonStyle(.borderedProminent)
                        if reader.unmatchedCount > 0 {
                            Button("Retry \(reader.unmatchedCount) unmatched") { reader.start(charts: Array(model.catalog.charts.values), retryUnmatched: true) }.buttonStyle(.bordered)
                        }
                    }.padding(.horizontal)
                }
                WikiArtworkBrowser(webView: reader.webView)
                Text("Artwork belongs to its credited artists and rights holders. Source: Arcaea Fan Wiki on Miraheze.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            .navigationTitle("Wiki covers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(reader.running ? "Stop & close" : "Done") { reader.stop(); dismiss() } }
        }.interactiveDismissDisabled(reader.running).presentationSizing(.page).onDisappear { reader.stop() }
    }
}
private struct WikiArtworkBrowser: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
