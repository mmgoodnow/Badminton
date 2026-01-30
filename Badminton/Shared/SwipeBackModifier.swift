import SwiftUI

#if os(macOS)
import AppKit

private final class SwipeBackView: NSView {
    var onSwipe: () -> Void
    private let recognizer: NSPanGestureRecognizer

    init(onSwipe: @escaping () -> Void) {
        self.onSwipe = onSwipe
        self.recognizer = NSPanGestureRecognizer()
        super.init(frame: .zero)

        recognizer.target = self
        recognizer.action = #selector(handlePan(_:))
        recognizer.allowedTouchTypes = [.direct, .indirect]
        addGestureRecognizer(recognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: self)
        let isHorizontal = abs(translation.x) > abs(translation.y)
        if isHorizontal && translation.x > 120 {
            onSwipe()
        }
    }
}

private struct SwipeBackRecognizer: NSViewRepresentable {
    var onSwipe: () -> Void

    func makeNSView(context: Context) -> SwipeBackView {
        SwipeBackView(onSwipe: onSwipe)
    }

    func updateNSView(_ nsView: SwipeBackView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        background(SwipeBackRecognizer(onSwipe: action))
    }
}
#else
extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        self
    }
}
#endif
