import Foundation

final class PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecentlyWatched(token: String, size: Int = 20) async throws -> PlexHistoryResult {
        let result = try await requestHistoryData(token: token, size: size)
        let items = try parseHistoryItems(from: result.data)
        return PlexHistoryResult(items: items, serverBaseURL: result.serverBaseURL, serverToken: result.serverToken)
    }

    func fetchRecentlyWatchedRaw(token: String, size: Int = 20) async throws -> PlexHistoryRawResult {
        let result = try await requestHistoryData(token: token, size: size)
        return PlexHistoryRawResult(
            data: result.data,
            response: result.response,
            serverBaseURL: result.serverBaseURL,
            serverToken: result.serverToken
        )
    }

    func fetchResourcesRaw(token: String) async throws -> PlexResourcesRawResult {
        let (data, response) = try await requestResourcesData(token: token)
        return PlexResourcesRawResult(data: data, response: response)
    }

    private func fetchResources(token: String) async throws -> PlexResourcesResponse {
        let (data, _) = try await requestResourcesData(token: token)
        return try JSONDecoder().decode(PlexResourcesResponse.self, from: data)
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func selectServer(from response: PlexResourcesResponse) -> PlexServerCandidate? {
        let devices = response.devices
        let servers = devices.filter { $0.provides?.contains("server") == true }
        for device in servers {
            if let connection = bestConnection(from: device.connections) {
                return PlexServerCandidate(baseURL: connection, accessToken: device.accessToken)
            }
        }
        return nil
    }

    private func bestConnection(from connections: [PlexConnection]?) -> URL? {
        let candidates = connections ?? []
        let nonRelay = candidates.filter { !$0.isRelay && $0.uri != nil }
        if let remoteSecure = nonRelay.first(where: { !$0.isLocal && $0.isSecure }) {
            return remoteSecure.uri
        }
        if let remote = nonRelay.first(where: { !$0.isLocal }) {
            return remote.uri
        }
        if let localSecure = nonRelay.first(where: { $0.isLocal && $0.isSecure }) {
            return localSecure.uri
        }
        if let local = nonRelay.first(where: { $0.isLocal }) {
            return local.uri
        }
        if let preferred = nonRelay.first {
            return preferred.uri
        }
        return candidates.first(where: { $0.uri != nil })?.uri
    }

    private func requestHistoryData(token: String, size: Int) async throws -> (data: Data, response: HTTPURLResponse, serverBaseURL: URL, serverToken: String) {
        let resourceResponse = try await fetchResources(token: token)
        guard let server = selectServer(from: resourceResponse) else {
            throw URLError(.cannotFindHost)
        }

        let serverToken = server.accessToken ?? token
        let serverURL = server.baseURL

        var components = URLComponents(url: serverURL.appendingPathComponent("status/sessions/history/all"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "viewedAt:desc"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)"),
            URLQueryItem(name: "X-Plex-Token", value: serverToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexConfig.clientIdentifier),
            URLQueryItem(name: "X-Plex-Product", value: PlexConfig.productName)
        ]
        let url = components?.url ?? serverURL.appendingPathComponent("status/sessions/history/all")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(serverToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, http, serverURL, serverToken)
    }

    private func parseHistoryItems(from data: Data) throws -> [PlexHistoryItem] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(PlexHistoryResponse.self, from: data)
        return response.items
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

private struct PlexServerCandidate {
    let baseURL: URL
    let accessToken: String?
}

private struct PlexResourcesResponse: Decodable {
    let devices: [PlexDevice]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        devices = try container.decode([PlexDevice].self)
    }
}

private struct PlexDevice: Decodable {
    let provides: String?
    let accessToken: String?
    let connections: [PlexConnection]

    private enum CodingKeys: String, CodingKey {
        case provides
        case accessToken
        case connections = "connections"
    }
}

private struct PlexConnection: Decodable {
    let uri: URL?
    let isLocal: Bool
    let isRelay: Bool
    let `protocol`: String?

    private enum CodingKeys: String, CodingKey {
        case uri
        case isLocal = "local"
        case isRelay = "relay"
        case `protocol` = "protocol"
    }

    var isSecure: Bool {
        uri?.scheme == "https"
    }
}
