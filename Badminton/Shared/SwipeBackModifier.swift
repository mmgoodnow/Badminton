import SwiftUI

#if os(macOS)
import AppKit

private final class SwipeBackView: NSView {
    var onSwipe: (CGFloat) -> Void

    init(onSwipe: @escaping (CGFloat) -> Void) {
        self.onSwipe = onSwipe
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func swipe(with event: NSEvent) {
        onSwipe(event.deltaX)
    }
}

private struct SwipeBackRecognizer: NSViewRepresentable {
    var onSwipe: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeBackView {
        SwipeBackView(onSwipe: onSwipe)
    }

    func updateNSView(_ nsView: SwipeBackView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        background(SwipeBackRecognizer { deltaX in
            if deltaX > 0 {
                action()
            }
        })
    }
}
#else
extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        self
    }
}
#endif
