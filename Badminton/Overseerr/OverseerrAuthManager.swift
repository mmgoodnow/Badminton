import Combine
import Foundation

@MainActor
final class OverseerrAuthManager: ObservableObject {
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

    private var renewalTask: Task<(user: OverseerrUser, cookie: String), Error>?
    private var sessionGeneration = UUID()

    private let client: OverseerrAPIClient
    private let storage: OverseerrTokenStore
    private var sessionCookie: String? {
        didSet { storage.save(sessionCookie, for: .sessionCookie) }
    }

    init(client: OverseerrAPIClient = OverseerrAPIClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.storage = OverseerrTokenStore(defaults: defaults)
        let storedBaseURL = storage.read(.baseURL) ?? ""
        self.baseURLString = storedBaseURL
        self.sessionCookie = storage.read(.sessionCookie)
        self.userDisplayName = storage.read(.userDisplayName)
        self.isAuthenticated = sessionCookie != nil
    }

    var baseURL: URL? {
        OverseerrConfig.normalizedBaseURL(from: baseURLString)
    }

    func signIn(plexToken: String?) async {
        errorMessage = nil
        do { try await renewSession(plexToken: plexToken) }
        catch { errorMessage = error.localizedDescription }
    }

    func withSession<T>(plexToken: String?, operation: (URL, String) async throws -> T) async throws -> T {
        guard let baseURL, let cookie = sessionCookie else { throw OverseerrAPIError.authenticationRequired }
        let generation = sessionGeneration
        do {
            let result = try await operation(baseURL, cookie)
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            return result
        }
        catch let error as OverseerrAPIError where error.isAuthenticationRequired {
            guard generation == sessionGeneration else { throw CancellationError() }
            // Concurrent reads share one login. A caller with an old cookie uses the renewed one.
            if sessionCookie == cookie {
                try await renewSession(plexToken: plexToken)
            }
            try Task.checkCancellation()
            guard generation == sessionGeneration, let renewed = sessionCookie else { throw CancellationError() }
            let result = try await operation(baseURL, renewed)
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            return result
        }
    }

    private func renewSession(plexToken: String?) async throws {
        guard let baseURL else { throw OverseerrAPIError.invalidURL }
        guard let plexToken, !plexToken.isEmpty else { throw OverseerrAPIError.authenticationRequired }
        let generation = sessionGeneration
        isAuthenticating = true
        defer { isAuthenticating = false }
        let task: Task<(user: OverseerrUser, cookie: String), Error>
        if let renewalTask { task = renewalTask }
        else {
            task = Task { try await client.signInWithPlex(baseURL: baseURL, plexToken: plexToken) }
            renewalTask = task
        }
        do {
            let response = try await task.value
            guard generation == sessionGeneration else { throw CancellationError() }
            renewalTask = nil
            sessionCookie = response.cookie
            userDisplayName = response.user.displayName ?? response.user.plexUsername ?? response.user.username
            storage.save(userDisplayName, for: .userDisplayName)
            isAuthenticated = true
        } catch {
            if generation == sessionGeneration { renewalTask = nil }
            throw error
        }
    }

    func signOut() {
        clearSession()
    }

    func expireSession() {
        clearSession()
        errorMessage = "Reconnect Seerr in Settings."
    }

    func authCookie() -> String? {
        sessionCookie
    }

    private func clearSession() {
        sessionGeneration = UUID()
        renewalTask?.cancel()
        renewalTask = nil
        sessionCookie = nil
        userDisplayName = nil
        storage.delete(.sessionCookie)
        storage.delete(.userDisplayName)
        isAuthenticated = false
    }
}

private struct OverseerrTokenStore {
    let defaults: UserDefaults
    enum Key: String {
        case baseURL = "overseerr.base.url"
        case sessionCookie = "overseerr.session.cookie"
        case userDisplayName = "overseerr.user.name"
    }

    func save(_ value: String?, for key: Key) {
        guard let value, !value.isEmpty else {
            delete(key)
            return
        }
        defaults.set(value, forKey: key.rawValue)
    }

    func read(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    func delete(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
