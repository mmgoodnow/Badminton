import SwiftUI

private struct BadmintonRefreshActionKey: FocusedValueKey {
    typealias Value = () async -> Void
}

extension FocusedValues {
    var badmintonRefreshAction: (() async -> Void)? {
        get { self[BadmintonRefreshActionKey.self] }
        set { self[BadmintonRefreshActionKey.self] = newValue }
    }
}

struct BadmintonRefreshCommands: Commands {
    @FocusedValue(\.badmintonRefreshAction) private var refreshAction

    var body: some Commands {
        CommandMenu("View") {
            Button("Refresh") {
                Task { await refreshAction?() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshAction == nil)
        }
    }
}
