import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @StateObject private var plexServers = PlexServerListViewModel()
    @StateObject private var plexAccounts = PlexAccountListViewModel()

    var body: some View {
        NavigationStack {
            Form {
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
            let selection = Binding<Int?>(
                get: { plexAuthManager.preferredAccountID },
                set: { newValue in
                    plexAuthManager.setPreferredAccountID(newValue)
                }
            )
            Picker("History Account", selection: selection) {
                Text("All Accounts").tag(Int?.none)
                ForEach(plexAccounts.accounts) { account in
                    Text(account.displayName).tag(Optional(account.id))
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
}

#Preview {
    SettingsView()
        .environmentObject(PlexAuthManager())
}
