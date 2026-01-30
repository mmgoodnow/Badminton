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
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            KFImage(item.url)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .simultaneousGesture(dragGesture)
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
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                } else {
                    lastOffset = offset
                }
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
