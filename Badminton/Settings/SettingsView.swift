import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @StateObject private var plexServers = PlexServerListViewModel()
    @StateObject private var plexAccounts = PlexAccountListViewModel()
#if os(iOS)
    @StateObject private var liveActivity = PlaybackLiveActivityManager()
#endif

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
}

#Preview {
    SettingsView()
        .environmentObject(PlexAuthManager())
}
