import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundView
            HomeView()
        }
        .dynamicTypeSize(.large)
    }

    private var backgroundView: some View {
        Group {
            if colorScheme == .dark {
                Color.black
            } else {
#if os(macOS)
                Color(nsColor: .windowBackgroundColor)
#else
                Color(uiColor: .systemBackground)
#endif
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environmentObject(TMDBAuthManager())
}
