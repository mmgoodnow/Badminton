import Combine
import Foundation

@MainActor
final class OverseerrAuthManager: ObservableObject {
    @Published var siteName: String {
        didSet {
            let trimmed = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
            storage.save(trimmed, for: .siteName)
        }
    }
    @Published var baseURLString: String {
        didSet {
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            storage.save(trimmed, for: .baseURL)
            if trimmed != oldValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                clearSession()
            }
        }
    }
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isAuthenticating: Bool = false
    @Published private(set) var userDisplayName: String?
    @Published var errorMessage: String?

    private let client: OverseerrAPIClient
    private let storage = OverseerrTokenStore()
    private var sessionCookie: String? {
        didSet { storage.save(sessionCookie, for: .sessionCookie) }
    }

    init(client: OverseerrAPIClient = OverseerrAPIClient()) {
        self.client = client
        let storedBaseURL = storage.read(.baseURL) ?? ""
        self.baseURLString = storedBaseURL
        self.siteName = storage.read(.siteName) ?? ""
        self.sessionCookie = storage.read(.sessionCookie)
        self.userDisplayName = storage.read(.userDisplayName)
        self.isAuthenticated = sessionCookie != nil
    }

    var baseURL: URL? {
        OverseerrConfig.normalizedBaseURL(from: baseURLString)
    }

    func signIn(plexToken: String?) async {
        errorMessage = nil
        guard let baseURL else {
            errorMessage = "Enter your Overseerr URL first."
            return
        }
        guard let plexToken, !plexToken.isEmpty else {
            errorMessage = "Connect Plex first."
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let response = try await client.signInWithPlex(baseURL: baseURL, plexToken: plexToken)
            sessionCookie = response.cookie
            userDisplayName = response.user.displayName ?? response.user.plexUsername ?? response.user.username
            storage.save(userDisplayName, for: .userDisplayName)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        clearSession()
    }

    func authCookie() -> String? {
        sessionCookie
    }

    private func clearSession() {
        sessionCookie = nil
        userDisplayName = nil
        storage.delete(.sessionCookie)
        storage.delete(.userDisplayName)
        isAuthenticated = false
    }
}

private struct OverseerrTokenStore {
    enum Key: String {
        case baseURL = "overseerr.base.url"
        case siteName = "overseerr.site.name"
        case sessionCookie = "overseerr.session.cookie"
        case userDisplayName = "overseerr.user.name"
    }

    func save(_ value: String?, for key: Key) {
        guard let value, !value.isEmpty else {
            delete(key)
            return
        }
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    func read(_ key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    func delete(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }
}
