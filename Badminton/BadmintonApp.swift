import SwiftUI

@main
struct BadmintonApp: App {
    @StateObject private var authManager = TMDBAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
