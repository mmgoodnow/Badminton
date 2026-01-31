import SwiftUI
import WebKit

struct TrailerLink: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
}

struct TrailerPlayerView: View {
    let link: TrailerLink

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: link.url)
                .ignoresSafeArea()
                .navigationTitle(link.title)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

#if os(iOS)
private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
#else
private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
#endif
