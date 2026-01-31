import Foundation

final class PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRecentlyWatched(token: String, size: Int = 20) async throws -> PlexHistoryResult {
        let result = try await requestHistoryData(token: token, size: size)
        let items = try parseHistoryItems(from: result.data, response: result.response)
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
        let devices = response.mediaContainer.devices
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
        if let local = candidates.first(where: { $0.isLocal && $0.uri != nil }) {
            return local.uri
        }
        if let https = candidates.first(where: { !$0.isRelay && $0.isSecure && $0.uri != nil }) {
            return https.uri
        }
        if let preferred = candidates.first(where: { !$0.isRelay && $0.uri != nil }) {
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

    private func parseHistoryItems(from data: Data, response: HTTPURLResponse) throws -> [PlexHistoryItem] {
        do {
            return try PlexHistoryParser.parseJSON(data)
        } catch {
            logParseFailure(data: data, response: response, error: error)
            if let items = PlexHistoryParser.parseXML(data) {
                return items
            }
            throw error
        }
    }

    private func logParseFailure(data: Data, response: HTTPURLResponse, error: Error) {
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        let prefix = String(data: data.prefix(2000), encoding: .utf8) ?? "<non-utf8>"
        print("Plex history parse failed (\(contentType)): \(error)")
        print("Plex history response preview: \(prefix)")
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
    let devices: [PlexDevice]

    private enum CodingKeys: String, CodingKey {
        case devices = "Device"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let array = try? container.decode([PlexDevice].self, forKey: .devices) {
            devices = array
        } else if let single = try? container.decode(PlexDevice.self, forKey: .devices) {
            devices = [single]
        } else {
            devices = []
        }
    }
}

private struct PlexDevice: Decodable {
    let provides: String?
    let accessToken: String?
    let connections: [PlexConnection]

    private enum CodingKeys: String, CodingKey {
        case provides
        case accessToken
        case connections = "Connection"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let provides = try? container.decode(String.self, forKey: .provides) {
            self.provides = provides
        } else if let providesArray = try? container.decode([String].self, forKey: .provides) {
            self.provides = providesArray.joined(separator: ",")
        } else {
            self.provides = nil
        }

        if let accessToken = try? container.decode(String.self, forKey: .accessToken) {
            self.accessToken = accessToken
        } else {
            self.accessToken = nil
        }

        if let array = try? container.decode([PlexConnection].self, forKey: .connections) {
            connections = array
        } else if let single = try? container.decode(PlexConnection.self, forKey: .connections) {
            connections = [single]
        } else {
            connections = []
        }
    }
}

private struct PlexConnection: Decodable {
    let uri: URL?
    let isLocal: Bool
    let isRelay: Bool
    let `protocol`: String?

    private enum CodingKeys: String, CodingKey {
        case uri
        case local
        case relay
        case `protocol` = "protocol"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let uriString = (try? container.decode(String.self, forKey: .uri)) ?? ""
        uri = URL(string: uriString)
        isLocal = PlexConnection.decodeBool(container: container, key: .local)
        isRelay = PlexConnection.decodeBool(container: container, key: .relay)
        `protocol` = try? container.decode(String.self, forKey: .protocol)
    }

    var isSecure: Bool {
        uri?.scheme == "https"
    }

    private static func decodeBool(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool {
        if let bool = try? container.decode(Bool.self, forKey: key) {
            return bool
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue == 1
        }
        if let string = try? container.decode(String.self, forKey: key) {
            return string == "1" || string.lowercased() == "true"
        }
        return false
    }
}
