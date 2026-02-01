import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: TMDBAuthManager
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @StateObject private var plexServers = PlexServerListViewModel()
    @StateObject private var plexAccounts = PlexAccountListViewModel()
#if os(iOS)
    @StateObject private var liveActivity = PlaybackLiveActivityManager()
#endif
    @State private var isSigningInTMDB = false
    @State private var tmdbErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("TMDB") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in with TMDB to personalize your experience.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

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

                        if authManager.isAuthenticated {
                            HStack {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                            }
                            Button("Disconnect TMDB", role: .destructive) {
                                Task { await authManager.signOut() }
                            }
                        } else {
                            if isSigningInTMDB {
                                ProgressView("Connecting…")
                            }
                            Button("Sign in with TMDB") {
                                Task { await signInTMDB() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSignInTMDB)
                        }

                        if let tmdbErrorMessage {
                            Text(tmdbErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Plex") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Plex to personalize Badminton and see what you're watching.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if plexAuthManager.isAuthenticated {
                            HStack {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                            }
                            serverPicker
                            accountPicker
                            Button("Disconnect Plex", role: .destructive) {
                                plexAuthManager.signOut()
                            }
                        } else {
                            Button(plexAuthManager.isAuthenticating ? "Connecting…" : "Connect Plex") {
                                Task { await plexAuthManager.signIn() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(plexAuthManager.isAuthenticating)
                        }

                        if plexAuthManager.isAuthenticating {
                            ProgressView("Waiting for Plex…")
                        }

                        if let errorMessage = plexAuthManager.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
#if os(iOS)
                Section("Live Activity (Debug)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(liveActivity.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Start") {
                                liveActivity.startSample()
                            }
                            Button("Update") {
                                liveActivity.updateSample()
                            }
                            Button("End") {
                                liveActivity.endSample()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
#endif
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: plexAuthManager.authToken) {
            await plexServers.load(token: plexAuthManager.authToken)
            await plexAccounts.load(
                token: plexAuthManager.authToken,
                preferredServerID: plexAuthManager.preferredServerID
            )
        }
        .task(id: plexAuthManager.preferredServerID) {
            await plexAccounts.load(
                token: plexAuthManager.authToken,
                preferredServerID: plexAuthManager.preferredServerID
            )
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    @ViewBuilder
    private var serverPicker: some View {
        if plexServers.isLoading {
            ProgressView("Loading Plex servers…")
        } else if !plexServers.servers.isEmpty {
            let selection = Binding<String?>(
                get: { plexAuthManager.preferredServerID },
                set: { newValue in
                    plexAuthManager.setPreferredServer(
                        id: newValue,
                        name: plexServers.name(for: newValue)
                    )
                }
            )
            Picker("Preferred Server", selection: selection) {
                Text("Auto").tag(String?.none)
                ForEach(plexServers.servers) { server in
                    Text(server.displayName).tag(Optional(server.id))
                }
            }
        } else if let errorMessage = plexServers.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text("No Plex servers found.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accountPicker: some View {
        if plexAccounts.isLoading {
            ProgressView("Loading Plex accounts…")
        } else if !plexAccounts.accounts.isEmpty {
            let selection = Binding<Set<Int>>(
                get: { plexAuthManager.preferredAccountIDs },
                set: { newValue in
                    plexAuthManager.setPreferredAccountIDs(newValue)
                }
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("History Accounts")
                    .font(.callout.weight(.semibold))
                Text("Select one or more accounts. Leave none selected to show all.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(plexAccounts.accounts) { account in
                    Toggle(isOn: Binding(
                        get: { selection.wrappedValue.contains(account.id) },
                        set: { isOn in
                            var updated = selection.wrappedValue
                            if isOn {
                                updated.insert(account.id)
                            } else {
                                updated.remove(account.id)
                            }
                            selection.wrappedValue = updated
                        }
                    )) {
                        Text(accountLabel(for: account))
                    }
                }
                if !selection.wrappedValue.isEmpty {
                    Button("Show All Accounts") {
                        selection.wrappedValue = []
                    }
#if os(macOS)
                    .buttonStyle(.link)
#else
                    .buttonStyle(.borderless)
#endif
                }
            }
        } else if let errorMessage = plexAccounts.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text("No recent Plex accounts found.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func accountLabel(for account: PlexAccountOption) -> String {
        if let name = plexAccounts.name(for: account.id) {
            let suffix = account.count == 1 ? "play" : "plays"
            return "\(name) · \(account.count) \(suffix)"
        }
        return account.displayName
    }

    private func signInTMDB() async {
        tmdbErrorMessage = nil
        isSigningInTMDB = true
        do {
            try await authManager.signIn()
        } catch {
            tmdbErrorMessage = error.localizedDescription
        }
        isSigningInTMDB = false
    }

    private var canSignInTMDB: Bool {
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
}

#Preview {
    SettingsView()
        .environmentObject(TMDBAuthManager())
        .environmentObject(PlexAuthManager())
}
