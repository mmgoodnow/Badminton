import Foundation

enum OverseerrConfig {
    static func normalizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolvedURL: URL?
        if trimmed.contains("://") {
            resolvedURL = URL(string: trimmed)
        } else {
            resolvedURL = URL(string: "https://\(trimmed)")
        }
        guard let url = resolvedURL else { return nil }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let lowercasedPath = components.path.lowercased()
        if let range = lowercasedPath.range(of: "/api/v1", options: .backwards),
           range.upperBound == lowercasedPath.endIndex {
            components.path = String(components.path[..<range.lowerBound])
        }

        return components.url
    }

    static func apiBaseURL(from baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
    }
}
