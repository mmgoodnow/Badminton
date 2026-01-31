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
    @Published var preferredServerID: String? {
        didSet { storage.save(preferredServerID, for: .preferredServerID) }
    }
    @Published var preferredServerName: String? {
        didSet { storage.save(preferredServerName, for: .preferredServerName) }
    }
    @Published var preferredAccountID: Int? {
        didSet { storage.save(preferredAccountID.map(String.init), for: .preferredAccountID) }
    }

    private let session: URLSession
    private var webAuthSession: ASWebAuthenticationSession?
    private let storage = PlexTokenStore()

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
        authToken = storage.read(.authToken)
        isAuthenticated = authToken != nil
        preferredServerID = storage.read(.preferredServerID)
        preferredServerName = storage.read(.preferredServerName)
        if let accountID = storage.read(.preferredAccountID) {
            preferredAccountID = Int(accountID)
        }
    }

    func signIn() async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let pin = try await createPin()
            startWebAuthentication(url: makeAuthURL(pinCode: pin.code))
            let token = try await pollPin(id: pin.id)
            authToken = token
            isAuthenticated = true
            storage.save(token, for: .authToken)
            webAuthSession?.cancel()
            webAuthSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        authToken = nil
        isAuthenticated = false
        storage.delete(.authToken)
        preferredServerID = nil
        preferredServerName = nil
        storage.delete(.preferredServerID)
        storage.delete(.preferredServerName)
        preferredAccountID = nil
        storage.delete(.preferredAccountID)
    }

    func setPreferredServer(id: String?, name: String?) {
        preferredServerID = id
        preferredServerName = name
    }

    func setPreferredAccountID(_ id: Int?) {
        preferredAccountID = id
    }

    private func createPin() async throws -> PlexPin {
        var components = URLComponents(url: PlexConfig.pinBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "strong", value: "true")]
        let url = components?.url ?? PlexConfig.pinBaseURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyPlexHeaders(to: &request)

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
            applyPlexHeaders(to: &request)

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
        let params: [String: String] = [
            "clientID": PlexConfig.clientIdentifier,
            "code": pinCode,
            "context[device][product]": PlexConfig.productName,
            "context[device][version]": Self.appVersion,
            "context[device][platform]": Self.platformName,
            "context[device][platformVersion]": ProcessInfo.processInfo.operatingSystemVersionString,
            "context[device][device]": Self.deviceType,
            "context[device][deviceName]": Self.deviceName,
            "context[device][model]": Self.deviceModel,
            "context[device][screenResolution]": Self.screenResolution,
            "context[device][layout]": Self.layoutName,
        ]
        let urlString = "https://app.plex.tv/auth/#!?\(Self.encodeQuery(params))"
        return URL(string: urlString) ?? PlexConfig.authBaseURL
    }

    private func startWebAuthentication(url: URL) {
        let callbackScheme = URL(string: PlexConfig.redirectURI)?.scheme
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { _, _ in }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    private static var platformName: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    private static var deviceType: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.model
        #endif
    }

    private static var deviceModel: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.model
        #endif
    }

    private static var layoutName: String {
        #if os(macOS)
        return "desktop"
        #else
        return "mobile"
        #endif
    }

    private static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    private static var screenResolution: String {
        #if os(macOS)
        guard let screen = NSScreen.main else { return "0x0" }
        let scale = screen.backingScaleFactor
        let width = Int(screen.frame.width * scale)
        let height = Int(screen.frame.height * scale)
        return "\(width)x\(height)"
        #else
        let bounds = UIScreen.main.nativeBounds
        return "\(Int(bounds.width))x\(Int(bounds.height))"
        #endif
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static func encodeQuery(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = Self.percentEncode(key)
            let escapedValue = Self.percentEncode(value)
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            throw PlexAuthError.badResponse(http.statusCode)
        }
    }

    private func applyPlexHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(Self.appVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(Self.deviceModel, forHTTPHeaderField: "X-Plex-Model")
        request.setValue(Self.platformName, forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(ProcessInfo.processInfo.operatingSystemVersionString, forHTTPHeaderField: "X-Plex-Platform-Version")
        request.setValue(Self.deviceType, forHTTPHeaderField: "X-Plex-Device")
        request.setValue(Self.deviceName, forHTTPHeaderField: "X-Plex-Device-Name")
        request.setValue(Self.screenResolution, forHTTPHeaderField: "X-Plex-Device-Screen-Resolution")
        request.setValue(Locale.current.language.languageCode?.identifier ?? "en", forHTTPHeaderField: "X-Plex-Language")
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
        case preferredServerID = "plex.server.id"
        case preferredServerName = "plex.server.name"
        case preferredAccountID = "plex.account.id"
    }

    func save(_ value: String?, for key: Key) {
        guard let value else {
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
