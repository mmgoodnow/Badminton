import Foundation

struct TMDBAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func getV3<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        guard !TMDBConfig.apiKey.isEmpty else {
            throw TMDBAPIError.missingConfiguration("TMDB_API_KEY")
        }
        var components = URLComponents(url: TMDBConfig.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: TMDBConfig.apiKey))
        components?.queryItems = items
        guard let url = components?.url else {
            throw TMDBAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func postV4<T: Decodable, Body: Encodable>(path: String, body: Body, accessToken: String) async throws -> T {
        let url = TMDBConfig.apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func deleteV4<T: Decodable, Body: Encodable>(path: String, body: Body, accessToken: String) async throws -> T {
        let url = TMDBConfig.apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    func getImageConfiguration() async throws -> TMDBImageConfiguration {
        try await getV3(path: "/3/configuration")
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw TMDBAPIError.network(host: request.url?.host ?? "unknown", code: error.code)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(TMDBErrorResponse.self, from: data) {
                throw TMDBAPIError.server(statusCode: errorResponse.statusCode, message: errorResponse.statusMessage)
            }
            throw TMDBAPIError.httpStatus(httpResponse.statusCode)
        }
        return try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        }.value
    }
}

struct TMDBErrorResponse: Decodable {
    let statusCode: Int
    let statusMessage: String
}

enum TMDBAPIError: LocalizedError {
    case missingConfiguration(String)
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case server(statusCode: Int, message: String)
    case network(host: String, code: URLError.Code)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing configuration: \(key)"
        case .invalidURL:
            return "Invalid URL."
        case .invalidResponse:
            return "Invalid response."
        case .httpStatus(let code):
            return "Server returned status code \(code)."
        case .server(_, let message):
            return message
        case .network(let host, let code):
            return "Network error (\(code.rawValue)) while contacting \(host)."
        }
    }
}
