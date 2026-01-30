import Kingfisher
import SwiftUI
import Zoomable

#if os(macOS)
import AppKit
#endif

struct ImageLightboxItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
}

struct ImageLightboxView: View {
    let item: ImageLightboxItem
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    close()
                }

            KFImage(item.url)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .zoomable(outOfBoundsColor: .black)
                .simultaneousGesture(TapGesture().onEnded { close() })
        }
        .contentShape(Rectangle())
        .onTapGesture {
            close()
        }
#if os(macOS)
        .onExitCommand {
            close()
        }
        .background(KeyDismissView(onKey: { close() }))
#endif
        .macOSSwipeToDismiss { close() }
    }

    private func close() {
        onDismiss?()
        dismiss()
    }
}

extension View {
    @ViewBuilder
    func imageLightbox(item: Binding<ImageLightboxItem?>) -> some View {
#if os(macOS)
        navigationDestination(item: item) { value in
            ImageLightboxView(item: value, onDismiss: { item.wrappedValue = nil })
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
