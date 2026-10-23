import Foundation

@MainActor
final class PlexAPIClient {
    private let session: URLSession
    private var resourcesTask: Task<PlexResourcesResponse, Error>?
    private var resourcesToken: String?
    private var resourcesDate: Date?
    private var workingConnections: [String: URL] = [:]

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecentlyWatched(token: String, size: Int = 20, preferredServerID: String? = nil) async throws -> PlexHistoryResult {
        let result = try await requestHistoryData(token: token, size: size, preferredServerID: preferredServerID)
        let items = try await parseHistoryItems(from: result.data, limit: size)
        return PlexHistoryResult(items: items, serverBaseURL: result.serverBaseURL, serverToken: result.serverToken)
    }

    func fetchNowPlaying(token: String, preferredServerID: String? = nil) async throws -> PlexHistoryResult {
        let result = try await requestSessionsData(token: token, preferredServerID: preferredServerID)
        let items = try await parseHistoryItems(from: result.data, limit: 0)
        return PlexHistoryResult(items: items, serverBaseURL: result.serverBaseURL, serverToken: result.serverToken)
    }

    func fetchRecentlyWatchedRaw(token: String, size: Int = 20, preferredServerID: String? = nil) async throws -> PlexHistoryRawResult {
        let result = try await requestHistoryData(token: token, size: size, preferredServerID: preferredServerID)
        return PlexHistoryRawResult(
            data: result.data,
            response: result.response,
            serverBaseURL: result.serverBaseURL,
            serverToken: result.serverToken
        )
    }

    func fetchMetadata(ratingKey: String, token: String, preferredServerID: String? = nil) async throws -> PlexMetadataItem? {
        let result = try await requestMetadataData(ratingKey: ratingKey, token: token, preferredServerID: preferredServerID)
        let response = try JSONDecoder().decode(PlexMetadataResponse.self, from: result.data)
        return response.items.first
    }

    func fetchServers(token: String) async throws -> [PlexServer] {
        let response = try await fetchResources(token: token)
        return response.devices
            .filter { $0.provides?.contains("server") == true }
            .map { device in
                PlexServer(
                    id: device.clientIdentifier,
                    name: device.name ?? "Plex Server",
                    product: device.product,
                    platform: device.platform,
                    owned: device.owned ?? false,
                    lastSeenAt: device.lastSeenAt
                )
            }
    }

    func fetchHomeUsers(token: String) async throws -> [PlexHomeUser] {
        var components = URLComponents(string: "https://plex.tv/api/v2/home/users")
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexConfig.clientIdentifier),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        let url = components?.url ?? URL(string: "https://plex.tv/api/v2/home/users")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PlexHomeUsersResponse.self, from: data).users
    }

    func fetchUserAccount(id: Int, token: String) async throws -> PlexUserAccount? {
        let url = URL(string: "https://plex.tv/api/users/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return PlexUserAccountParser.parse(data: data)
    }

    func fetchCurrentUser(token: String) async throws -> PlexUserAccount? {
        let url = URL(string: "https://plex.tv/users/account")!
        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return PlexUserAccountParser.parse(data: data)
    }

    func fetchResourcesRaw(token: String) async throws -> PlexResourcesRawResult {
        let (data, response) = try await requestResourcesData(token: token)
        return PlexResourcesRawResult(data: data, response: response)
    }

    private func fetchResources(token: String) async throws -> PlexResourcesResponse {
        if resourcesToken != token || resourcesDate.map({ Date().timeIntervalSince($0) > 300 }) == true {
            resourcesTask = nil
            workingConnections = [:]
        }
        if let resourcesTask { return try await resourcesTask.value }
        resourcesToken = token
        resourcesDate = Date()
        let task = Task {
            let (data, _) = try await requestResourcesData(token: token)
            return try JSONDecoder().decode(PlexResourcesResponse.self, from: data)
        }
        resourcesTask = task
        do { return try await task.value }
        catch {
            if resourcesToken == token { resourcesTask = nil }
            throw error
        }
    }

    private func requestResourcesData(token: String) async throws -> (data: Data, response: HTTPURLResponse) {
        var components = URLComponents(string: "https://clients.plex.tv/api/v2/resources")
        components?.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "includeIPv6", value: "1")
        ]
        let url = components?.url ?? URL(string: "https://clients.plex.tv/api/v2/resources")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                throw PlexAPIError.authenticationRequired
            }
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func requestHistoryData(token: String, size: Int, preferredServerID: String?) async throws -> PlexServerResponse {
        let oneMonthAgo = Int(Date().addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970)
        return try await requestServerData(token: token, preferredServerID: preferredServerID,
            path: "status/sessions/history/all", queryItems: [
                URLQueryItem(name: "sort", value: "viewedAt:desc"),
                URLQueryItem(name: "X-Plex-Container-Start", value: "0"),
                URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
                URLQueryItem(name: "viewedAt>", value: String(oneMonthAgo))
            ])
    }

    private func requestMetadataData(ratingKey: String, token: String, preferredServerID: String?) async throws -> PlexServerResponse {
        try await requestServerData(token: token, preferredServerID: preferredServerID,
            path: "library/metadata/\(ratingKey)", queryItems: [URLQueryItem(name: "includeGuids", value: "1")])
    }

    private func requestSessionsData(token: String, preferredServerID: String?) async throws -> PlexServerResponse {
        try await requestServerData(token: token, preferredServerID: preferredServerID, path: "status/sessions")
    }

    private func requestServerData(token: String, preferredServerID: String?, path: String,
                                   queryItems: [URLQueryItem] = []) async throws -> PlexServerResponse {
        guard let preferredServerID, !preferredServerID.isEmpty else { throw PlexAPIError.noSelectedServer }
        let resources = try await fetchResources(token: token)
        try Task.checkCancellation()
        guard let server = resources.devices.first(where: {
            $0.clientIdentifier == preferredServerID && $0.provides?.contains("server") == true
        }) else { throw PlexAPIError.selectedServerUnavailable }
        let serverToken = server.accessToken ?? token
        let urls = Array(Set((server.connections ?? []).compactMap(\.uri)))
        guard !urls.isEmpty else { throw PlexAPIError.selectedServerUnavailable }

        if let cached = workingConnections[preferredServerID], urls.contains(cached) {
            do {
                return try await Self.readServer(session: session, baseURL: cached, token: serverToken,
                                                 path: path, queryItems: queryItems)
            } catch {
                try Task.checkCancellation()
                workingConnections[preferredServerID] = nil
                print("Plex cached connection failed; trying other addresses for selected server")
            }
        }

        // Race actual GETs: every address belongs to the explicitly selected server.
        // A dead remote or LAN address cannot delay a reachable connection.
        let session = session
        let result = try await withThrowingTaskGroup(of: PlexServerResponse?.self) { group in
            for url in urls {
                group.addTask {
                    try? await Self.readServer(session: session, baseURL: url, token: serverToken,
                                               path: path, queryItems: queryItems)
                }
            }
            for try await response in group {
                if let response {
                    group.cancelAll()
                    return response
                }
            }
            try Task.checkCancellation()
            throw PlexAPIError.selectedServerUnavailable
        }
        workingConnections[preferredServerID] = result.serverBaseURL
        if PlexConfig.logConnectionSelection {
            print("Plex connected to selected server via \(result.serverBaseURL.host ?? "unknown")")
        }
        return result
    }

    private static func readServer(session: URLSession, baseURL: URL, token: String,
                                   path: String, queryItems: [URLQueryItem]) async throws -> PlexServerResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return PlexServerResponse(data: data, response: http, serverBaseURL: baseURL, serverToken: token)
    }

    private func parseHistoryItems(from data: Data, limit: Int) async throws -> [PlexHistoryItem] {
        let response = try JSONDecoder().decode(PlexHistoryResponse.self, from: data)
        return limit > 0 ? Array(response.items.prefix(limit)) : response.items
    }
}

struct PlexHistoryResult {
    let items: [PlexHistoryItem]
    let serverBaseURL: URL
    let serverToken: String
}

struct PlexHistoryRawResult {
    let data: Data
    let response: HTTPURLResponse
    let serverBaseURL: URL
    let serverToken: String
}

struct PlexResourcesRawResult {
    let data: Data
    let response: HTTPURLResponse
}

private struct PlexServerResponse {
    let data: Data
    let response: HTTPURLResponse
    let serverBaseURL: URL
    let serverToken: String
}

enum PlexAPIError: LocalizedError {
    case authenticationRequired
    case noSelectedServer
    case selectedServerUnavailable

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "Reconnect Plex in Settings; its saved connection is no longer authorized."
        case .noSelectedServer: return "Choose a Plex server in Settings."
        case .selectedServerUnavailable: return "The selected Plex server is unavailable. Check its connection or retry."
        }
    }
}

private struct PlexResourcesResponse: Decodable {
    let devices: [PlexDevice]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        devices = try container.decode([PlexDevice].self)
    }
}

private struct PlexDevice: Decodable {
    let name: String?
    let product: String?
    let platform: String?
    let clientIdentifier: String
    let provides: String?
    let accessToken: String?
    let owned: Bool?
    let lastSeenAt: String?
    let connections: [PlexConnection]?

    private enum CodingKeys: String, CodingKey {
        case name
        case product
        case platform
        case clientIdentifier
        case provides
        case accessToken
        case owned
        case lastSeenAt
        case connections = "connections"
    }
}

private struct PlexConnection: Decodable {
    let uri: URL?
    let address: String?
    let isLocal: Bool
    let isRelay: Bool
    let isIPv6: Bool?
    let `protocol`: String?

    private enum CodingKeys: String, CodingKey {
        case uri
        case address
        case isLocal = "local"
        case isRelay = "relay"
        case isIPv6 = "IPv6"
        case `protocol` = "protocol"
    }

    var isSecure: Bool {
        uri?.scheme == "https"
    }

    var isPlexDirect: Bool {
        uri?.host?.hasSuffix(".plex.direct") == true
    }

    var isIPv6Address: Bool {
        if let isIPv6 {
            return isIPv6
        }
        if let address {
            return address.contains(":")
        }
        return false
    }
}

struct PlexUserAccount: Hashable {
    let id: Int
    let title: String?
    let username: String?

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if let username, !username.isEmpty {
            return username
        }
        return "Account \(id)"
    }

    var nameVariants: Set<String> {
        var variants: Set<String> = []
        if let title, !title.isEmpty {
            variants.insert(title)
        }
        if let username, !username.isEmpty {
            variants.insert(username)
        }
        return variants
    }
}

private final class PlexUserAccountParser: NSObject, XMLParserDelegate {
    private var parsedUser: PlexUserAccount?

    static func parse(data: Data) -> PlexUserAccount? {
        let parser = XMLParser(data: data)
        let delegate = PlexUserAccountParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.parsedUser
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard parsedUser == nil else { return }
        if elementName.lowercased() == "user" {
            if let idString = attributeDict["id"], let id = Int(idString) {
                let title = attributeDict["title"]
                let username = attributeDict["username"]
                parsedUser = PlexUserAccount(id: id, title: title, username: username)
            }
        }
    }
}
