import SwiftUI

@main
struct BadmintonApp: App {
    @StateObject private var authManager = TMDBAuthManager()
    @StateObject private var plexAuthManager = PlexAuthManager()
    @StateObject private var overseerrAuthManager = OverseerrAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(plexAuthManager)
                .environmentObject(overseerrAuthManager)
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        .commands {
            BadmintonRefreshCommands()
        }
#endif
    }
}
