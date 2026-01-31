import AuthenticationServices
import Combine
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class PlexAuthManager: NSObject, ObservableObject {
    @Published private(set) var authToken: String?
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isAuthenticating: Bool = false
    @Published var errorMessage: String?

    private let session: URLSession
    private var webAuthSession: ASWebAuthenticationSession?
    private let storage = PlexTokenStore()

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
        authToken = storage.read(.authToken)
        isAuthenticated = authToken != nil
    }

    func signIn() async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let pin = try await createPin()
            try await beginWebAuthentication(url: makeAuthURL(pinCode: pin.code))
            let token = try await pollPin(id: pin.id)
            authToken = token
            isAuthenticated = true
            storage.save(token, for: .authToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        authToken = nil
        isAuthenticated = false
        storage.delete(.authToken)
    }

    private func createPin() async throws -> PlexPin {
        var components = URLComponents(url: PlexConfig.pinBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "strong", value: "true")]
        let url = components?.url ?? PlexConfig.pinBaseURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    private func pollPin(id: Int) async throws -> String {
        let url = PlexConfig.pinBaseURL.appendingPathComponent(String(id))
        var attempt = 0

        while attempt < 90 {
            attempt += 1
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
            request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response)
            let pin = try JSONDecoder().decode(PlexPinStatus.self, from: data)
            if let token = pin.authToken, !token.isEmpty {
                return token
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw PlexAuthError.timedOut
    }

    private func makeAuthURL(pinCode: String) -> URL {
        var components = URLComponents(url: PlexConfig.authBaseURL, resolvingAgainstBaseURL: false)
        components?.fragment = "!?"+Self.encodeQuery([
            "clientID": PlexConfig.clientIdentifier,
            "code": pinCode,
            "forwardUrl": PlexConfig.redirectURI,
            "context[device][product]": PlexConfig.productName,
            "context[device][platform]": Self.platformName,
            "context[device][platformVersion]": ProcessInfo.processInfo.operatingSystemVersionString,
            "context[device][deviceName]": Self.deviceName,
        ])
        return components?.url ?? PlexConfig.authBaseURL
    }

    private func beginWebAuthentication(url: URL) async throws {
        let callbackScheme = URL(string: PlexConfig.redirectURI)?.scheme
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.webAuthSession = session
            session.start()
        }
    }

    private static var platformName: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    private static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    private static func encodeQuery(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            throw PlexAuthError.badResponse(http.statusCode)
        }
    }
}

extension PlexAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

struct PlexPin: Decodable {
    let id: Int
    let code: String
}

struct PlexPinStatus: Decodable {
    let id: Int
    let code: String?
    let authToken: String?
}

enum PlexAuthError: LocalizedError {
    case badResponse(Int)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Plex auth failed (HTTP \(code))."
        case .timedOut:
            return "Plex login timed out. Please try again."
        }
    }
}

private struct PlexTokenStore {
    enum Key: String {
        case authToken = "plex.auth.token"
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
