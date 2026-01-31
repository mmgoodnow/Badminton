import Foundation

final class PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecentlyWatched(token: String, size: Int = 20) async throws -> PlexHistoryResult {
        let resourceResponse = try await fetchResources(token: token)
        guard let server = selectServer(from: resourceResponse) else {
            throw URLError(.cannotFindHost)
        }

        let serverToken = server.accessToken ?? token
        let serverURL = server.baseURL

        var components = URLComponents(url: serverURL.appendingPathComponent("/status/sessions/history/all"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "viewedAt:desc"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
        ]
        let url = components?.url ?? serverURL.appendingPathComponent("/status/sessions/history/all")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(serverToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let items = try JSONDecoder().decode(PlexHistoryResponse.self, from: data).items
        return PlexHistoryResult(items: items, serverBaseURL: serverURL, serverToken: serverToken)
    }

    private func fetchResources(token: String) async throws -> PlexResourcesResponse {
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
        return try JSONDecoder().decode(PlexResourcesResponse.self, from: data)
    }

    private func selectServer(from response: PlexResourcesResponse) -> PlexServerCandidate? {
        let devices = response.mediaContainer.devices ?? []
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
        if let local = candidates.first(where: { $0.isLocal }) {
            return local.uri
        }
        if let https = candidates.first(where: { $0.isSecure }) {
            return https.uri
        }
        return candidates.first?.uri
    }
}

struct PlexHistoryResult {
    let items: [PlexHistoryItem]
    let serverBaseURL: URL
    let serverToken: String
}

private struct PlexServerCandidate {
    let baseURL: URL
    let accessToken: String?
}

private struct PlexResourcesResponse: Decodable {
    let mediaContainer: PlexMediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexMediaContainer: Decodable {
    let devices: [PlexDevice]?

    private enum CodingKeys: String, CodingKey {
        case devices = "Device"
    }
}

private struct PlexDevice: Decodable {
    let provides: String?
    let accessToken: String?
    let connections: [PlexConnection]?

    private enum CodingKeys: String, CodingKey {
        case provides
        case accessToken
        case connections = "Connection"
    }
}

private struct PlexConnection: Decodable {
    let uri: URL
    let local: String?
    let relay: String?
    let `protocol`: String?

    private enum CodingKeys: String, CodingKey {
        case uri
        case local
        case relay
        case `protocol` = "protocol"
    }

    var isLocal: Bool {
        local == "1"
    }

    var isSecure: Bool {
        uri.scheme == "https"
    }
}
