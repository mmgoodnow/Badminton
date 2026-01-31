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
    @Environment(\.openURL) private var openURL
    @State private var playbackError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                WebView(url: link.url, playbackError: $playbackError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if playbackError, let watchURL = watchURL {
                    VStack(spacing: 12) {
                        Text("This trailer can’t be embedded.")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Button("Open in YouTube") {
                            openURL(watchURL)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle(link.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let watchURL = watchURL {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open in YouTube") {
                            openURL(watchURL)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #else
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    private var watchURL: URL? {
        guard let id = youtubeEmbedID(from: link.url) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}

#if os(iOS)
private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var playbackError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackError: $playbackError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "youtubeError")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            playbackError = false
            loadContent(into: uiView, url: url)
            context.coordinator.lastLoadedURL = url
        }
    }
}
#else
private struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var playbackError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackError: $playbackError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "youtubeError")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            playbackError = false
            loadContent(into: nsView, url: url)
            context.coordinator.lastLoadedURL = url
        }
    }
}
#endif

private final class Coordinator: NSObject, WKScriptMessageHandler {
    @Binding var playbackError: Bool
    var lastLoadedURL: URL?

    init(playbackError: Binding<Bool>) {
        _playbackError = playbackError
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "youtubeError" else { return }
        playbackError = true
    }
}

private func loadContent(into webView: WKWebView, url: URL) {
    if let embedID = youtubeEmbedID(from: url) {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
            <style>
              html, body { margin: 0; padding: 0; background: #000; height: 100%; }
              #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
            </style>
          </head>
          <body>
            <div id=\"player\"></div>
            <script src=\"https://www.youtube.com/iframe_api\"></script>
            <script>
              function onYouTubeIframeAPIReady() {
                new YT.Player('player', {
                  videoId: '\(embedID)',
                  playerVars: {
                    playsinline: 1,
                    autoplay: 1,
                    rel: 0,
                    modestbranding: 1,
                    origin: 'https://www.youtube.com'
                  },
                  events: {
                    onError: function(event) {
                      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.youtubeError) {
                        window.webkit.messageHandlers.youtubeError.postMessage(event.data);
                      }
                    }
                  }
                });
              }
            </script>
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
