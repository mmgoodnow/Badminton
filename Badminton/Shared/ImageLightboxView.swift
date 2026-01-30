import Kingfisher
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ImageLightboxItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct ImageLightboxView: View {
    let item: ImageLightboxItem

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    KFImage(item.url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width * scale,
                               height: proxy.size.height * scale)
                        .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .gesture(magnificationGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
        .onExitCommand {
            dismiss()
        }
#if os(macOS)
        .background(KeyDismissView(onKey: { dismiss() }))
#endif
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}

#if os(macOS)
private struct KeyDismissView: NSViewRepresentable {
    let onKey: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onKey = onKey
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCatcherView {
            view.onKey = onKey
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }
}

private final class KeyCatcherView: NSView {
    var onKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKey?()
    }
}
#endif
