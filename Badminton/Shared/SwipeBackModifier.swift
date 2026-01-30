import SwiftUI

#if os(macOS)
import AppKit

private final class SwipeBackView: NSView {
    var onSwipe: () -> Void
    private var monitor: Any?
    private static weak var activeView: SwipeBackView?
    private static var activeMonitor: Any?

    init(onSwipe: @escaping () -> Void) {
        self.onSwipe = onSwipe
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateIfNeeded()
    }

    deinit {
        removeMonitorIfNeeded()
    }

    private func removeMonitorIfNeeded() {
        guard SwipeBackView.activeView === self else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        SwipeBackView.activeMonitor = nil
        SwipeBackView.activeView = nil
    }

    func activateIfNeeded() {
        guard window != nil else {
            removeMonitorIfNeeded()
            return
        }
        guard SwipeBackView.activeView !== self else { return }
        SwipeBackView.activeView?.removeMonitorIfNeeded()
        SwipeBackView.activeView = self

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe]) { [weak self] event in
            guard let self else { return event }
            if event.deltaX > 0 {
                self.onSwipe()
                return nil
            }
            return event
        }
        SwipeBackView.activeMonitor = monitor
    }
}

private struct SwipeBackRecognizer: NSViewRepresentable {
    var onSwipe: () -> Void

    func makeNSView(context: Context) -> SwipeBackView {
        SwipeBackView(onSwipe: onSwipe)
    }

    func updateNSView(_ nsView: SwipeBackView, context: Context) {
        nsView.onSwipe = onSwipe
        nsView.activateIfNeeded()
    }
}

extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        background(SwipeBackRecognizer(onSwipe: action))
    }

    func macOSSwipeToDismiss() -> some View {
        modifier(MacOSSwipeToDismissModifier())
    }
}
#else
extension View {
    func macOSSwipeToDismiss(_ action: @escaping () -> Void) -> some View {
        self
    }

    func macOSSwipeToDismiss() -> some View {
        self
    }
}
#endif

#if os(macOS)
private struct MacOSSwipeToDismissModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.macOSSwipeToDismiss { dismiss() }
    }
}
#endif
