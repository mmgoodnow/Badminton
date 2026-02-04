import Foundation

struct OverseerrAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func signInWithPlex(baseURL: URL, plexToken: String) async throws -> (user: OverseerrUser, cookie: String) {
        let body = OverseerrPlexAuthRequest(authToken: plexToken)
        let url = try makeURL(baseURL: baseURL, path: "/auth/plex")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let response: (value: OverseerrUser, cookie: String?) = try await perform(request, includeCookies: true)
        guard let cookie = response.cookie else {
            throw OverseerrAPIError.missingSessionCookie
        }
        return (response.value, cookie)
    }

    func getPublicSettings(baseURL: URL) async throws -> OverseerrPublicSettings {
        try await get(baseURL: baseURL, path: "/settings/public")
    }

    func getMovie(baseURL: URL, tmdbID: Int, cookie: String?) async throws -> OverseerrMovieResponse {
        try await get(baseURL: baseURL, path: "/movie/\(tmdbID)", cookie: cookie)
    }

    func getTV(baseURL: URL, tmdbID: Int, cookie: String?) async throws -> OverseerrTVResponse {
        try await get(baseURL: baseURL, path: "/tv/\(tmdbID)", cookie: cookie)
    }

    func requestMedia(baseURL: URL, body: OverseerrRequestBody, cookie: String?) async throws -> OverseerrRequestResponse {
        try await post(baseURL: baseURL, path: "/request", body: body, cookie: cookie)
    }

    func get<T: Decodable>(baseURL: URL, path: String, cookie: String? = nil) async throws -> T {
        let url = try makeURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return try await perform(request, includeCookies: false).value
    }

    func post<T: Decodable, Body: Encodable>(
        baseURL: URL,
        path: String,
        body: Body,
        cookie: String? = nil,
        includeCookies: Bool = false
    ) async throws -> T {
        let url = try makeURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = try encoder.encode(body)
        let response: (value: T, cookie: String?) = try await perform(request, includeCookies: includeCookies)
        return response.value
    }

    private func makeURL(baseURL: URL, path: String) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = OverseerrConfig.apiBaseURL(from: baseURL)
        let url = base.appendingPathComponent(trimmedPath)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let result = components.url else {
            throw OverseerrAPIError.invalidURL
        }
        return result
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        includeCookies: Bool
    ) async throws -> (value: T, cookie: String?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw OverseerrAPIError.network(host: request.url?.host ?? "unknown", code: error.code)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverseerrAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(OverseerrErrorResponse.self, from: data) {
                if let message = errorResponse.message, !message.isEmpty {
                    throw OverseerrAPIError.server(message)
                }
                if let message = errorResponse.error, !message.isEmpty {
                    throw OverseerrAPIError.server(message)
                }
            }
            throw OverseerrAPIError.httpStatus(httpResponse.statusCode)
        }

        let cookieHeader: String?
        if includeCookies, let url = request.url {
            cookieHeader = cookies(from: httpResponse, url: url)
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
                .nilIfEmpty
        } else {
            cookieHeader = nil
        }

        let decoded = try decoder.decode(T.self, from: data)
        return (decoded, cookieHeader)
    }

    private func cookies(from response: HTTPURLResponse, url: URL) -> [HTTPCookie] {
        let headers: [String: String] = response.allHeaderFields.reduce(into: [:]) { result, item in
            if let key = item.key as? String, let value = item.value as? String {
                result[key] = value
            }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    }
}

struct OverseerrPlexAuthRequest: Encodable {
    let authToken: String
}

struct OverseerrUser: Decodable {
    let id: Int?
    let plexUsername: String?
    let username: String?
    let displayName: String?
}

struct OverseerrErrorResponse: Decodable {
    let message: String?
    let error: String?
}

enum OverseerrAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case server(String)
    case network(host: String, code: URLError.Code)
    case missingSessionCookie

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Overseerr URL."
        case .invalidResponse:
            return "Invalid response from Overseerr."
        case .httpStatus(let code):
            return "Overseerr returned status code \(code)."
        case .server(let message):
            return message
        case .network(let host, let code):
            return "Network error (\(code.rawValue)) while contacting \(host)."
        case .missingSessionCookie:
            return "Overseerr did not return a session cookie."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
