import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plexAuthManager: PlexAuthManager

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
        .frame(minWidth: 360, minHeight: 320)
    }
}

#Preview {
    SettingsView()
        .environmentObject(PlexAuthManager())
}
