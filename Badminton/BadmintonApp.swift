import SwiftUI

@main
struct BadmintonApp: App {
    @StateObject private var authManager = TMDBAuthManager()
    @StateObject private var plexAuthManager = PlexAuthManager()
    @StateObject private var overseerrAuthManager = OverseerrAuthManager()
    @StateObject private var overseerrLibraryIndex = OverseerrLibraryIndex()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(plexAuthManager)
                .environmentObject(overseerrAuthManager)
                .environmentObject(overseerrLibraryIndex)
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        .commands {
            BadmintonRefreshCommands()
        }
#endif
    }
}
