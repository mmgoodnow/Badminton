import Foundation
import Testing
@testable import Badminton

@Suite(.serialized)
@MainActor
struct BadmintonTests {
    private func session(_ handler: @escaping (URLRequest) throws -> (Int, [String: String], String)) -> URLSession {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func expiredSeerrSessionRenewsAndRetriesOnce() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://seerr.test", forKey: "overseerr.base.url")
        defaults.set("connect.sid=old", forKey: "overseerr.session.cookie")
        var logins = 0
        var reads = 0
        let session = session { request in
            #expect(!request.httpShouldHandleCookies)
            switch request.url!.path {
            case "/api/v1/auth/plex":
                logins += 1
                return (200, ["Set-Cookie": "connect.sid=new; Path=/; HttpOnly"], "{\"id\":1}")
            case "/api/v1/auth/me":
                return (403, [:], "{\"error\":\"You do not have permission to access this endpoint\"}")
            default:
                reads += 1
                if request.value(forHTTPHeaderField: "Cookie") == "connect.sid=new" {
                    return (200, [:], "{\"mediaInfo\":{\"status\":5}}")
                }
                return (403, [:], "{\"message\":\"You do not have permission to perform this action\"}")
            }
        }
        let client = OverseerrAPIClient(session: session)
        let auth = OverseerrAuthManager(client: client, defaults: defaults)
        let movie = try await auth.withSession(plexToken: "plex-token") { url, cookie in
            try await client.getMovie(baseURL: url, tmdbID: 123, cookie: cookie)
        }
        #expect(movie.mediaInfo?.status == .available)
        #expect(logins == 1)
        #expect(reads == 2)
        #expect(auth.authCookie() == "connect.sid=new")
        session.invalidateAndCancel()
    }

    @Test func genuineSeerrPermissionDenialDoesNotLogOut() async throws {
        var checks = 0
        let session = session { request in
            if request.url!.path.hasSuffix("/auth/me") {
                checks += 1
                return (200, [:], "{\"id\":1}")
            }
            return (403, [:], "{\"message\":\"Requests are disabled for this user\"}")
        }
        let client = OverseerrAPIClient(session: session)
        do {
            _ = try await client.requestMedia(baseURL: URL(string: "https://seerr.test")!,
                body: OverseerrRequestBody(mediaType: .movie, mediaId: 1, seasons: nil), cookie: "connect.sid=valid")
            Issue.record("Expected permission denial")
        } catch let error as OverseerrAPIError {
            #expect(!error.isAuthenticationRequired)
            #expect(error.localizedDescription == "Requests are disabled for this user")
        }
        #expect(checks == 1)
        session.invalidateAndCancel()
    }

    @Test func seerrUnauthorizedWithoutJSONRequiresAuthentication() async throws {
        let session = session { _ in (401, [:], "Unauthorized") }
        let client = OverseerrAPIClient(session: session)
        do {
            _ = try await client.getMovie(baseURL: URL(string: "https://seerr.test")!, tmdbID: 1, cookie: "old")
            Issue.record("Expected expired session")
        } catch let error as OverseerrAPIError { #expect(error.isAuthenticationRequired) }
        session.invalidateAndCancel()
    }

    @Test func plexUsesOnlySelectedServerAndCachesDiscovery() async throws {
        var discoveries = 0
        var hosts: [String] = []
        let session = session { request in
            let host = request.url!.host!
            if host == "clients.plex.tv" {
                discoveries += 1
                return (200, [:], Self.resources)
            }
            hosts.append(host)
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "selected-token")
            #expect(!request.url!.absoluteString.contains("selected-token"))
            if host == "dead.test" { throw URLError(.cannotConnectToHost) }
            return (200, [:], "{\"MediaContainer\":{\"Metadata\":[]}}")
        }
        let client = PlexAPIClient(session: session)
        _ = try await client.fetchRecentlyWatched(token: "account", preferredServerID: "selected")
        _ = try await client.fetchNowPlaying(token: "account", preferredServerID: "selected")
        _ = try await client.fetchMetadata(ratingKey: "42", token: "account", preferredServerID: "selected")
        #expect(discoveries == 1)
        #expect(hosts.contains("working.test"))
        #expect(!hosts.contains("other.test"))
        session.invalidateAndCancel()
    }

    @Test func missingSelectedServerNeverFallsBack() async throws {
        let session = session { request in
            #expect(request.url!.host == "clients.plex.tv")
            return (200, [:], Self.resources)
        }
        let client = PlexAPIClient(session: session)
        do {
            _ = try await client.fetchNowPlaying(token: "account", preferredServerID: "missing")
            Issue.record("Expected unavailable selected server")
        } catch let error as PlexAPIError {
            #expect(error.localizedDescription.contains("selected Plex server"))
        }
        session.invalidateAndCancel()
    }

    @Test func historyFailureStillShowsNowPlaying() async throws {
        let session = session { request in
            if request.url!.host == "clients.plex.tv" { return (200, [:], Self.resources) }
            if request.url!.path == "/status/sessions" {
                return (200, [:], "{\"MediaContainer\":{\"Metadata\":[{\"ratingKey\":\"42\",\"type\":\"movie\",\"title\":\"Test\",\"thumb\":\"/thumb\"}]}}")
            }
            throw URLError(.cannotConnectToHost)
        }
        let model = HomeViewModel(plexClient: PlexAPIClient(session: session))
        await model.loadPlexHistory(token: "account", preferredServerID: "selected", preferredAccountIDs: [])
        #expect(model.plexNowPlaying.count == 1)
        #expect(model.plexErrorMessage?.hasPrefix("History:") == true)
        #expect(!model.plexIsLoading)
        await model.loadPlexHistory(token: nil, preferredServerID: nil, preferredAccountIDs: [])
        session.invalidateAndCancel()
    }

    @Test func availabilitySeparatesMoviesAndTVAndClearsOnDisconnect() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://seerr.test", forKey: "overseerr.base.url")
        defaults.set("connect.sid=test", forKey: "overseerr.session.cookie")
        let session = session { _ in
            (200, [:], "{\"pageInfo\":{\"pages\":1,\"page\":1,\"results\":1,\"pageSize\":100},\"results\":[{\"tmdbId\":42,\"mediaType\":\"movie\"}]}")
        }
        let auth = OverseerrAuthManager(client: OverseerrAPIClient(session: session), defaults: defaults)
        let index = OverseerrLibraryIndex(client: OverseerrAPIClient(session: session), defaults: defaults)
        await index.refresh(authManager: auth, plexToken: nil)
        #expect(index.isAvailable(tmdbID: 42, mediaType: .movie))
        #expect(!index.isAvailable(tmdbID: 42, mediaType: .tv))
        auth.signOut()
        await index.refresh(authManager: auth, plexToken: nil)
        #expect(index.availableMedia.isEmpty)
        #expect(index.lastUpdated == nil)
        session.invalidateAndCancel()
    }

    @Test func transientPlexFailurePreservesPreviouslyLoadedRail() async throws {
        var fail = false
        let session = session { request in
            if request.url!.host == "clients.plex.tv" { return (200, [:], Self.resources) }
            if fail { throw URLError(.cannotConnectToHost) }
            return (200, [:], "{\"MediaContainer\":{\"Metadata\":[{\"ratingKey\":\"42\",\"type\":\"movie\",\"title\":\"Test\",\"thumb\":\"/thumb\"}]}}")
        }
        let model = HomeViewModel(plexClient: PlexAPIClient(session: session))
        await model.loadPlexHistory(token: "account", preferredServerID: "selected", preferredAccountIDs: [])
        #expect(model.plexNowPlaying.count == 1)
        fail = true
        await model.loadPlexHistory(token: "account", preferredServerID: "selected", preferredAccountIDs: [], force: true)
        #expect(model.plexNowPlaying.count == 1)
        #expect(model.plexErrorMessage != nil)
        await model.loadPlexHistory(token: nil, preferredServerID: nil, preferredAccountIDs: [])
        session.invalidateAndCancel()
    }

    @Test func concurrentSeerrReadsShareOneRenewal() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://seerr.test", forKey: "overseerr.base.url")
        defaults.set("connect.sid=old", forKey: "overseerr.session.cookie")
        var logins = 0
        let session = session { request in
            if request.url!.path.hasSuffix("/auth/plex") {
                logins += 1
                return (200, ["Set-Cookie": "connect.sid=new; Path=/"], "{\"id\":1}")
            }
            if request.value(forHTTPHeaderField: "Cookie") == "connect.sid=new" {
                return (200, [:], "{\"mediaInfo\":{\"status\":5}}")
            }
            return (403, [:], "{\"error\":\"You do not have permission to access this endpoint\"}")
        }
        let client = OverseerrAPIClient(session: session)
        let auth = OverseerrAuthManager(client: client, defaults: defaults)
        async let first = auth.withSession(plexToken: "plex") { url, cookie in
            try await client.getMovie(baseURL: url, tmdbID: 1, cookie: cookie)
        }
        async let second = auth.withSession(plexToken: "plex") { url, cookie in
            try await client.getTV(baseURL: url, tmdbID: 2, cookie: cookie)
        }
        let responses = try await (first, second)
        #expect(responses.0.mediaInfo?.status == .available)
        #expect(responses.1.mediaInfo?.status == .available)
        #expect(logins == 1)
        session.invalidateAndCancel()
    }

    private static let resources = """
    [{"clientIdentifier":"other","provides":"server","accessToken":"other-token","connections":[{"uri":"https://other.test","local":false,"relay":false}]},
     {"clientIdentifier":"selected","provides":"server","accessToken":"selected-token","connections":[{"uri":"https://dead.test","local":false,"relay":false},{"uri":"https://working.test","local":true,"relay":false}]}]
    """
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
