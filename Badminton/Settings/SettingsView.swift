import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: TMDBAuthManager
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @EnvironmentObject private var overseerrAuthManager: OverseerrAuthManager
    @StateObject private var plexServers = PlexServerListViewModel()
    @StateObject private var plexAccounts = PlexAccountListViewModel()
#if os(iOS)
    @StateObject private var liveActivity = PlaybackLiveActivityManager()
#endif
    @State private var isSigningInTMDB = false
    @State private var tmdbErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tmdbCard
                    plexCard
                    overseerrCard
#if os(iOS)
                    liveActivityCard
#endif
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(settingsBackground)
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

    private var tmdbCard: some View {
        settingsCard(
            title: "TMDB",
            subtitle: "Sign in with TMDB to personalize your experience.",
            status: tmdbStatus
        ) {
            settingsSubcard(title: "Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    configRow(title: "TMDB_API_KEY", isReady: !TMDBConfig.apiKey.isEmpty)
                    configRow(title: "TMDB_READ_ACCESS_TOKEN", isReady: !TMDBConfig.readAccessToken.isEmpty)
                    configRow(title: "TMDB_REDIRECT_URI", isReady: !TMDBConfig.redirectURI.isEmpty)
                    Text("Set these in Secrets.xcconfig or via Xcode Cloud env vars.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if authManager.isAuthenticated {
                Button("Disconnect TMDB", role: .destructive) {
                    Task { await authManager.signOut() }
                }
                .buttonStyle(.bordered)
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
    }

    private var plexCard: some View {
        settingsCard(
            title: "Plex",
            subtitle: "Connect Plex to personalize Badminton and see what you're watching.",
            status: plexStatus
        ) {
            if plexAuthManager.isAuthenticated {
                settingsSubcard {
                    serverPicker
                }
                settingsSubcard {
                    accountPicker
                }
                Button("Disconnect Plex", role: .destructive) {
                    plexAuthManager.signOut()
                }
                .buttonStyle(.bordered)
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
    }

    private var overseerrCard: some View {
        settingsCard(
            title: "Overseerr",
            subtitle: "Connect Overseerr to request movies and shows from Badminton.",
            status: overseerrStatus
        ) {
            settingsSubcard(title: "Server") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://overseerr.yourdomain.com", text: $overseerrAuthManager.baseURLString)
                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
#endif
                    Text("Include the scheme (https://).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if overseerrAuthManager.isAuthenticated {
                if let displayName = overseerrAuthManager.userDisplayName, !displayName.isEmpty {
                    Text("Signed in as \(displayName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect Overseerr", role: .destructive) {
                    overseerrAuthManager.signOut()
                }
                .buttonStyle(.bordered)
            } else {
                Button(overseerrAuthManager.isAuthenticating ? "Connecting…" : "Connect Overseerr") {
                    Task { await overseerrAuthManager.signIn(plexToken: plexAuthManager.authToken) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnectOverseerr)
            }

            if overseerrAuthManager.isAuthenticating {
                ProgressView("Waiting for Overseerr…")
            }

            if let errorMessage = overseerrAuthManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !plexAuthManager.isAuthenticated {
                Text("Connect Plex first to authenticate with Overseerr.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

#if os(iOS)
    private var liveActivityCard: some View {
        settingsCard(
            title: "Live Activity",
            subtitle: "Debug controls for live activity previews.",
            status: nil
        ) {
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
    }
#endif

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
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferred Server")
                    .font(.callout.weight(.semibold))
                Picker("", selection: selection) {
                    Text("Auto").tag(String?.none)
                    ForEach(plexServers.servers) { server in
                        Text(server.displayName).tag(Optional(server.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
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
#if os(iOS)
                .toggleStyle(.switch)
#endif
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

    private var tmdbStatus: SettingsStatus? {
        if authManager.isAuthenticated {
            return SettingsStatus(text: "Connected", systemImage: "checkmark.circle.fill", color: .green)
        }
        if canSignInTMDB {
            return SettingsStatus(text: "Ready", systemImage: "checkmark.circle", color: .orange)
        }
        return SettingsStatus(text: "Needs setup", systemImage: "exclamationmark.triangle.fill", color: .orange)
    }

    private var plexStatus: SettingsStatus? {
        if plexAuthManager.isAuthenticated {
            return SettingsStatus(text: "Connected", systemImage: "checkmark.circle.fill", color: .green)
        }
        if plexAuthManager.isAuthenticating {
            return SettingsStatus(text: "Connecting", systemImage: "arrow.triangle.2.circlepath", color: .orange)
        }
        return SettingsStatus(text: "Not connected", systemImage: "xmark.circle.fill", color: .secondary)
    }

    private var overseerrStatus: SettingsStatus? {
        if overseerrAuthManager.isAuthenticated {
            return SettingsStatus(text: "Connected", systemImage: "checkmark.circle.fill", color: .green)
        }
        if overseerrAuthManager.isAuthenticating {
            return SettingsStatus(text: "Connecting", systemImage: "arrow.triangle.2.circlepath", color: .orange)
        }
        if overseerrAuthManager.baseURL == nil {
            return SettingsStatus(text: "Needs URL", systemImage: "exclamationmark.triangle.fill", color: .orange)
        }
        if !plexAuthManager.isAuthenticated {
            return SettingsStatus(text: "Needs Plex", systemImage: "xmark.circle.fill", color: .secondary)
        }
        return SettingsStatus(text: "Not connected", systemImage: "xmark.circle.fill", color: .secondary)
    }

    private var canConnectOverseerr: Bool {
        overseerrAuthManager.baseURL != nil && plexAuthManager.isAuthenticated && !overseerrAuthManager.isAuthenticating
    }

    private var settingsBackground: some View {
        ZStack {
            baseBackgroundColor
            LinearGradient(
                colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var baseBackgroundColor: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        status: SettingsStatus?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let status {
                    statusPill(status)
                }
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func settingsSubcard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusPill(_ status: SettingsStatus) -> some View {
        Label(status.text, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func configRow(title: String, isReady: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(isReady ? "Set" : "Missing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isReady ? .green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isReady ? Color.green : Color.orange).opacity(0.15), in: Capsule())
        }
    }
}

private struct SettingsStatus {
    let text: String
    let systemImage: String
    let color: Color
}

#Preview {
    SettingsView()
        .environmentObject(TMDBAuthManager())
        .environmentObject(PlexAuthManager())
        .environmentObject(OverseerrAuthManager())
}
