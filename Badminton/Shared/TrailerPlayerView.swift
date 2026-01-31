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
            ZStack {
                Color.black
                    .ignoresSafeArea()
                WebView(url: link.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        #if os(iOS)
        .presentationDetents([.large])
        #else
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}

#if os(iOS)
private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        loadContent(into: uiView, url: url)
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
        loadContent(into: nsView, url: url)
    }
}
#endif

private func loadContent(into webView: WKWebView, url: URL) {
    if let embedID = youtubeEmbedID(from: url) {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
            <style>
              html, body { margin: 0; padding: 0; background: #000; height: 100%; }
              iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
            </style>
          </head>
          <body>
            <iframe
              src=\"https://www.youtube.com/embed/\(embedID)?playsinline=1&autoplay=1&rel=0&modestbranding=1&origin=https://www.youtube.com\"
              allow=\"autoplay; encrypted-media; picture-in-picture\"
              allowfullscreen
              referrerpolicy=\"origin\">
            </iframe>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return
    }

    if webView.url != url {
        webView.load(URLRequest(url: url))
    }
}

private func youtubeEmbedID(from url: URL) -> String? {
    guard let host = url.host?.lowercased() else { return nil }

    if host.contains("youtu.be") {
        return url.pathComponents.last
    }

    if host.contains("youtube.com") {
        if url.path.contains("/embed/") {
            return url.pathComponents.last
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return id
        }
    }

    return nil
}
