import AuthenticationServices
import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class TMDBAuthManager: NSObject, ObservableObject {
    @Published private(set) var accessToken: String?
    @Published private(set) var accountID: String?
    @Published private(set) var isAuthenticated: Bool = false

    private let client: TMDBAPIClient
    private var webAuthSession: ASWebAuthenticationSession?
    private let storage = TMDBTokenStore()

    init(client: TMDBAPIClient = TMDBAPIClient()) {
        self.client = client
        super.init()
        accessToken = storage.read(.accessToken)
        accountID = storage.read(.accountID)
        isAuthenticated = accessToken != nil
    }

    func signIn() async throws {
        guard !TMDBConfig.readAccessToken.isEmpty else {
            throw TMDBAPIError.missingConfiguration("TMDB_READ_ACCESS_TOKEN")
        }
        guard !TMDBConfig.redirectURI.isEmpty else {
            throw TMDBAPIError.missingConfiguration("TMDB_REDIRECT_URI")
        }

        let requestTokenResponse: TMDBRequestTokenResponse = try await client.postV4(
            path: "/4/auth/request_token",
            body: TMDBRequestTokenRequest(redirectTo: TMDBConfig.redirectURI),
            accessToken: TMDBConfig.readAccessToken
        )

        let authURL = try makeAuthURL(requestToken: requestTokenResponse.requestToken)
        let callbackURL = try await beginWebAuthentication(url: authURL)
        let query = Self.queryItems(from: callbackURL)
        if query["approved"] == "false" {
            throw TMDBAuthError.notApproved
        }

        let approvedToken = query["request_token"] ?? requestTokenResponse.requestToken
        let accessTokenResponse: TMDBAccessTokenResponse = try await client.postV4(
            path: "/4/auth/access_token",
            body: TMDBAccessTokenRequest(requestToken: approvedToken),
            accessToken: TMDBConfig.readAccessToken
        )

        accessToken = accessTokenResponse.accessToken
        accountID = accessTokenResponse.accountId
        isAuthenticated = true

        if let accessToken {
            storage.save(accessToken, for: .accessToken)
        }
        if let accountID {
            storage.save(accountID, for: .accountID)
        }
    }

    func signOut() async {
        if let accessToken {
            _ = try? await client.deleteV4(
                path: "/4/auth/access_token",
                body: TMDBLogoutRequest(accessToken: accessToken),
                accessToken: TMDBConfig.readAccessToken
            ) as TMDBStatusResponse
        }
        accessToken = nil
        accountID = nil
        isAuthenticated = false
        storage.delete(.accessToken)
        storage.delete(.accountID)
    }

    private func makeAuthURL(requestToken: String) throws -> URL {
        guard var components = URLComponents(string: TMDBConfig.authBaseURL) else {
            throw TMDBAPIError.invalidURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "request_token", value: requestToken))
        components.queryItems = items
        guard let url = components.url else {
            throw TMDBAPIError.invalidURL
        }
        return url
    }

    private func beginWebAuthentication(url: URL) async throws -> URL {
        let callbackScheme = URL(string: TMDBConfig.redirectURI)?.scheme
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: TMDBAuthError.missingCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.webAuthSession = session
            session.start()
        }
    }

    private static func queryItems(from url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
}

extension TMDBAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

struct TMDBRequestTokenRequest: Encodable {
    let redirectTo: String
}

struct TMDBRequestTokenResponse: Decodable {
    let success: Bool
    let statusCode: Int
    let statusMessage: String
    let requestToken: String
}

struct TMDBAccessTokenRequest: Encodable {
    let requestToken: String
}

struct TMDBAccessTokenResponse: Decodable {
    let success: Bool
    let statusCode: Int
    let statusMessage: String
    let accessToken: String
    let accountId: String
}

struct TMDBLogoutRequest: Encodable {
    let accessToken: String
}

struct TMDBStatusResponse: Decodable {
    let success: Bool
    let statusCode: Int
    let statusMessage: String
}

enum TMDBAuthError: LocalizedError {
    case missingCallback
    case notApproved

    var errorDescription: String? {
        switch self {
        case .missingCallback:
            return "Authentication callback was missing."
        case .notApproved:
            return "Request was not approved."
        }
    }
}

private struct TMDBTokenStore {
    enum Key: String {
        case accessToken
        case accountID
    }

    func save(_ value: String, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    func read(_ key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    func delete(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }
}
