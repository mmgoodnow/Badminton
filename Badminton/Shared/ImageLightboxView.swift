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
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    close()
                }

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
            close()
        }
        .onExitCommand {
            close()
        }
#if os(macOS)
        .background(KeyDismissView(onKey: { close() }))
#endif
    }

    private func close() {
        onDismiss?()
        dismiss()
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

extension View {
    @ViewBuilder
    func imageLightbox(item: Binding<ImageLightboxItem?>) -> some View {
#if os(macOS)
        overlay {
            if let value = item.wrappedValue {
                ImageLightboxView(item: value, onDismiss: { item.wrappedValue = nil })
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
#else
        sheet(item: item) { value in
            ImageLightboxView(item: value, onDismiss: nil)
        }
#endif
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
