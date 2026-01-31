import Foundation

enum PlexConfig {
    static let pinBaseURL = URL(string: "https://plex.tv/api/v2/pins")!
    static let authBaseURL = URL(string: "https://app.plex.tv/auth")!
    static let productName = "Badminton"
    static let redirectURI = "badminton://auth/plex"

    static var clientIdentifier: String {
        PlexClientIDStore.shared.clientIdentifier
    }
}

private final class PlexClientIDStore {
    static let shared = PlexClientIDStore()
    private let key = "plex.client.id"

    var clientIdentifier: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
