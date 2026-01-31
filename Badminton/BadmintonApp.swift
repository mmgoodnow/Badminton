import SwiftUI

@main
struct BadmintonApp: App {
    @StateObject private var authManager = TMDBAuthManager()
    @StateObject private var plexAuthManager = PlexAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(plexAuthManager)
        }
    }
}
