import SwiftUI

#if os(macOS)
import AppKit

private final class SwipeBackView: NSView {
    var onSwipe: () -> Void
    private var monitor: Any?

    init(onSwipe: @escaping () -> Void) {
        self.onSwipe = onSwipe
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func swipe(with event: NSEvent) {
        if event.deltaX > 0 {
            onSwipe()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe]) { [weak self] event in
            guard let self else { return event }
            if event.deltaX > 0 {
                self.onSwipe()
            }
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
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
