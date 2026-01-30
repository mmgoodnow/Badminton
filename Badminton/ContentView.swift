import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: TMDBAuthManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            backgroundView
            if authManager.isAuthenticated {
                HomeView()
            } else {
                authGate
            }
        }
    }

    private var authGate: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Badminton")
                            .font(.largeTitle.bold())
                        Text("Sign in with TMDB to personalize your experience.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Configuration") {
                        VStack(alignment: .leading, spacing: 8) {
                            configRow(title: "TMDB_API_KEY", isReady: !TMDBConfig.apiKey.isEmpty)
                            configRow(title: "TMDB_READ_ACCESS_TOKEN", isReady: !TMDBConfig.readAccessToken.isEmpty)
                            configRow(title: "TMDB_REDIRECT_URI", isReady: !TMDBConfig.redirectURI.isEmpty)
                            Text("Set these in Secrets.xcconfig or via Xcode Cloud env vars.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Session") {
                        VStack(alignment: .leading, spacing: 12) {
                            if isSigningIn {
                                ProgressView("Connecting…")
                            }
                            Button("Sign in with TMDB") {
                                Task { await signIn() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSignIn)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
        }
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        do {
            try await authManager.signIn()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSigningIn = false
    }

    private var canSignIn: Bool {
        !TMDBConfig.apiKey.isEmpty && !TMDBConfig.readAccessToken.isEmpty && !TMDBConfig.redirectURI.isEmpty
    }

    @ViewBuilder
    private func configRow(title: String, isReady: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(isReady ? "Set" : "Missing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
