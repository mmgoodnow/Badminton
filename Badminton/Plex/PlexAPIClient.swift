import Foundation

final class PlexAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchHistory(token: String, size: Int = 20) async throws -> [PlexHistoryItem] {
        var components = URLComponents(string: "https://plex.tv/api/v2/user/history")
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
        ]
        let url = components?.url ?? URL(string: "https://plex.tv/api/v2/user/history")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexConfig.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexConfig.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PlexHistoryResponse.self, from: data).items
    }
}
